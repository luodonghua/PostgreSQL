-- peek_pgoutput_simple.sql - list the changes waiting in a pgoutput slot.
--
-- One read-only query. It creates nothing in the database: no functions, no tables, no slot copy.
-- Requirements:
--   * the slot uses pgoutput (native logical replication)
--   * the slot is NOT in use (no subscriber connected). Pause the subscription first if needed:
--       on the subscriber:  ALTER SUBSCRIPTION <sub> DISABLE;   ... later:  ALTER SUBSCRIPTION <sub> ENABLE;
--   * a role with REPLICATION (RDS/Aurora: rds_replication); PostgreSQL 10+
-- Peeking never consumes the slot: the subscriber receives the same changes when it reconnects.
--
-- Usage (on the PUBLISHER, connected to the slot's database):
--   psql -v slot=<slot> -f peek_pgoutput_simple.sql
--   psql -v slot=<slot> -v limit=1000 -v publication=pub1,pub2 -f peek_pgoutput_simple.sql
--
--   slot         slot name (required)
--   limit        changes to show (default 100). The slot is read up to the end of the
--                transaction in which the limit is reached, so a single large transaction is
--                always decoded completely (statement_timeout below protects against runaway reads).
--   timeout      statement_timeout for this session (default 300s)
--   publication  comma-separated publication names (default: all publications in this database)
--
-- Output, one row per change:
--   lsn          WAL position of the change
--   commit_time  commit timestamp of its transaction
--   schema_name, table_name, operation (INSERT / UPDATE / DELETE / TRUNCATE)
--   pk           replica-identity (primary key) columns and values. For UPDATE it is the old key
--                when the key itself changed; for REPLICA IDENTITY FULL tables it lists all columns.

\set QUIET 1
\set ON_ERROR_STOP 1
\if :{?slot}
\else
  \echo 'usage: psql -v slot=<slot name> [-v limit=100] [-v publication=p1,p2] -f peek_pgoutput_simple.sql'
  \quit
\endif
\if :{?limit}       \else \set limit 100       \endif
\if :{?publication} \else \set publication ''  \endif
\if :{?timeout}     \else \set timeout 300s     \endif
SET statement_timeout = :'timeout';

-- ---------------------------------------------------------------- checks (read-only)
SELECT s.slot_name IS NOT NULL                        AS found,
       coalesce(s.plugin = 'pgoutput', false)         AS is_pgoutput,
       coalesce(s.active, false)                      AS in_use,
       coalesce(s.active_pid::text, '')               AS pid,
       coalesce(s.database = current_database(), false) AS right_db,
       coalesce(s.database, '')                       AS slot_db,
       coalesce(s.plugin, '')                         AS plugin,
       coalesce(CASE WHEN :'publication' <> ''
                     THEN (SELECT string_agg(quote_ident(trim(x)), ',') FROM unnest(string_to_array(:'publication', ',')) x)
                     ELSE (SELECT string_agg(quote_ident(pubname), ',' ORDER BY pubname) FROM pg_publication) END, '') AS pubs
FROM (SELECT 1) one
LEFT JOIN pg_replication_slots s ON s.slot_name = :'slot' \gset chk_

\if :chk_found \else
  \echo 'ERROR: slot' :'slot' 'does not exist'
  \quit
\endif
\if :chk_right_db \else
  \echo 'ERROR: slot' :'slot' 'belongs to database' :'chk_slot_db' '- connect to that database'
  \quit
\endif
\if :chk_is_pgoutput \else
  \echo 'ERROR: slot' :'slot' 'uses plugin' :'chk_plugin' '- this script only decodes pgoutput (see slot_peek.sql for other plugins)'
  \quit
\endif
\if :chk_in_use
  \echo 'ERROR: slot' :'slot' 'is in use by PID' :'chk_pid' '- pause the subscription first (on the subscriber: ALTER SUBSCRIPTION <sub> DISABLE;)'
  \echo '       or use slot_peek.sql, which reads a temporary copy of an in-use slot on PostgreSQL 12+'
  \quit
\endif
SELECT :'chk_pubs' <> '' AS has_pubs \gset chk_
\if :chk_has_pubs \else
  \echo 'ERROR: no publication found in this database; pass -v publication=<name>'
  \quit
\endif

SELECT format('slot %s | publications %s | pending WAL %s (from %s) | limit %s',
              slot_name, :'chk_pubs',
              pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn)),
              confirmed_flush_lsn, :limit) AS line
FROM pg_replication_slots WHERE slot_name = :'slot' \gset hdr_
\echo :hdr_line

-- ---------------------------------------------------------------- decode
-- pgoutput protocol 1 (understood by every PostgreSQL 10+ server). Byte offsets are 0-based (get_byte).
WITH RECURSIVE
raw AS (                  -- the slot's pending messages, in order
  SELECT row_number() OVER () AS seq, lsn, data AS d, chr(get_byte(data, 0)) AS t
  -- the server-side limit counts protocol messages (begin/relation/commit too), so read enough of them
  -- for :limit changes; the final SELECT then shows at most :limit changes
  FROM pg_logical_slot_peek_binary_changes(:'slot', NULL, 3 * :limit + 100,
       'proto_version', '1', 'publication_names', :'chk_pubs')
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
               convert_from(substring(d FROM p_rel + 1 FOR position('\x00'::bytea IN substring(d FROM p_rel + 1)) - 1),
                            current_setting('server_encoding')) AS rel,
               p_rel + position('\x00'::bytea IN substring(d FROM p_rel + 1)) AS p_att
        FROM (SELECT seq, d,
                     ((get_byte(d,1)::bigint<<24)|(get_byte(d,2)<<16)|(get_byte(d,3)<<8)|get_byte(d,4)) AS relid,
                     convert_from(substring(d FROM 6 FOR position('\x00'::bytea IN substring(d FROM 6)) - 1),
                                  current_setting('server_encoding')) AS nsp,
                     5 + position('\x00'::bytea IN substring(d FROM 6)) AS p_rel
              FROM raw WHERE t = 'R') a) b
),
relcol AS (               -- walk the column list: flags byte, name cstring, type oid int32, typmod int32
  SELECT h.seq, 0 AS i, (get_byte(r.d, h.p_natts) << 8) | get_byte(r.d, h.p_natts + 1) AS natts,
         h.p_natts + 2 AS p, r.d
  FROM relhdr h JOIN raw r USING (seq)
  UNION ALL
  SELECT seq, i + 1, natts, p + 1 + position('\x00'::bytea IN substring(d FROM p + 2)) + 8, d
  FROM relcol WHERE i + 1 < natts
),
relinfo AS (
  SELECT h.seq, h.relid, h.nsp, h.rel,
         array_agg(convert_from(substring(c.d FROM c.p + 2 FOR position('\x00'::bytea IN substring(c.d FROM c.p + 2)) - 1),
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
           WHEN 'b' THEN '\x' || encode(substring(t.d FROM t.p + 6
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
)
SELECT x.lsn, to_char(tx.commit_time, 'YYYY-MM-DD HH24:MI:SS.US TZ') AS commit_time,
       ri.nsp AS schema_name, ri.rel AS table_name, x.operation, x.pk
FROM (
  SELECT c.seq, c.lsn, c.bseq, c.relid, c.operation, pk.pk
  FROM chg c LEFT JOIN pk USING (seq)
  UNION ALL
  SELECT seq + k * 0.001, lsn, bseq, relid, 'TRUNCATE', NULL FROM trunc
) x
LEFT JOIN txn tx ON tx.bseq = x.bseq
LEFT JOIN LATERAL (SELECT * FROM relinfo r WHERE r.relid = x.relid AND r.seq < x.seq ORDER BY r.seq DESC LIMIT 1) ri ON true
ORDER BY x.seq
LIMIT :limit;

SELECT :ROW_COUNT >= :limit AS more \gset chk_
\if :chk_more
  \echo 'Limit reached: more changes may be pending. Re-run with a larger -v limit=... to see them.'
\endif
