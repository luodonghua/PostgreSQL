-- slot_peek.sql - see what is waiting in a logical replication slot, without consuming it.
--
-- Run on the PUBLISHER, connected to the slot's database:
--   psql -v slot=<slot> -f slot_peek.sql
--   psql -v slot=<slot> -v format=sql -v since_lsn=<lsn from position.sql> -f slot_peek.sql > replay.sql
--
-- Variables (all optional except slot):
--   slot           slot to inspect
--   publication    comma-separated publication names (pgoutput decoder). Auto-detected when a
--                  native subscriber is connected to the slot.
--   decoder        auto (default) | pgoutput | text
--   limit          stop after about this many decoded rows (default 1000); applied at
--                  transaction / stream-chunk boundaries
--   wal_window_mb  text decoder: MB of WAL to scan after confirmed_flush_lsn (default 256)
--   since_lsn      subscriber's applied position (position.sql); marks changes already applied
--                  and leaves them out of format=sql
--   table          only this table (schema.table)
--   format         table (default: summary + changes) | summary | sql (replay statements)
--   per_txn        table format: changes shown per transaction (default 20)
--   timeout        statement_timeout (default 300s)
--   decoding_mem   logical_decoding_work_mem for this session on PG14+ (default 1MB)
--
-- Safety: PG12+ reads a TEMPORARY COPY of the slot (the original slot and its consumer are not
-- touched; nothing needs to be paused). PG10/11 can only peek a slot that is not in use.
-- Nothing is installed: helper functions live in pg_temp and disappear with the session.
-- Not supported: two-phase (PREPARE TRANSACTION) decoding.

\set QUIET 1
\set ON_ERROR_STOP 1
\if :{?slot}
\else
  \echo 'usage: psql -v slot=<slot name> [-v publication=p1,p2] [-v format=table|summary|sql] [-v since_lsn=X/Y] -f slot_peek.sql'
  \quit
\endif
\if :{?publication}  \else \set publication ''      \endif
\if :{?decoder}      \else \set decoder auto        \endif
\if :{?limit}        \else \set limit 1000          \endif
\if :{?wal_window_mb} \else \set wal_window_mb 256  \endif
\if :{?since_lsn}    \else \set since_lsn ''        \endif
\if :{?table}        \else \set table ''            \endif
\if :{?format}       \else \set format table        \endif
\if :{?per_txn}      \else \set per_txn 20          \endif
\if :{?timeout}      \else \set timeout 300s        \endif
\if :{?decoding_mem} \else \set decoding_mem 1MB    \endif

SET statement_timeout = :'timeout';
SET application_name = 'slot_peek.sql';
SET client_min_messages = warning;

-- ------------------------------------------------------------------ plan: which method, which decoder
CREATE FUNCTION pg_temp.sp_plan(p_slot text, p_pubs text, p_decoder text, p_window_mb int)
RETURNS TABLE (target text, do_copy boolean, copy_plugin text, use_pgoutput boolean, pubs text,
               method text, note text, server text, proto int, streaming boolean, upto text,
               confirmed text, current_lsn text, plugin text, in_use boolean)
LANGUAGE plpgsql AS $f$
DECLARE
  v_num int := current_setting('server_version_num')::int;
  s record;
  v_query text;
  v_free int;
  v_dec text := p_decoder;
BEGIN
  SELECT * INTO s FROM pg_replication_slots WHERE slot_name = p_slot;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'slot "%" does not exist on this server', p_slot;
  END IF;
  IF s.slot_type <> 'logical' THEN
    RAISE EXCEPTION 'slot "%" is a physical slot; only logical slots can be decoded', p_slot;
  END IF;
  IF s.database <> current_database() THEN
    RAISE EXCEPTION 'slot "%" belongs to database "%"; connect to that database', p_slot, s.database;
  END IF;
  server := current_setting('server_version');
  plugin := s.plugin;
  in_use := s.active;
  confirmed := s.confirmed_flush_lsn::text;
  current_lsn := pg_current_wal_lsn()::text;
  pubs := nullif(p_pubs, '');
  note := '';

  -- a native subscriber's walsender runs: START_REPLICATION ... publication_names '"p1","p2"'
  IF pubs IS NULL AND s.active_pid IS NOT NULL THEN
    SELECT query INTO v_query FROM pg_stat_activity WHERE pid = s.active_pid;
    pubs := (SELECT string_agg(coalesce(replace(m[1], '""', '"'), trim(m[2])), ',')
             -- native subscriber: publication_names '"p1","p2"'; pg_recvlogical: "publication_names" 'p1'
             FROM regexp_matches(substring(v_query from $re$"?publication_names"?\s+'((?:[^']|'')*)'$re$),
                                 '"((?:[^"]|"")*)"|([^,]+)', 'g') m);
  END IF;

  IF v_dec = 'auto' THEN
    IF s.plugin = 'pgoutput' AND pubs IS NOT NULL THEN
      v_dec := 'pgoutput';
    ELSE
      v_dec := 'text';
      IF s.plugin = 'pgoutput' THEN
        note := format('publication names unknown (%s): showing ALL tables. Pass -v publication=... to filter.',
                       CASE WHEN s.active THEN 'the subscriber''s command is not visible to this role (needs pg_read_all_stats)'
                            ELSE 'slot not in use by a native subscriber' END);
      END IF;
    END IF;
  END IF;
  IF v_dec = 'pgoutput' AND pubs IS NULL THEN
    RAISE EXCEPTION 'decoder pgoutput needs -v publication=... (could not detect it from an active walsender)';
  END IF;
  use_pgoutput := (v_dec = 'pgoutput');
  IF v_num < 120000 AND s.plugin <> (CASE WHEN use_pgoutput THEN 'pgoutput' ELSE 'test_decoding' END) THEN
    RAISE EXCEPTION 'on PostgreSQL % a % slot can only be read with its own plugin', server, s.plugin
      USING HINT = 'Use -v decoder=' || CASE WHEN s.plugin = 'pgoutput' THEN 'pgoutput' ELSE 'text' END
                   || ', or upgrade to PostgreSQL 12+ where the slot is copied first.';
  END IF;

  IF v_num >= 120000 THEN
    SELECT current_setting('max_replication_slots')::int - count(*) INTO v_free FROM pg_replication_slots;
    IF v_free < 1 THEN
      RAISE EXCEPTION 'no free replication slot for the temporary copy'
        USING HINT = 'Raise max_replication_slots or drop an unused slot.';
    END IF;
    target := 'slot_peek_' || pg_backend_pid();
    do_copy := true;
    copy_plugin := CASE WHEN use_pgoutput THEN 'pgoutput' ELSE 'test_decoding' END;
    method := format('temporary copy %s (%s); original slot untouched', target, copy_plugin);
  ELSE
    IF s.active THEN
      RAISE EXCEPTION 'slot "%" is in use by PID % and PostgreSQL % cannot copy slots (needs 12+)', p_slot, s.active_pid, server
        USING HINT = 'Pause the consumer, re-run, then resume it. Native subscription (on the subscriber): '
                     'ALTER SUBSCRIPTION <sub> DISABLE; ... ALTER SUBSCRIPTION <sub> ENABLE;  '
                     'pglogical: SELECT pglogical.alter_subscription_disable(''<sub>'', true); / _enable(...). '
                     'Other CDC tools: stop and restart the connector or task. Application writes are not affected.';
    END IF;
    target := p_slot;
    do_copy := false;
    copy_plugin := '';
    method := format('direct peek of the inactive slot (PostgreSQL %s)', server);
  END IF;
  proto := CASE WHEN v_num >= 140000 THEN 2 ELSE 1 END;
  streaming := use_pgoutput AND v_num >= 140000;
  -- (pg_lsn + numeric only exists from PG14; compute it by hand for older servers)
  upto := least((SELECT format('%s/%s', to_hex((v / 4294967296)::bigint), to_hex((v % 4294967296)::bigint))::pg_lsn
                 FROM (SELECT floor(pg_wal_lsn_diff(s.confirmed_flush_lsn, '0/0') + p_window_mb::numeric * 1024 * 1024) AS v) w),
                pg_current_wal_lsn())::text;
  RETURN NEXT;
END
$f$;

-- ------------------------------------------------------------------ pgoutput decoder
-- Emits kind 'X' (change), 'C' (commit), 'A' (abort of a streamed (sub)transaction).
CREATE FUNCTION pg_temp.sp_decode_pgoutput(p_slot text, p_pubs text, p_limit int, p_proto int, p_streaming boolean)
RETURNS TABLE (kind text, seq bigint, lsn text, xid bigint, subxid bigint, end_lsn pg_lsn,
               commit_time timestamptz, origin text, schema text, tbl text, op text,
               key jsonb, old jsonb, new jsonb, toast text[], detail text, cols text[])
LANGUAGE plpgsql AS $f$
DECLARE
  enc text := current_setting('server_encoding');
  opts text[];
  m record;
  b bytea;
  p int;               -- 0-based read offset
  t text;
  rels jsonb := '{}';
  rel jsonb;
  v_xid bigint;        -- current (non-streamed) transaction
  v_stream bigint;     -- open stream block (top-level xid)
  v_origin text;
  n int; i int; k int; len int;
  cname text; rcols jsonb; flags int; kch text;
  tup jsonb; tst text[]; okind text;
  pubs_quoted text;
BEGIN
  SELECT string_agg(quote_ident(trim(x)), ',') INTO pubs_quoted FROM unnest(string_to_array(p_pubs, ',')) x;
  opts := ARRAY['proto_version', p_proto::text, 'publication_names', pubs_quoted];
  IF p_streaming THEN
    opts := opts || ARRAY['streaming', 'on', 'messages', 'true'];
  END IF;
  seq := 0;
  FOR m IN SELECT c.lsn::text AS l, c.data FROM pg_logical_slot_peek_binary_changes(p_slot, NULL, p_limit, VARIADIC opts) c LOOP
    b := m.data; p := 1; t := chr(get_byte(b, 0));
    seq := seq + 1; lsn := m.l;
    kind := 'X'; xid := v_xid; subxid := NULL; end_lsn := NULL; commit_time := NULL; origin := v_origin;
    schema := NULL; tbl := NULL; op := NULL; key := NULL; old := NULL; new := NULL; toast := '{}'; detail := NULL; cols := NULL;
    IF v_stream IS NOT NULL AND t IN ('R','Y','I','U','D','T','M') THEN
      subxid := (get_byte(b,p)::bigint<<24)|(get_byte(b,p+1)<<16)|(get_byte(b,p+2)<<8)|get_byte(b,p+3); p := p + 4;
      xid := v_stream; origin := NULL;
    END IF;

    IF t = 'B' THEN
      v_xid := (get_byte(b,17)::bigint<<24)|(get_byte(b,18)<<16)|(get_byte(b,19)<<8)|get_byte(b,20);
      v_origin := NULL;
      CONTINUE;
    ELSIF t = 'C' OR t = 'c' THEN
      IF t = 'c' THEN   -- stream commit: xid, flags, commit_lsn, end_lsn, ts
        xid := (get_byte(b,1)::bigint<<24)|(get_byte(b,2)<<16)|(get_byte(b,3)<<8)|get_byte(b,4); p := 6;
      ELSE
        xid := v_xid; p := 2;
      END IF;
      p := p + 8;  -- commit_lsn (start of the commit record)
      end_lsn := (to_hex((get_byte(b,p)::bigint<<24)|(get_byte(b,p+1)<<16)|(get_byte(b,p+2)<<8)|get_byte(b,p+3))
                  || '/' || to_hex((get_byte(b,p+4)::bigint<<24)|(get_byte(b,p+5)<<16)|(get_byte(b,p+6)<<8)|get_byte(b,p+7)))::pg_lsn;
      p := p + 8;
      commit_time := timestamptz '2000-01-01 00:00:00+00' + make_interval(secs =>
          ((((get_byte(b,p)::bigint<<24)|(get_byte(b,p+1)<<16)|(get_byte(b,p+2)<<8)|get_byte(b,p+3)) << 32)
           | ((get_byte(b,p+4)::bigint<<24)|(get_byte(b,p+5)<<16)|(get_byte(b,p+6)<<8)|get_byte(b,p+7)))::numeric / 1000000);
      kind := 'C';
      IF t = 'C' THEN v_xid := NULL; END IF;
      RETURN NEXT;
      CONTINUE;
    ELSIF t = 'O' THEN
      p := p + 8;
      k := position('\x00'::bytea in substring(b from p + 1));
      v_origin := convert_from(substring(b from p + 1 for k - 1), enc);
      CONTINUE;
    ELSIF t = 'S' THEN
      v_stream := (get_byte(b,1)::bigint<<24)|(get_byte(b,2)<<16)|(get_byte(b,3)<<8)|get_byte(b,4);
      CONTINUE;
    ELSIF t = 'E' THEN
      v_stream := NULL;
      CONTINUE;
    ELSIF t = 'A' THEN
      kind := 'A';
      xid := (get_byte(b,1)::bigint<<24)|(get_byte(b,2)<<16)|(get_byte(b,3)<<8)|get_byte(b,4);
      subxid := (get_byte(b,5)::bigint<<24)|(get_byte(b,6)<<16)|(get_byte(b,7)<<8)|get_byte(b,8);
      RETURN NEXT;
      CONTINUE;
    ELSIF t = 'Y' THEN
      CONTINUE;
    ELSIF t = 'R' THEN
      k := ((get_byte(b,p)::bigint<<24)|(get_byte(b,p+1)<<16)|(get_byte(b,p+2)<<8)|get_byte(b,p+3)); p := p + 4;
      len := position('\x00'::bytea in substring(b from p + 1));
      schema := convert_from(substring(b from p + 1 for len - 1), enc); p := p + len;
      len := position('\x00'::bytea in substring(b from p + 1));
      tbl := convert_from(substring(b from p + 1 for len - 1), enc); p := p + len;
      detail := chr(get_byte(b, p)); p := p + 1;
      n := (get_byte(b,p) << 8) | get_byte(b,p+1); p := p + 2;
      rcols := '[]';
      FOR i IN 1..n LOOP
        flags := get_byte(b, p); p := p + 1;
        len := position('\x00'::bytea in substring(b from p + 1));
        cname := convert_from(substring(b from p + 1 for len - 1), enc); p := p + len + 8;  -- + typoid, typmod
        rcols := rcols || jsonb_build_object('n', cname, 'k', (flags & 1) = 1);
      END LOOP;
      rels := rels || jsonb_build_object(k::text, jsonb_build_object('s', schema, 't', tbl, 'c', rcols));
      CONTINUE;
    ELSIF t = 'M' THEN
      flags := get_byte(b, p); p := p + 1 + 8;
      len := position('\x00'::bytea in substring(b from p + 1));
      cname := convert_from(substring(b from p + 1 for len - 1), enc); p := p + len;
      len := ((get_byte(b,p)::bigint<<24)|(get_byte(b,p+1)<<16)|(get_byte(b,p+2)<<8)|get_byte(b,p+3)); p := p + 4;
      op := 'MESSAGE';
      new := jsonb_build_object('prefix', cname, 'content', convert_from(substring(b from p + 1 for len), enc));
      detail := CASE WHEN flags & 1 = 1 THEN 'transactional' ELSE 'non-transactional' END;
      RETURN NEXT;
      CONTINUE;
    ELSIF t = 'T' THEN
      n := ((get_byte(b,p)::bigint<<24)|(get_byte(b,p+1)<<16)|(get_byte(b,p+2)<<8)|get_byte(b,p+3)); p := p + 4;
      flags := get_byte(b, p); p := p + 1;
      op := 'TRUNCATE';
      detail := concat_ws(' ', CASE WHEN flags & 1 = 1 THEN 'CASCADE' END, CASE WHEN flags & 2 = 2 THEN 'RESTART IDENTITY' END);
      key := '{}';
      FOR i IN 1..n LOOP
        rel := rels -> (((get_byte(b,p)::bigint<<24)|(get_byte(b,p+1)<<16)|(get_byte(b,p+2)<<8)|get_byte(b,p+3))::text); p := p + 4;
        schema := rel->>'s'; tbl := rel->>'t';
        RETURN NEXT;
      END LOOP;
      CONTINUE;
    ELSIF t NOT IN ('I', 'U', 'D') THEN
      CONTINUE;   -- two-phase messages are not supported
    END IF;

    -- I / U / D
    rel := rels -> (((get_byte(b,p)::bigint<<24)|(get_byte(b,p+1)<<16)|(get_byte(b,p+2)<<8)|get_byte(b,p+3))::text); p := p + 4;
    schema := rel->>'s'; tbl := rel->>'t';
    SELECT array_agg(c->>'n' ORDER BY o) INTO cols FROM jsonb_array_elements(rel->'c') WITH ORDINALITY e(c, o);
    op := CASE t WHEN 'I' THEN 'INSERT' WHEN 'U' THEN 'UPDATE' ELSE 'DELETE' END;
    -- up to two tuples: [K|O old] then N new (insert/update), or K|O (delete)
    LOOP
      okind := chr(get_byte(b, p)); p := p + 1;
      n := (get_byte(b,p) << 8) | get_byte(b,p+1); p := p + 2;
      tup := '{}'; tst := '{}';
      FOR i IN 0..n - 1 LOOP
        cname := rel->'c'->i->>'n';
        kch := chr(get_byte(b, p)); p := p + 1;
        IF kch = 'n' THEN
          tup := tup || jsonb_build_object(cname, NULL);
        ELSIF kch = 'u' THEN
          tst := tst || cname;
        ELSE
          len := ((get_byte(b,p)::bigint<<24)|(get_byte(b,p+1)<<16)|(get_byte(b,p+2)<<8)|get_byte(b,p+3)); p := p + 4;
          IF kch = 't' THEN
            tup := tup || jsonb_build_object(cname, convert_from(substring(b from p + 1 for len), enc));
          ELSE
            tup := tup || jsonb_build_object(cname, '\x' || encode(substring(b from p + 1 for len), 'hex'));
          END IF;
          p := p + len;
        END IF;
      END LOOP;
      IF okind = 'K' THEN   -- old KEY tuple: non-key columns are sent as NULL, keep only the key
        SELECT coalesce(jsonb_object_agg(e.key, e.value), '{}') INTO tup FROM jsonb_each(tup) e
        WHERE EXISTS (SELECT 1 FROM jsonb_array_elements(rel->'c') c WHERE c->>'n' = e.key AND (c->>'k')::boolean);
      END IF;
      IF okind = 'N' THEN new := tup; toast := tst; EXIT;
      ELSE old := tup;
        EXIT WHEN t = 'D';
      END IF;
    END LOOP;
    SELECT coalesce(jsonb_object_agg(c->>'n', coalesce(old, new) -> (c->>'n')), '{}') INTO key
    FROM jsonb_array_elements(rel->'c') c
    WHERE (c->>'k')::boolean AND coalesce(old, new) ? (c->>'n');
    RETURN NEXT;
  END LOOP;
  kind := 'Z'; op := NULL; schema := NULL; tbl := NULL; xid := NULL;   -- trailer: rows returned by the peek
  RETURN NEXT;
END
$f$;

-- ------------------------------------------------------------------ text decoder (test_decoding)
CREATE FUNCTION pg_temp.sp_decode_text(p_slot text, p_upto text, p_limit int)
RETURNS TABLE (kind text, seq bigint, lsn text, xid bigint, subxid bigint, end_lsn pg_lsn,
               commit_time timestamptz, origin text, schema text, tbl text, op text,
               key jsonb, old jsonb, new jsonb, toast text[], detail text, cols text[])
LANGUAGE plpgsql AS $f$
DECLARE
  m record; mm text[]; tok text[]; target text; rest text; v text; cname text;
  pk jsonb;
BEGIN
  -- primary keys from the CURRENT catalog (test_decoding does not mark key columns)
  SELECT coalesce(jsonb_object_agg(format('%s.%s', n.nspname, c.relname), x.pkcols), '{}') INTO pk
  FROM (SELECT i.indrelid, jsonb_agg(a.attname ORDER BY k.ord) AS pkcols
        FROM pg_index i CROSS JOIN LATERAL unnest(i.indkey) WITH ORDINALITY k(attnum, ord)
        JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k.attnum
        WHERE i.indisprimary GROUP BY i.indrelid) x
  JOIN pg_class c ON c.oid = x.indrelid JOIN pg_namespace n ON n.oid = c.relnamespace;
  seq := 0;
  FOR m IN SELECT c.lsn::text AS l, c.xid::text::bigint AS x, c.data
           FROM pg_logical_slot_peek_changes(p_slot, p_upto::pg_lsn, p_limit,
                'include-xids', '1', 'include-timestamp', '1', 'skip-empty-xacts', '1') c LOOP
    seq := seq + 1; lsn := m.l; xid := m.x;
    kind := 'X'; subxid := NULL; end_lsn := NULL; commit_time := NULL; origin := NULL;
    schema := NULL; tbl := NULL; op := NULL; key := '{}'; old := NULL; new := NULL; toast := '{}'; detail := NULL; cols := '{}';
    IF m.data LIKE 'BEGIN %' THEN
      CONTINUE;
    ELSIF m.data LIKE 'COMMIT %' THEN
      kind := 'C';
      end_lsn := m.l::pg_lsn;    -- test_decoding reports the commit END position on this row
      commit_time := substring(m.data from '\(at (.+)\)')::timestamptz;
      RETURN NEXT;
      CONTINUE;
    ELSIF m.data LIKE 'message:%' THEN
      mm := regexp_match(m.data, '^message: transactional: (\d) prefix: (.*), sz: \d+ content:(.*)$');
      op := 'MESSAGE';
      new := jsonb_build_object('prefix', mm[2], 'content', mm[3]);
      detail := CASE WHEN mm[1] = '1' THEN 'transactional' ELSE 'non-transactional' END;
      RETURN NEXT;
      CONTINUE;
    END IF;
    mm := regexp_match(m.data, '^table (.+?): (INSERT|UPDATE|DELETE|TRUNCATE): ?(.*)$');
    IF mm IS NULL THEN CONTINUE; END IF;
    op := mm[2]; rest := mm[3];
    -- schema.table, either part may be double-quoted
    tok := regexp_match(mm[1], '^(?:"((?:[^"]|"")+)"|([^."]+))\.(?:"((?:[^"]|"")+)"|([^."]+))$');
    schema := coalesce(replace(tok[1], '""', '"'), tok[2]);
    tbl := coalesce(replace(tok[3], '""', '"'), tok[4]);
    IF op = 'TRUNCATE' THEN
      detail := nullif(rest, '(no-flags)');
      RETURN NEXT;
      CONTINUE;
    ELSIF rest = '(no-tuple-data)' THEN
      detail := 'no replica identity data';
      RETURN NEXT;
      CONTINUE;
    END IF;
    target := CASE WHEN op = 'DELETE' THEN 'old' ELSE 'new' END;
    FOR tok IN SELECT regexp_matches(rest,
        $re$(old-key:|new-tuple:)|(?:"((?:[^"]|"")+)"|([^["[:space:]]+))\[((?:[^]]|\](?!:))*)\]:(null|unchanged-toast-datum|B?'(?:[^']|'')*'|[^[:space:]]*)$re$, 'g') LOOP
      IF tok[1] IS NOT NULL THEN
        target := CASE WHEN tok[1] = 'old-key:' THEN 'old' ELSE 'new' END;
        CONTINUE;
      END IF;
      cname := coalesce(replace(tok[2], '""', '"'), tok[3]);
      IF NOT cname = ANY (cols) THEN cols := cols || cname; END IF;
      v := tok[5];
      IF v = 'unchanged-toast-datum' THEN toast := toast || cname; CONTINUE; END IF;
      v := CASE WHEN v = 'null' THEN NULL
                WHEN v LIKE 'B''%' THEN substr(v, 3, length(v) - 3)
                WHEN v LIKE '''%' THEN replace(substr(v, 2, length(v) - 2), '''''', '''')
                ELSE v END;
      IF target = 'old' THEN old := coalesce(old, '{}') || jsonb_build_object(cname, v);
      ELSE new := coalesce(new, '{}') || jsonb_build_object(cname, v); END IF;
    END LOOP;
    IF pk ? (schema || '.' || tbl) THEN
      SELECT coalesce(jsonb_object_agg(c, coalesce(old, new) -> c), '{}') INTO key
      FROM jsonb_array_elements_text(pk -> (schema || '.' || tbl)) c WHERE coalesce(old, new) ? c;
    ELSE
      key := coalesce(old, '{}');
    END IF;
    RETURN NEXT;
  END LOOP;
  kind := 'Z'; op := NULL; schema := NULL; tbl := NULL; xid := NULL;   -- trailer: rows returned by the peek
  RETURN NEXT;
END
$f$;

-- ------------------------------------------------------------------ replay statement for one change
CREATE FUNCTION pg_temp.sp_sql(p_schema text, p_tbl text, p_op text, p_key jsonb, p_new jsonb, p_detail text, p_cols text[])
RETURNS text LANGUAGE sql AS $f$
  SELECT CASE p_op
    WHEN 'INSERT' THEN format('INSERT INTO %I.%I (%s) VALUES (%s);', p_schema, p_tbl,
         (SELECT string_agg(quote_ident(k), ', ' ORDER BY coalesce(array_position(p_cols, k), 999), k) FROM jsonb_object_keys(p_new) k),
         (SELECT string_agg(quote_nullable(p_new ->> k), ', ' ORDER BY coalesce(array_position(p_cols, k), 999), k) FROM jsonb_object_keys(p_new) k))
    WHEN 'UPDATE' THEN CASE WHEN p_key = '{}' THEN format('-- UPDATE on %I.%I skipped: no key (replica identity) data', p_schema, p_tbl)
         ELSE format('UPDATE %I.%I SET %s WHERE %s;', p_schema, p_tbl,
         (SELECT string_agg(format('%I = %s', k, quote_nullable(p_new ->> k)), ', ' ORDER BY coalesce(array_position(p_cols, k), 999), k) FROM jsonb_object_keys(p_new) k),
         (SELECT string_agg(CASE WHEN p_key ->> k IS NULL THEN format('%I IS NULL', k)
                                 ELSE format('%I = %L', k, p_key ->> k) END, ' AND ' ORDER BY coalesce(array_position(p_cols, k), 999), k) FROM jsonb_object_keys(p_key) k)) END
    WHEN 'DELETE' THEN CASE WHEN p_key = '{}' THEN format('-- DELETE on %I.%I skipped: no key (replica identity) data', p_schema, p_tbl)
         ELSE format('DELETE FROM %I.%I WHERE %s;', p_schema, p_tbl,
         (SELECT string_agg(CASE WHEN p_key ->> k IS NULL THEN format('%I IS NULL', k)
                                 ELSE format('%I = %L', k, p_key ->> k) END, ' AND ' ORDER BY coalesce(array_position(p_cols, k), 999), k) FROM jsonb_object_keys(p_key) k)) END
    WHEN 'TRUNCATE' THEN format('TRUNCATE %I.%I%s;', p_schema, p_tbl, coalesce(' ' || nullif(p_detail, ''), ''))
    ELSE '-- logical message: ' || p_new::text END
$f$;

-- ------------------------------------------------------------------ run
SELECT * FROM pg_temp.sp_plan(:'slot', :'publication', :'decoder', :wal_window_mb) \gset sp_

\if :sp_do_copy
SELECT slot_name AS copied FROM pg_copy_logical_replication_slot(:'slot', :'sp_target', true, :'sp_copy_plugin') \gset sp_
\endif
\if :sp_streaming
SET logical_decoding_work_mem = :'decoding_mem';
\endif

\if :sp_use_pgoutput
CREATE TEMP TABLE sp_raw AS SELECT * FROM pg_temp.sp_decode_pgoutput(:'sp_target', :'sp_pubs', :limit, :sp_proto, :'sp_streaming'::boolean);
\else
CREATE TEMP TABLE sp_raw AS SELECT * FROM pg_temp.sp_decode_text(:'sp_target', :'sp_upto', :limit);
\endif

\if :sp_do_copy
SELECT pg_drop_replication_slot(:'sp_target') AS dropped \gset sp_
\endif

-- one row per change, with its transaction's commit (if seen) and the applied flag
CREATE TEMP TABLE sp_changes AS
SELECT x.seq, x.xid, c.end_lsn, c.commit_time,
       CASE WHEN c.xid IS NULL THEN 'open' ELSE 'committed' END AS status,
       c.end_lsn IS NOT NULL AND nullif(:'since_lsn', '') IS NOT NULL
         AND c.end_lsn <= nullif(:'since_lsn', '')::pg_lsn AS applied,
       x.origin, x.schema, x.tbl, x.op, x.key, x.old, x.new, x.toast, x.detail, x.cols,
       CASE WHEN x.tbl IS NULL THEN '-' ELSE format('%s.%s', x.schema, x.tbl) END AS table_name
FROM sp_raw x
LEFT JOIN sp_raw c ON c.kind = 'C' AND c.xid = x.xid
WHERE x.kind = 'X'
  AND NOT EXISTS (SELECT 1 FROM sp_raw a WHERE a.kind = 'A' AND a.xid = x.xid
                  AND (a.subxid = a.xid OR a.subxid = x.subxid))
  AND (:'table' = '' OR x.tbl IS NULL OR format('%s.%s', x.schema, x.tbl) = :'table' OR x.tbl = :'table');

\if :sp_use_pgoutput
  \set sp_decoder_text 'pgoutput (publications: ' :sp_pubs ')'
\else
  \set sp_decoder_text 'text via test_decoding (all tables of the database); WAL scanned up to ' :sp_upto
\endif

SELECT :'format' = 'sql' AS is_sql, :'format' = 'summary' AS is_summary \gset sp_

\if :sp_is_sql
  \pset tuples_only on
  \pset format unaligned
  SELECT '-- Generated by slot_peek.sql from slot ' || :'slot' || ', ' || now()::timestamptz(0)
  UNION ALL SELECT '-- Review before running. Unchanged TOAST columns are left out of UPDATE SET lists.'
  UNION ALL SELECT '-- Only transactions with end_lsn after ' || :'since_lsn' || ' (not yet applied by the subscriber).'
         WHERE :'since_lsn' <> '';
  SELECT CASE WHEN rn = 1 THEN format(E'\n-- xid %s committed %s, end_lsn %s\nBEGIN;\n', xid, commit_time, end_lsn) ELSE '' END
         || pg_temp.sp_sql(schema, tbl, op, key, new, detail, cols)
         || CASE WHEN rn = cnt THEN E'\nCOMMIT;' ELSE '' END
  FROM (SELECT *, row_number() OVER w AS rn, count(*) OVER (PARTITION BY xid) AS cnt
        FROM sp_changes WHERE status = 'committed' AND NOT applied
        WINDOW w AS (PARTITION BY xid ORDER BY seq)) s
  ORDER BY end_lsn, seq;
  SELECT format('-- %s changes of transactions not committed in the scanned range were not included.', count(*))
  FROM sp_changes WHERE status = 'open' HAVING count(*) > 0;
\else
  \pset footer off
  \pset tuples_only on
  \pset format unaligned
  \pset fieldsep ' : '
  SELECT 'Slot           ', format('%s  (plugin %s, %s)', :'slot', :'sp_plugin', CASE WHEN :'sp_in_use' THEN 'in use' ELSE 'not in use' END)
  UNION ALL SELECT 'Server         ', 'PostgreSQL ' || :'sp_server'
  UNION ALL SELECT 'Method         ', :'sp_method'
  UNION ALL SELECT 'Decoder        ', :'sp_decoder_text'
  UNION ALL SELECT 'Pending WAL    ', format('%s  (confirmed_flush_lsn %s -> current %s)',
                   pg_size_pretty(pg_wal_lsn_diff(:'sp_current_lsn', :'sp_confirmed')), :'sp_confirmed', :'sp_current_lsn')
  UNION ALL SELECT 'Note           ', :'sp_note' WHERE :'sp_note' <> ''
  UNION ALL SELECT 'Rows decoded   ', format('%s (limit %s; applied at transaction or stream-chunk boundaries)', (SELECT max(seq) FROM sp_raw WHERE kind = 'Z'), :limit)
  UNION ALL SELECT 'Stopped early  ', 'limit reached - more changes may follow; raise -v limit=... to see them'
                   WHERE (SELECT max(seq) FROM sp_raw WHERE kind = 'Z') >= :limit
  UNION ALL SELECT 'Transactions   ', format('%s committed, %s open (no commit seen in the scanned range)',
                   count(DISTINCT xid) FILTER (WHERE status = 'committed'), count(DISTINCT xid) FILTER (WHERE status = 'open'))
                   FROM sp_changes WHERE op <> 'MESSAGE'
  UNION ALL SELECT 'Commit time    ', format('%s  ..  %s', min(commit_time), max(commit_time)) FROM sp_changes HAVING count(commit_time) > 0
  UNION ALL SELECT 'Commit end LSN ', format('%s  ..  %s',   -- min/max(pg_lsn) only exist from PG13
                   (SELECT end_lsn FROM sp_changes WHERE end_lsn IS NOT NULL ORDER BY end_lsn LIMIT 1),
                   (SELECT end_lsn FROM sp_changes WHERE end_lsn IS NOT NULL ORDER BY end_lsn DESC LIMIT 1))
                   WHERE EXISTS (SELECT 1 FROM sp_changes WHERE end_lsn IS NOT NULL)
  UNION ALL SELECT 'Not yet applied', format('%s changes in %s transactions after %s', count(*), count(DISTINCT xid), :'since_lsn')
                   FROM sp_changes WHERE NOT applied AND op <> 'MESSAGE' HAVING :'since_lsn' <> ''
  UNION ALL SELECT 'Largest txn    ', format('xid %s with %s changes', xid, n)
                   FROM (SELECT xid, count(*) n FROM sp_changes WHERE op <> 'MESSAGE' GROUP BY xid ORDER BY 2 DESC LIMIT 1) z
  UNION ALL SELECT 'Logical msgs   ', count(*)::text FROM sp_changes WHERE op = 'MESSAGE' HAVING count(*) > 0;
  \pset tuples_only off
  \pset format aligned
  \echo
  SELECT NOT EXISTS (SELECT 1 FROM sp_changes) AS nothing \gset sp_
  \if :sp_nothing
    \echo 'No pending changes in the scanned range.'
    \quit
  \endif
  SELECT table_name AS "table",
         count(*) FILTER (WHERE op = 'INSERT') AS insert, count(*) FILTER (WHERE op = 'UPDATE') AS update,
         count(*) FILTER (WHERE op = 'DELETE') AS delete, count(*) FILTER (WHERE op = 'TRUNCATE') AS truncate
  FROM sp_changes WHERE op <> 'MESSAGE' GROUP BY 1 ORDER BY 1;
  \if :sp_is_summary
  \else
    SELECT end_lsn, to_char(commit_time, 'YYYY-MM-DD HH24:MI:SS.MS') AS commit_time, xid,
           status || CASE WHEN applied THEN ' (applied)' ELSE '' END AS status,
           table_name AS "table", op,
           coalesce((SELECT '{' || string_agg(format('%s: %s', to_json(k), to_json(key ->> k)), ', '
                                                ORDER BY coalesce(array_position(cols, k), 999)) || '}'
                     FROM jsonb_object_keys(key) k), '') AS key,
           left(CASE op
             WHEN 'INSERT' THEN (SELECT string_agg(format('%s=%s', k, coalesce(new ->> k, 'NULL')), ', ' ORDER BY o)
                                 FROM unnest(cols) WITH ORDINALITY u(k, o) WHERE new ? k)
             WHEN 'UPDATE' THEN coalesce((SELECT string_agg(CASE WHEN old IS NOT NULL AND old ? k AND (old ->> k) IS DISTINCT FROM (new ->> k)
                                                                 THEN format('%s: %s -> %s', k, coalesce(old ->> k, 'NULL'), coalesce(new ->> k, 'NULL'))
                                                                 WHEN old IS NULL AND NOT key ? k THEN format('%s=%s', k, coalesce(new ->> k, 'NULL')) END, ', ' ORDER BY o)
                                          FROM unnest(cols) WITH ORDINALITY u(k, o) WHERE new ? k), '')
                                || CASE WHEN toast <> '{}' THEN format(' (unchanged TOAST: %s)', array_to_string(toast, ', ')) ELSE '' END
             WHEN 'MESSAGE' THEN detail || ' ' || new::text
             ELSE coalesce(detail, '') END, 70) AS change
    FROM (SELECT *, row_number() OVER (PARTITION BY xid ORDER BY seq) AS rn FROM sp_changes) s
    WHERE rn <= :per_txn OR :per_txn = 0
    ORDER BY end_lsn NULLS LAST, seq;
    \pset tuples_only on
    SELECT format('... %s more changes of xid %s not shown (-v per_txn=%s; use -v format=sql for all)', count(*) - :per_txn, xid, :per_txn)
    FROM sp_changes GROUP BY xid HAVING :per_txn > 0 AND count(*) > :per_txn;
  \endif
\endif
