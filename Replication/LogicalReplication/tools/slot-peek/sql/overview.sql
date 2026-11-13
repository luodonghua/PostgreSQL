-- overview.sql - list logical replication slots and how to inspect each one.
-- Run on the PUBLISHER (any database):  psql -f overview.sql
-- Read-only. Works on PostgreSQL 10+.

\set QUIET 1
\pset footer off
SELECT format('PostgreSQL %s, database %s, free replication slots: %s',
              current_setting('server_version'), current_database(),
              current_setting('max_replication_slots')::int - (SELECT count(*) FROM pg_replication_slots))
       AS header \gset ov_
\echo :ov_header

SELECT s.slot_name                                              AS slot,
       s.plugin,
       s.database,
       CASE WHEN s.active THEN format('pid %s %s %s', s.active_pid, a.application_name, host(a.client_addr))
            ELSE '-' END                                        AS "in use by",
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), s.confirmed_flush_lsn)) AS "pending WAL",
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), s.restart_lsn))         AS "retained WAL",
       CASE
         WHEN s.database <> current_database()
           THEN format('connect to database %s', s.database)
         WHEN current_setting('server_version_num')::int >= 120000
           THEN format('psql -v slot=%s -f slot_peek.sql', s.slot_name)
                || CASE WHEN s.plugin = 'pgoutput' THEN '' ELSE '   (text decoder)' END
         WHEN s.active
           THEN 'pause the consumer first (README), then slot_peek.sql'
         WHEN s.plugin IN ('pgoutput', 'test_decoding')
           THEN format('psql -v slot=%s -f slot_peek.sql', s.slot_name)
         ELSE format('not supported on PostgreSQL < 12 (%s)', s.plugin)
       END                                                      AS "how to inspect"
FROM pg_replication_slots s
LEFT JOIN pg_stat_activity a ON a.pid = s.active_pid
WHERE s.slot_type = 'logical'
ORDER BY 1;
