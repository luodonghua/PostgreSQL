-- peek_pgoutput_ide.sql - list the changes waiting in a pgoutput slot. For SQL IDEs (pgAdmin, DBeaver, DataGrip, ...).
--
-- HOW TO USE
--   1. Connect to the PUBLISHER, to the database the slot belongs to.
--   2. Edit the three values in the "params" block just below.
--   3. Run the whole statement (pgAdmin: F5; DBeaver: Ctrl+Enter, with the cursor in the statement).
--
-- It is ONE read-only SELECT. It creates nothing: no functions, tables or slot copies, so it needs
-- no change approval. No psql commands, so any client can run it.
--
-- ASSUMES
--   * a pgoutput slot (native logical replication)
--   * the slot is NOT in use. Pause the subscription first:  ALTER SUBSCRIPTION <sub> DISABLE;
--     on the subscriber, and  ENABLE  afterwards. Application writes continue meanwhile.
--   * a role with REPLICATION (RDS/Aurora: rds_replication); PostgreSQL 10+
-- Peeking never consumes the slot.
--
-- OUTPUT (one row per change). The first row (no lsn) describes the slot; problems are reported there too.
--   lsn, commit_time, schema_name, table_name, operation, pk, and note
--   pk = replica-identity (primary key) columns; for UPDATE it is the old key if the key changed.
--
-- Set a longer statement timeout in the IDE if you read a very large transaction:  SET statement_timeout = '10min';

WITH RECURSIVE params AS (
  SELECT 'my_slot'::text AS slot_name,      -- <== EDIT: the replication slot name
         100             AS row_limit,      -- <== EDIT: changes to show (a transaction is always read to its end)
         ''::text        AS publications    -- <== EDIT (optional): comma-separated publication names; empty = all publications
),
chk AS (                  -- checks, and the first problem found (NULL = all good)
  SELECT p.slot_name, p.row_limit, s.slot_name AS found, s.plugin, s.active, s.active_pid, s.database,
         s.confirmed_flush_lsn,
         coalesce(CASE WHEN p.publications <> ''
                       THEN (SELECT string_agg(quote_ident(trim(x)), ',') FROM unnest(string_to_array(p.publications, ',')) x)
                       ELSE (SELECT string_agg(quote_ident(pubname), ',' ORDER BY pubname) FROM pg_publication) END, '') AS pubs,
         CASE WHEN s.slot_name IS NULL THEN format('ERROR: slot "%s" does not exist', p.slot_name)
              WHEN s.database <> current_database() THEN format('ERROR: slot "%s" belongs to database "%s"; connect to that database', p.slot_name, s.database)
              WHEN s.plugin <> 'pgoutput' THEN format('ERROR: slot "%s" uses plugin "%s"; this script only decodes pgoutput', p.slot_name, s.plugin)
              WHEN s.active THEN format('ERROR: slot "%s" is in use by PID %s; pause the subscription first (on the subscriber: ALTER SUBSCRIPTION <sub> DISABLE)', p.slot_name, s.active_pid)
         END AS problem
  FROM params p
  LEFT JOIN pg_replication_slots s ON s.slot_name = p.slot_name
),
chk2 AS (
  SELECT c.*, CASE WHEN c.problem IS NULL AND c.pubs = ''
                   THEN 'ERROR: no publication found in this database; set publications in the params block'
                   ELSE c.problem END AS problem2
  FROM chk c
),
raw AS (                  -- the slot's pending messages, in order (only when every check passed)
  SELECT row_number() OVER () AS seq, c.lsn, c.data AS d, chr(get_byte(c.data, 0)) AS t
  FROM chk2 k
  CROSS JOIN LATERAL pg_logical_slot_peek_binary_changes(k.slot_name, NULL, 3 * k.row_limit + 100,
       'proto_version', '1', 'publication_names', k.pubs) c
  WHERE k.problem2 IS NULL
),
msg AS (                  -- attach each message to the Begin of its transaction
  SELECT r.*, max(seq) FILTER (WHERE t = 'B') OVER (ORDER BY seq) AS bseq
  FROM raw r
),
txn AS (                  -- Begin: final_lsn int64 @1, commit timestamp int64 @9 (microseconds since 2000-01-01 UTC)
  SELECT seq AS bseq,
         timestamptz '2000-01-01 00:00:00+00' + interval '1 microsecond' *
           (((get_byte(d,9)::bigint<<24)|(get_byte(d,10)<<16)|(get_byte(d,11)<<8)|get_byte(d,12)) * 4294967296
            + ((get_byte(d,13)::bigint<<24)|(get_byte(d,14)<<16)|(get_byte(d,15)<<8)|get_byte(d,16))) AS commit_time
  FROM raw WHERE t = 'B'
),
relhdr AS (               -- Relation: relid int32 @1, namespace cstring, relname cstring, replident byte, natts int16, columns
  SELECT seq, relid, nsp, rel, p_att + 1 AS p_natts
  FROM (SELECT seq, d, relid, nsp,
               convert_from(substring(d FROM p_rel + 1 FOR position(decode('00', 'hex') IN substring(d FROM p_rel + 1)) - 1),
                            current_setting('server_encoding')) AS rel,
               p_rel + position(decode('00', 'hex') IN substring(d FROM p_rel + 1)) AS p_att
        FROM (SELECT seq, d,
                     ((get_byte(d,1)::bigint<<24)|(get_byte(d,2)<<16)|(get_byte(d,3)<<8)|get_byte(d,4)) AS relid,
                     convert_from(substring(d FROM 6 FOR position(decode('00', 'hex') IN substring(d FROM 6)) - 1),
                                  current_setting('server_encoding')) AS nsp,
                     5 + position(decode('00', 'hex') IN substring(d FROM 6)) AS p_rel
              FROM raw WHERE t = 'R') a) b
),
relcol AS (               -- walk the column list: flags byte, name cstring, type oid int32, typmod int32
  SELECT h.seq, 0 AS i, (get_byte(r.d, h.p_natts) << 8) | get_byte(r.d, h.p_natts + 1) AS natts,
         h.p_natts + 2 AS p, r.d
  FROM relhdr h JOIN raw r USING (seq)
  UNION ALL
  SELECT seq, i + 1, natts, p + 1 + position(decode('00', 'hex') IN substring(d FROM p + 2)) + 8, d
  FROM relcol WHERE i + 1 < natts
),
relinfo AS (
  SELECT h.seq, h.relid, h.nsp, h.rel,
         array_agg(convert_from(substring(c.d FROM c.p + 2 FOR position(decode('00', 'hex') IN substring(c.d FROM c.p + 2)) - 1),
                                current_setting('server_encoding')) ORDER BY c.i) AS colnames,
         array_agg((get_byte(c.d, c.p) & 1) = 1 ORDER BY c.i) AS iskey
  FROM relhdr h JOIN relcol c USING (seq)
  GROUP BY h.seq, h.relid, h.nsp, h.rel
),
chg AS (                  -- Insert / Update / Delete: relid int32 @1, first tuple marker @5, ncols int16 @6
  SELECT m.seq, m.lsn, m.bseq, m.d,
         CASE m.t WHEN 'I' THEN 'INSERT' WHEN 'U' THEN 'UPDATE' ELSE 'DELETE' END AS operation,
         ((get_byte(m.d,1)::bigint<<24)|(get_byte(m.d,2)<<16)|(get_byte(m.d,3)<<8)|get_byte(m.d,4)) AS relid
  FROM msg m WHERE m.t IN ('I', 'U', 'D')
),
tup AS (                  -- walk the first tuple (it holds the key): per column a kind byte n/u/t/b, t/b: int32 len + data
  SELECT seq, d, 0 AS i, (get_byte(d,6) << 8) | get_byte(d,7) AS ncols, 8 AS p
  FROM chg
  UNION ALL
  SELECT seq, d, i + 1, ncols,
         CASE WHEN chr(get_byte(d, p)) IN ('t', 'b')
              THEN p + 5 + ((get_byte(d,p+1)<<24)|(get_byte(d,p+2)<<16)|(get_byte(d,p+3)<<8)|get_byte(d,p+4))
              ELSE p + 1 END
  FROM tup WHERE i + 1 < ncols
),
keyval AS (               -- key columns only
  SELECT c.seq, t.i, ri.colnames[t.i + 1] AS col,
         CASE chr(get_byte(t.d, t.p))
           WHEN 't' THEN convert_from(substring(t.d FROM t.p + 6
                         FOR ((get_byte(t.d,t.p+1)<<24)|(get_byte(t.d,t.p+2)<<16)|(get_byte(t.d,t.p+3)<<8)|get_byte(t.d,t.p+4))),
                         current_setting('server_encoding'))
           WHEN 'b' THEN chr(92) || 'x' || encode(substring(t.d FROM t.p + 6
                         FOR ((get_byte(t.d,t.p+1)<<24)|(get_byte(t.d,t.p+2)<<16)|(get_byte(t.d,t.p+3)<<8)|get_byte(t.d,t.p+4))), 'hex')
         END AS val
  FROM chg c
  JOIN tup t USING (seq)
  CROSS JOIN LATERAL (SELECT * FROM relinfo r WHERE r.relid = c.relid AND r.seq < c.seq ORDER BY r.seq DESC LIMIT 1) ri
  WHERE ri.iskey[t.i + 1]
),
pk AS (
  SELECT seq, string_agg(format('%s=%s', col, coalesce(val, 'NULL')), ', ' ORDER BY i) AS pk
  FROM keyval GROUP BY seq
),
trunc AS (                -- Truncate: nrels int32 @1, options byte @5, relids int32 @6..
  SELECT m.seq, m.lsn, m.bseq, k,
         ((get_byte(m.d,6+4*k)::bigint<<24)|(get_byte(m.d,7+4*k)<<16)|(get_byte(m.d,8+4*k)<<8)|get_byte(m.d,9+4*k)) AS relid
  FROM msg m
  CROSS JOIN LATERAL generate_series(0, ((get_byte(m.d,1)<<24)|(get_byte(m.d,2)<<16)|(get_byte(m.d,3)<<8)|get_byte(m.d,4)) - 1) k
  WHERE m.t = 'T'
),
changes AS (
  SELECT x.seq, x.lsn, tx.commit_time::text AS commit_time,
         ri.nsp AS schema_name, ri.rel AS table_name, x.operation, x.pk,
         row_number() OVER (ORDER BY x.seq) AS rn
  FROM (
    SELECT c.seq, c.lsn, c.bseq, c.relid, c.operation, pk.pk
    FROM chg c LEFT JOIN pk USING (seq)
    UNION ALL
    SELECT seq + k * 0.001, lsn, bseq, relid, 'TRUNCATE', NULL FROM trunc
  ) x
  LEFT JOIN txn tx ON tx.bseq = x.bseq
  LEFT JOIN LATERAL (SELECT * FROM relinfo r WHERE r.relid = x.relid AND r.seq < x.seq ORDER BY r.seq DESC LIMIT 1) ri ON true
)
SELECT lsn, commit_time, schema_name, table_name, operation, pk, note
FROM (
  -- row 1: what is being read, or why nothing is returned
  SELECT 0 AS ord, NULL::pg_lsn AS lsn, NULL::text AS commit_time, NULL::text AS schema_name, NULL::text AS table_name,
         NULL::text AS operation, NULL::text AS pk,
         coalesce(k.problem2,
                  format('slot %s | publications %s | pending WAL %s (from %s) | showing up to %s changes',
                         k.slot_name, k.pubs,
                         pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), k.confirmed_flush_lsn)),
                         k.confirmed_flush_lsn, k.row_limit)) AS note
  FROM chk2 k
  UNION ALL
  SELECT 1 + c.rn, c.lsn::pg_lsn, c.commit_time, c.schema_name, c.table_name, c.operation, c.pk, NULL
  FROM changes c, chk2 k
  WHERE c.rn <= k.row_limit
  UNION ALL
  SELECT 2147483647, NULL, NULL, NULL, NULL, NULL, NULL,
         'Limit reached: more changes may be pending. Increase row_limit in the params block to see them.'
  FROM chk2 k WHERE (SELECT count(*) FROM changes) > k.row_limit
) out
ORDER BY ord;
