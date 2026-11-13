-- position.sql - how far each subscription has applied.
-- Run on the SUBSCRIBER, in the subscription's database:  psql -f position.sql
-- Use "applied up to" as since_lsn for slot_peek.sql on the publisher: changes with an end_lsn
-- at or below it are already applied. Read-only. Works on PostgreSQL 10+.

\set QUIET 1
\pset footer off
SELECT s.subname                                  AS subscription,
       s.subenabled                               AS enabled,
       s.subslotname                              AS slot,
       coalesce(o.remote_lsn::text, '-')          AS "applied up to",
       array_to_string(s.subpublications, ',')    AS publications
FROM pg_subscription s
LEFT JOIN pg_replication_origin_status o ON o.external_id = 'pg_' || s.oid
WHERE s.subdbid = (SELECT oid FROM pg_database WHERE datname = current_database())
ORDER BY 1;
