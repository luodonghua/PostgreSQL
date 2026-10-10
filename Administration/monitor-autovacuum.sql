SELECT relname, last_vacuum, last_autovacuum,n_dead_tup FROM pg_stat_user_tables;

/*

mytest=> SELECT relname, last_vacuum, last_autovacuum,n_dead_tup FROM pg_stat_user_tables;
     relname      |          last_vacuum          | last_autovacuum | n_dead_tup 
------------------+-------------------------------+-----------------+------------
 pgbench_branches | 2021-11-28 11:52:06.075918+00 |                 |          0
 pgbench_accounts | 2021-11-28 11:52:26.421433+00 |                 |          0
 pgbench_history  | 2021-11-28 11:52:26.874922+00 |                 |          0
 pgbench_tellers  | 2021-11-28 11:52:06.35523+00  |                 |          0
(4 rows)


-- monitor the rds postgresql log
-- aws logs tail "/aws/rds/instance/database-1/postgresql"  --follow

2021-11-28T12:06:39+00:00 database-1.0 2021-11-28 12:06:39 UTC::@:[11761]:LOCATION:  do_analyze_rel, analyze.c:714
2021-11-28T12:06:54+00:00 database-1.0 2021-11-28 12:06:54 UTC::@:[12026]:LOG:  00000: automatic vacuum of table "mytest.public.pgbench_branches": index scans: 0
     pages: 0 removed, 1 remain, 0 skipped due to pins, 0 skipped frozen
     tuples: 71 removed, 100 remain, 0 are dead but not yet removable, oldest xmin: 731
     buffer usage: 46 hits, 0 misses, 0 dirtied
     avg read rate: 0.000 MB/s, avg write rate: 0.000 MB/s
     system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.00 s
     WAL usage: 2 records, 0 full page images, 585 bytes
2021-11-28T12:06:54+00:00 database-1.0 2021-11-28 12:06:54 UTC::@:[12026]:LOCATION:  heap_vacuum_rel, vacuumlazy.c:690
2021-11-28T12:06:54+00:00 database-1.0 2021-11-28 12:06:54 UTC::@:[12026]:LOG:  00000: automatic analyze of table "mytest.public.pgbench_branches" system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.00 s
2021-11-28T12:06:54+00:00 database-1.0 2021-11-28 12:06:54 UTC::@:[12026]:LOCATION:  do_analyze_rel, analyze.c:714
2021-11-28T12:07:04+00:00 database-1.0 2021-11-28 12:07:04 UTC::@:[10203]:LOG:  00000: checkpoint starting: time
2021-11-28T12:07:04+00:00 database-1.0 2021-11-28 12:07:04 UTC::@:[10203]:LOCATION:  LogCheckpointStart, xlog.c:8569
2021-11-28T12:07:36+00:00 database-1.0 2021-11-28 12:07:36 UTC::@:[10203]:LOG:  00000: checkpoint complete: wrote 321 buffers (0.3%); 0 WAL file(s) added, 0 removed, 1 recycled; write=32.497 s, sync=0.003 s, total=32.511 s; sync files=20, longest=0.003 s, average=0.001 s; distance=66331 kB, estimate=891445 kB
2021-11-28T12:07:36+00:00 database-1.0 2021-11-28 12:07:36 UTC::@:[10203]:LOCATION:  LogCheckpointEnd, xlog.c:8637
2021-11-28T12:07:39+00:00 database-1.0 2021-11-28 12:07:39 UTC::@:[12873]:LOG:  00000: automatic analyze of table "mytest.public.pgbench_history" system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.00 s
2021-11-28T12:07:39+00:00 database-1.0 2021-11-28 12:07:39 UTC::@:[12873]:LOCATION:  do_analyze_rel, analyze.c:714
2021-11-28T12:07:54+00:00 database-1.0 2021-11-28 12:07:54 UTC::@:[13227]:LOG:  00000: automatic vacuum of table "mytest.public.pgbench_branches": index scans: 0
     pages: 0 removed, 1 remain, 0 skipped due to pins, 0 skipped frozen
     tuples: 71 removed, 100 remain, 0 are dead but not yet removable, oldest xmin: 805
     buffer usage: 46 hits, 0 misses, 4 dirtied
     avg read rate: 0.000 MB/s, avg write rate: 71.347 MB/s
     system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.00 s
     WAL usage: 6 records, 4 full page images, 1391 bytes
2021-11-28T12:07:54+00:00 database-1.0 2021-11-28 12:07:54 UTC::@:[13227]:LOCATION:  heap_vacuum_rel, vacuumlazy.c:690
2021-11-28T12:07:54+00:00 database-1.0 2021-11-28 12:07:54 UTC::@:[13227]:LOG:  00000: automatic analyze of table "mytest.public.pgbench_branches" system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.00 s
2021-11-28T12:07:54+00:00 database-1.0 2021-11-28 12:07:54 UTC::@:[13227]:LOCATION:  do_analyze_rel, analyze.c:714
2021-11-28T12:08:09+00:00 database-1.0 2021-11-28 12:08:09 UTC::@:[13454]:LOG:  00000: automatic analyze of table "mytest.public.pgbench_tellers" system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.00 s
2021-11-28T12:08:09+00:00 database-1.0 2021-11-28 12:08:09 UTC::@:[13454]:LOCATION:  do_analyze_rel, analyze.c:714
2021-11-28T12:08:39+00:00 database-1.0 2021-11-28 12:08:39 UTC::@:[13909]:LOG:  00000: automatic analyze of table "mytest.public.pgbench_history" system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.00 s


mytest=> begin transaction isolation level repeatable read;
mytest=*> select * from pgbench_branches;






2021-11-28T12:15:40+00:00 database-1.0 2021-11-28 12:15:40 UTC::@:[21444]:LOG:  00000: automatic vacuum of table "mytest.public.pgbench_tellers": index scans: 0
     pages: 0 removed, 8 remain, 0 skipped due to pins, 0 skipped frozen
     tuples: 0 removed, 1269 remain, 269 are dead but not yet removable, oldest xmin: 1092
     buffer usage: 41 hits, 0 misses, 0 dirtied
     avg read rate: 0.000 MB/s, avg write rate: 0.000 MB/s
     system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.00 s
     WAL usage: 0 records, 0 full page images, 0 bytes
2021-11-28T12:15:40+00:00 database-1.0 2021-11-28 12:15:40 UTC::@:[21444]:LOCATION:  heap_vacuum_rel, vacuumlazy.c:690
2021-11-28T12:15:40+00:00 database-1.0 2021-11-28 12:15:40 UTC::@:[21444]:LOG:  00000: automatic analyze of table "mytest.public.pgbench_tellers" system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.00 s
2021-11-28T12:15:40+00:00 database-1.0 2021-11-28 12:15:40 UTC::@:[21444]:LOCATION:  do_analyze_rel, analyze.c:714
2021-11-28T12:15:55+00:00 database-1.0 2021-11-28 12:15:55 UTC::@:[21707]:LOG:  00000: automatic vacuum of table "mytest.public.pgbench_branches": index scans: 0
     pages: 0 removed, 2 remain, 0 skipped due to pins, 0 skipped frozen
     tuples: 0 removed, 386 remain, 286 are dead but not yet removable, oldest xmin: 1092
     buffer usage: 47 hits, 0 misses, 0 dirtied
     avg read rate: 0.000 MB/s, avg write rate: 0.000 MB/s
     system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.00 s
     WAL usage: 0 records, 0 full page images, 0 bytes
2021-11-28T12:15:55+00:00 database-1.0 2021-11-28 12:15:55 UTC::@:[21707]:LOCATION:  heap_vacuum_rel, vacuumlazy.c:690
2021-11-28T12:15:55+00:00 database-1.0 2021-11-28 12:15:55 UTC::@:[21707]:LOG:  00000: automatic analyze of table "mytest.public.pgbench_branches" system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.00 s
2021-11-28T12:15:55+00:00 database-1.0 2021-11-28 12:15:55 UTC::@:[21707]:LOCATION:  do_analyze_rel, analyze.c:714
2021-11-28T12:15:55+00:00 database-1.0 2021-11-28 12:15:55 UTC::@:[21707]:LOG:  00000: automatic vacuum of table "mytest.public.pgbench_tellers": index scans: 0
     pages: 0 removed, 8 remain, 0 skipped due to pins, 0 skipped frozen
     tuples: 0 removed, 1286 remain, 286 are dead but not yet removable, oldest xmin: 1092
     buffer usage: 41 hits, 0 misses, 0 dirtied
     avg read rate: 0.000 MB/s, avg write rate: 0.000 MB/s
     system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.00 s
     WAL usage: 0 records, 0 full page images, 0 bytes
2021-11-28T12:15:55+00:00 database-1.0 2021-11-28 12:15:55 UTC::@:[21707]:LOCATION:  heap_vacuum_rel, vacuumlazy.c:690






2021-11-28T12:18:10+00:00 database-1.0 2021-11-28 12:18:10 UTC::@:[24055]:LOG:  00000: automatic vacuum of table "mytest.public.pgbench_branches": index scans: 0
     pages: 0 removed, 4 remain, 0 skipped due to pins, 0 skipped frozen
     tuples: 0 removed, 545 remain, 445 are dead but not yet removable, oldest xmin: 1092
     buffer usage: 51 hits, 0 misses, 0 dirtied
     avg read rate: 0.000 MB/s, avg write rate: 0.000 MB/s
     system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.00 s
     WAL usage: 0 records, 0 full page images, 0 bytes
2021-11-28T12:18:10+00:00 database-1.0 2021-11-28 12:18:10 UTC::@:[24055]:LOCATION:  heap_vacuum_rel, vacuumlazy.c:690
2021-11-28T12:18:10+00:00 database-1.0 2021-11-28 12:18:10 UTC::@:[24055]:LOG:  00000: automatic vacuum of table "mytest.public.pgbench_tellers": index scans: 0
     pages: 0 removed, 8 remain, 0 skipped due to pins, 0 skipped frozen
     tuples: 0 removed, 1445 remain, 445 are dead but not yet removable, oldest xmin: 1092
     buffer usage: 41 hits, 0 misses, 0 dirtied
     avg read rate: 0.000 MB/s, avg write rate: 0.000 MB/s
     system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.00 s
     WAL usage: 0 records, 0 full page images, 0 bytes

*/

WITH max_age AS (
    SELECT 2000000000 as max_old_xid
        , setting AS autovacuum_freeze_max_age
        FROM pg_catalog.pg_settings
        WHERE name = 'autovacuum_freeze_max_age' )
, per_database_stats AS (
    SELECT datname
        , m.max_old_xid::int
        , m.autovacuum_freeze_max_age::int
        , age(d.datfrozenxid) AS oldest_current_xid
    FROM pg_catalog.pg_database d
    JOIN max_age m ON (true)
    WHERE d.datallowconn )
SELECT max(oldest_current_xid) AS oldest_current_xid
    , max(ROUND(100*(oldest_current_xid/max_old_xid::float))) AS percent_towards_wraparound
    , max(ROUND(100*(oldest_current_xid/autovacuum_freeze_max_age::float))) AS percent_towards_emergency_autovac
FROM per_database_stats;




/*

mytest=> WITH max_age AS (
    SELECT 2000000000 as max_old_xid
        , setting AS autovacuum_freeze_max_age
        FROM pg_catalog.pg_settings
        WHERE name = 'autovacuum_freeze_max_age' )
, per_database_stats AS (
    SELECT datname
        , m.max_old_xid::int
        , m.autovacuum_freeze_max_age::int
        , age(d.datfrozenxid) AS oldest_current_xid
    FROM pg_catalog.pg_database d
    JOIN max_age m ON (true)
    WHERE d.datallowconn )
SELECT max(oldest_current_xid) AS oldest_current_xid
    , max(ROUND(100*(oldest_current_xid/max_old_xid::float))) AS percent_towards_wraparound
    , max(ROUND(100*(oldest_current_xid/autovacuum_freeze_max_age::float))) AS percent_towards_emergency_autovac
FROM per_database_stats
;
 oldest_current_xid | percent_towards_wraparound | percent_towards_emergency_autovac 
--------------------+----------------------------+-----------------------------------
               1418 |                          0 |                                 0
(1 row)

*/

SELECT datname
, age(datfrozenxid)
, current_setting('autovacuum_freeze_max_age') 
FROM pg_database 
ORDER BY 2 DESC;

/*


mytest=> SELECT datname
mytest->     , age(datfrozenxid)
mytest->     , current_setting('autovacuum_freeze_max_age') 
mytest-> FROM pg_database 
mytest-> ORDER BY 2 DESC;
  datname  | age  | current_setting 
-----------+------+-----------------
 template0 | 1442 | 200000000
 rdsadmin  | 1442 | 200000000
 template1 | 1442 | 200000000
 postgres  | 1442 | 200000000
 mytest    | 1442 | 200000000

*/

SELECT c.oid::regclass
, age(c.relfrozenxid)
, pg_size_pretty(pg_total_relation_size(c.oid)) 
FROM pg_class c
JOIN pg_namespace n on c.relnamespace = n.oid
WHERE relkind IN ('r', 't', 'm') 
AND n.nspname NOT IN ('pg_toast')
ORDER BY 2 DESC LIMIT 100;

/*



mytest=> SELECT c.oid::regclass
mytest->     , age(c.relfrozenxid)
mytest->     , pg_size_pretty(pg_total_relation_size(c.oid)) 
mytest-> FROM pg_class c
mytest-> JOIN pg_namespace n on c.relnamespace = n.oid
mytest-> WHERE relkind IN ('r', 't', 'm') 
mytest-> AND n.nspname NOT IN ('pg_toast')
mytest-> ORDER BY 2 DESC LIMIT 100;
                    oid                     | age  | pg_size_pretty 
--------------------------------------------+------+----------------
 information_schema.sql_features            | 1467 | 104 kB
 pg_subscription_rel                        | 1467 | 8192 bytes
 information_schema.sql_implementation_info | 1467 | 48 kB
 information_schema.sql_parts               | 1467 | 48 kB
 information_schema.sql_sizing              | 1467 | 48 kB
 pg_statistic                               | 1467 | 368 kB
 pg_type                                    | 1467 | 192 kB
 pg_foreign_table                           | 1467 | 16 kB
 pg_authid                                  | 1467 | 80 kB
 pg_statistic_ext_data                      | 1467 | 16 kB
 pg_largeobject                             | 1467 | 8192 bytes
 pg_user_mapping                            | 1467 | 24 kB
 pg_subscription                            | 1467 | 24 kB
 pg_attribute                               | 1467 | 656 kB
 pg_proc                                    | 1467 | 1024 kB
 pg_class                                   | 1467 | 256 kB
 pg_attrdef                                 | 1467 | 24 kB
 pg_constraint                              | 1467 | 128 kB
 pg_inherits                                | 1467 | 16 kB
 pg_index                                   | 1467 | 96 kB
 pg_operator                                | 1467 | 232 kB
 pg_opfamily                                | 1467 | 80 kB
 pg_opclass                                 | 1467 | 80 kB
 pg_am                                      | 1467 | 72 kB
 pg_amop                                    | 1467 | 192 kB
 pg_amproc                                  | 1467 | 128 kB
 pg_language                                | 1467 | 80 kB
 pg_largeobject_metadata                    | 1467 | 8192 bytes
 pg_aggregate                               | 1467 | 72 kB
 pg_statistic_ext                           | 1467 | 32 kB
 pg_rewrite                                 | 1467 | 688 kB
 pg_trigger                                 | 1467 | 32 kB
 pg_event_trigger                           | 1467 | 24 kB
 pg_description                             | 1467 | 560 kB
 pg_cast                                    | 1467 | 80 kB
 pg_enum                                    | 1467 | 24 kB
 pg_namespace                               | 1467 | 80 kB
 pg_conversion                              | 1467 | 96 kB
 pg_depend                                  | 1467 | 1104 kB
 pg_database                                | 1467 | 80 kB
 pg_db_role_setting                         | 1467 | 32 kB
 pg_tablespace                              | 1467 | 80 kB
 pg_auth_members                            | 1467 | 72 kB
 pg_shdepend                                | 1467 | 72 kB
 pg_shdescription                           | 1467 | 64 kB
 pg_ts_config                               | 1467 | 72 kB
 pg_ts_config_map                           | 1467 | 88 kB
 pg_ts_dict                                 | 1467 | 80 kB
 pg_ts_parser                               | 1467 | 72 kB
 pg_ts_template                             | 1467 | 72 kB
 pg_extension                               | 1467 | 80 kB
 pg_foreign_data_wrapper                    | 1467 | 24 kB
 pg_foreign_server                          | 1467 | 24 kB
 pg_policy                                  | 1467 | 24 kB
 pg_replication_origin                      | 1467 | 24 kB
 pg_default_acl                             | 1467 | 24 kB
 pg_init_privs                              | 1467 | 72 kB
 pg_seclabel                                | 1467 | 16 kB
 pg_shseclabel                              | 1467 | 16 kB
 pg_collation                               | 1467 | 616 kB
 pg_partitioned_table                       | 1467 | 16 kB
 pg_range                                   | 1467 | 56 kB
 pg_transform                               | 1467 | 16 kB
 pg_sequence                                | 1467 | 8192 bytes
 pg_publication                             | 1467 | 16 kB
 pg_publication_rel                         | 1467 | 16 kB
 pgbench_branches                           | 1363 | 96 kB
 pgbench_tellers                            | 1363 | 184 kB
 pgbench_accounts                           | 1363 | 1496 MB
 pgbench_history                            | 1352 | 136 kB
(70 rows)


2021-11-28T12:26:44+00:00 database-1.0 2021-11-28 12:26:44 UTC::@:[528]:LOG:  00000: automatic vacuum of table "mytest.pg_catalog.pg_statistic": index scans: 0
     pages: 0 removed, 31 remain, 0 skipped due to pins, 0 skipped frozen
     tuples: 0 removed, 564 remain, 145 are dead but not yet removable, oldest xmin: 1092
     buffer usage: 70 hits, 0 misses, 0 dirtied
     avg read rate: 0.000 MB/s, avg write rate: 0.000 MB/s
     system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.00 s
     WAL usage: 0 records, 0 full page images, 0 bytes
2021-11-28T12:26:44+00:00 database-1.0 2021-11-28 12:26:44 UTC::@:[528]:LOCATION:  heap_vacuum_rel, vacuumlazy.c:690

mytest=*> commit;

2021-11-28T12:28:30+00:00 database-1.0 2021-11-28 12:28:30 UTC::@:[2439]:LOCATION:  heap_vacuum_rel, vacuumlazy.c:690
2021-11-28T12:28:45+00:00 database-1.0 2021-11-28 12:28:45 UTC::@:[2685]:LOG:  00000: automatic vacuum of table "mytest.public.pgbench_branches": index scans: 1
     pages: 0 removed, 6 remain, 0 skipped due to pins, 0 skipped frozen
     tuples: 160 removed, 100 remain, 0 are dead but not yet removable, oldest xmin: 2325
     buffer usage: 60 hits, 0 misses, 1 dirtied
     avg read rate: 0.000 MB/s, avg write rate: 13.493 MB/s
     system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.00 s
     WAL usage: 15 records, 1 full page images, 2742 bytes
2021-11-28T12:28:45+00:00 database-1.0 2021-11-28 12:28:45 UTC::@:[2685]:LOCATION:  heap_vacuum_rel, vacuumlazy.c:690
2021-11-28T12:28:45+00:00 database-1.0 2021-11-28 12:28:45 UTC::@:[2685]:LOG:  00000: automatic vacuum of table "mytest.public.pgbench_tellers": index scans: 1
     pages: 0 removed, 12 remain, 0 skipped due to pins, 0 skipped frozen
     tuples: 251 removed, 1000 remain, 0 are dead but not yet removable, oldest xmin: 2325
     buffer usage: 71 hits, 0 misses, 1 dirtied
     avg read rate: 0.000 MB/s, avg write rate: 6.615 MB/s
     system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.00 s
     WAL usage: 36 records, 1 full page images, 7619 bytes
2021-11-28T12:28:45+00:00 database-1.0 2021-11-28 12:28:45 UTC::@:[2685]:LOCATION:  heap_vacuum_rel, vacuumlazy.c:690
2021-11-28T12:28:45+00:00 database-1.0 2021-11-28 12:28:45 UTC::@:[2685]:LOG:  00000: automatic vacuum of table "mytest.pg_catalog.pg_statistic": index scans: 1
     pages: 0 removed, 33 remain, 0 skipped due to pins, 0 skipped frozen
     tuples: 161 removed, 419 remain, 0 are dead but not yet removable, oldest xmin: 2325
     buffer usage: 98 hits, 0 misses, 14 dirtied
     avg read rate: 0.000 MB/s, avg write rate: 23.891 MB/s
     system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.00 s
     WAL usage: 51 records, 14 full page images, 14680 bytes
2021-11-28T12:28:45+00:00 database-1.0 2021-11-28 12:28:45 UTC::@:[2685]:LOCATION:  heap_vacuum_rel, vacuumlazy.c:690




mytest=> begin transaction isolation level repeatable read;
BEGIN
mytest=*> select txid_current();
 txid_current 
--------------
         2854
(1 row)

mytest=*> select * from t1;
 id 
----
  1
(1 row)



ge: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.00 s
2021-11-28T12:36:00+00:00 database-1.0 2021-11-28 12:36:00 UTC::@:[10720]:LOCATION:  do_analyze_rel, analyze.c:714
2021-11-28T12:36:00+00:00 database-1.0 2021-11-28 12:36:00 UTC::@:[10720]:LOG:  00000: automatic vacuum of table "mytest.public.pgbench_tellers": index scans: 0
     pages: 0 removed, 12 remain, 0 skipped due to pins, 0 skipped frozen
     tuples: 147 removed, 1004 remain, 4 are dead but not yet removable, oldest xmin: 2852
     buffer usage: 50 hits, 0 misses, 0 dirtied
     avg read rate: 0.000 MB/s, avg write rate: 0.000 MB/s
     system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.00 s
     WAL usage: 20 records, 0 full page images, 1984 bytes
2021-11-28T12:36:00+00:00 database-1.0 2021-11-28 12:36:00 UTC::@:[10720]:LOCATION:  heap_vacuum_rel, vacuumlazy.c:690
2021-11-28T12:36:15+00:00 database-1.0 2021-11-28 12:36:15 UTC::@:[10947]:LOG:  00000: automatic vacuum of table "mytest.public.pgbench_branches": index scans: 0
     pages: 0 removed, 6 remain, 0 skipped due to pins, 0 skipped frozen
     tuples: 49 removed, 122 remain, 22 are dead but not yet removable, oldest xmin: 2852
     buffer usage: 55 hits, 0 misses, 0 dirtied
     avg read rate: 0.000 MB/s, avg write rate: 0.000 MB/s
     system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.00 s
     WAL usage: 2 records, 0 full page images, 334 bytes
2021-11-28T12:36:15+00:00 database-1.0 2021-11-28 12:36:15 UTC::@:[10947]:LOCATION:  heap_vacuum_rel, vacuumlazy.c:690
2021-11-28T12:36:45+00:00 database-1.0 2021-11-28 12:36:45 UTC::@:[11454]:LOG:  00000: automatic analyze of table "mytest.public.pgbench_tellers" system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.00 s
2021-11-28T12:36:45+00:00 database-1.0 2021-11-28 12:36:45 UTC::@:[11454]:LOCATION:  do_analyze_rel, analyze.c:714


====================================================

mytest=> begin transaction;
BEGIN
mytest=*> insert into pgbench_branches values(100000,0,0);
INSERT 0 1
mytest=*> select txid_current();
 txid_current 
--------------
        81848
(1 row)



2021-11-28T12:47:16+00:00 database-1.0 2021-11-28 12:47:16 UTC::@:[23498]:LOCATION:  heap_vacuum_rel, vacuumlazy.c:690
2021-11-28T12:47:16+00:00 database-1.0 2021-11-28 12:47:16 UTC::@:[23498]:LOG:  00000: automatic analyze of table "mytest.public.pgbench_history" system usage: CPU: user: 0.06 s, system: 0.01 s, elapsed: 0.08 s
2021-11-28T12:47:16+00:00 database-1.0 2021-11-28 12:47:16 UTC::@:[23498]:LOCATION:  do_analyze_rel, analyze.c:714
2021-11-28T12:47:16+00:00 database-1.0 2021-11-28 12:47:16 UTC::@:[23498]:LOG:  00000: automatic vacuum of table "mytest.pg_catalog.pg_statistic": index scans: 0
     pages: 0 removed, 33 remain, 0 skipped due to pins, 0 skipped frozen
     tuples: 0 removed, 576 remain, 157 are dead but not yet removable, oldest xmin: 81848
     buffer usage: 73 hits, 0 misses, 2 dirtied
     avg read rate: 0.000 MB/s, avg write rate: 47.637 MB/s
     system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.00 s
     WAL usage: 3 records, 2 full page images, 625 bytes
2021-11-28T12:47:16+00:00 database-1.0 2021-11-28 12:47:16 UTC::@:[23498]:LOCATION:  heap_vacuum_rel, vacuumlazy.c:690
2021-11-28T12:47:31+00:00 database-1.0 2021-11-28 12:47:31 UTC::@:[23727]:LOG:  00000: automatic vacuum of table "mytest.public.pgbench_branches": index scans: 0
     pages: 0 removed, 396 remain, 0 skipped due to pins, 0 skipped frozen
     tuples: 0 removed, 89382 remain, 89282 are dead but not yet removable, oldest xmin: 81848
     buffer usage: 831 hits, 0 misses, 0 dirtied
     avg read rate: 0.000 MB/s, avg write rate: 0.000 MB/s
     system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.02 s
     WAL usage: 1 records, 0 full page images, 229 bytes
2021-11-28T12:47:31+00:00 database-1.0 2021-11-28 12:47:31 UTC::@:[23727]:LOCATION:  heap_vacuum_rel, vacuumlazy.c:690
2021-11-28T12:47:31+00:00 database-1.0 2021-11-28 12:47:31 UTC::@:[23727]:LOG:  00000: automatic analyze of table "mytest.public.pgbench_branches" system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.00 s
2021-11-28T12:47:31+00:00 database-1.0 2021-11-28 12:47:31 UTC::@:[23727]:LOCATION:  do_analyze_rel, analyze.c:714
2021-11-28T12:47:31+00:00 database-1.0 2021-11-28 12:47:31 UTC::@:[23727]:LOG:  00000: automatic vacuum of table "mytest.public.pgbench_tellers": index scans: 0
     pages: 0 removed, 490 remain, 0 skipped due to pins, 0 skipped frozen
     tuples: 0 removed, 90295 remain, 89295 are dead but not yet removable, oldest xmin: 81848
     buffer usage: 1006 hits, 0 misses, 0 dirtied
     avg read rate: 0.000 MB/s, avg write rate: 0.000 MB/s
     system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.01 s
     WAL usage: 1 records, 0 full page images, 229 bytes
2021-11-28T12:47:31+00:00 database-1.0 2021-11-28 12:47:31 UTC::@:[23727]:LOCATION:  heap_vacuum_rel, vacuumlazy.c:690
2021-11-28T12:47:31+00:00 database-1.0 2021-11-28 12:47:31 UTC::@:[23727]:LOG:  00000: automatic analyze of table "mytest.public.pgbench_tellers" system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.00 s
2021-11-28T12:47:31+00:00 database-1.0 2021-11-28 12:47:31 UTC::@:[23727]:LOCATION:  do_analyze_rel, analyze.c:714
2021-11-28T12:47:31+00:00 database-1.0 2021-11-28 12:47:31 UTC::@:[23727]:LOG:  00000: automatic vacuum of table "mytest.pg_catalog.pg_statistic": index scans: 0
     pages: 0 removed, 33 remain, 0 skipped due to pins, 0 skipped frozen
     tuples: 0 removed, 583 remain, 164 are dead but not yet removable, oldest xmin: 81848
     buffer usage: 72 hits, 0 misses, 0 dirtied
     avg read rate: 0.000 MB/s, avg write rate: 0.000 MB/s
     system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.00 s
     WAL usage: 0 records, 0 full page images, 0 bytes
2021-11-28T12:47:31+00:00 database-1.0 2021-11-28 12:47:31 UTC::@:[23727]:LOCATION:  heap_vacuum_rel, vacuumlazy.c:690

     relname      |          last_vacuum          |        last_autovacuum        | n_dead_tup 
------------------+-------------------------------+-------------------------------+------------
 pgbench_branches | 2021-11-28 12:41:22.481517+00 | 2021-11-28 12:48:46.387668+00 |     121440
 t1               |                               |                               |          0
 pgbench_accounts | 2021-11-28 11:52:26.421433+00 |                               |     192487
 pgbench_history  | 2021-11-28 11:52:26.874922+00 | 2021-11-28 12:47:16.373243+00 |          0
 pgbench_tellers  | 2021-11-28 12:41:22.482544+00 | 2021-11-28 12:48:46.434575+00 |     121459
(5 rows)

                              Sun Nov 28 20:48:53 2021 (every 1s)

     relname      |          last_vacuum          |        last_autovacuum        | n_dead_tup 
------------------+-------------------------------+-------------------------------+------------
 pgbench_branches | 2021-11-28 12:41:22.481517+00 | 2021-11-28 12:48:46.387668+00 |     122088
 t1               |                               |                               |          0
 pgbench_accounts | 2021-11-28 11:52:26.421433+00 |                               |     193112
 pgbench_history  | 2021-11-28 11:52:26.874922+00 | 2021-11-28 12:47:16.373243+00 |          0
 pgbench_tellers  | 2021-11-28 12:41:22.482544+00 | 2021-11-28 12:48:46.434575+00 |     122107
(5 rows)

-- different database has its own autovaccum 
mytest2=> create table t2  (id  int);
CREATE TABLE
mytest2=> insert into t2 select * from generate_series(1,1000000);
INSERT 0 1000000
mytest2=> update t2 set id=id+1;
UPDATE 1000000
mytest2=> update t2 set id=id+1;
UPDATE 1000000
mytest2=> delete from t2 where mod(id,2)=0;
DELETE 500000
mytest2=> SELECT relname, last_vacuum, last_autovacuum,n_dead_tup FROM pg_stat_user_tables;
 relname | last_vacuum |        last_autovacuum        | n_dead_tup 
---------+-------------+-------------------------------+------------
 t2      |             | 2021-11-28 12:53:27.911481+00 |          0
(1 row)

mytest2=> 


2021-11-28T12:53:18+00:00 database-1.0 2021-11-28 12:53:18 UTC::@:[31447]:LOCATION:  do_analyze_rel, analyze.c:714
2021-11-28T12:53:18+00:00 database-1.0 2021-11-28 12:53:18 UTC::@:[31447]:LOG:  00000: automatic vacuum of table "mytest.pg_catalog.pg_statistic": index scans: 0
     pages: 0 removed, 47 remain, 0 skipped due to pins, 0 skipped frozen
     tuples: 0 removed, 798 remain, 379 are dead but not yet removable, oldest xmin: 81848
     buffer usage: 100 hits, 0 misses, 0 dirtied
     avg read rate: 0.000 MB/s, avg write rate: 0.000 MB/s
     system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.00 s
     WAL usage: 0 records, 0 full page images, 0 bytes
2021-11-28T12:53:18+00:00 database-1.0 2021-11-28 12:53:18 UTC::@:[31447]:LOCATION:  heap_vacuum_rel, vacuumlazy.c:690
2021-11-28T12:53:27+00:00 database-1.0 2021-11-28 12:53:27 UTC::@:[31574]:LOG:  00000: automatic vacuum of table "mytest2.public.t2": index scans: 0
     pages: 0 removed, 8850 remain, 0 skipped due to pins, 4424 skipped frozen
     tuples: 500000 removed, 999887 remain, 0 are dead but not yet removable, oldest xmin: 299104
     buffer usage: 8880 hits, 0 misses, 0 dirtied
     avg read rate: 0.000 MB/s, avg write rate: 0.000 MB/s
     system usage: CPU: user: 0.09 s, system: 0.02 s, elapsed: 0.20 s
     WAL usage: 13279 records, 0 full page images, 2739480 bytes
2021-11-28T12:53:27+00:00 database-1.0 2021-11-28 12:53:27 UTC::@:[31574]:LOCATION:  heap_vacuum_rel, vacuumlazy.c:690
2021-11-28T12:53:28+00:00 database-1.0 2021-11-28 12:53:28 UTC::@:[31574]:LOG:  00000: automatic analyze of table "mytest2.public.t2" system usage: CPU: user: 0.05 s, system: 0.00 s, elapsed: 0.16 s
2021-11-28T12:53:28+00:00 database-1.0 2021-11-28 12:53:28 UTC::@:[31574]:LOCATION:  do_analyze_rel, analyze.c:714
2021-11-28T12:53:33+00:00 database-1.0 2021-11-28 12:53:33 UTC::@:[31670]:LOG:  00000: automatic vacuum of table "mytest.public.pgbench_branches": index scans: 0
     pages: 0 removed, 971 remain, 0 skipped due to pins, 0 skipped frozen
     tuples: 0 removed, 219327 remain, 219227 are dead but not yet removable, oldest xmin: 81848
     buffer usage: 1986 hits, 0 misses, 0 dirtied
     avg read rate: 0.000 MB/s, avg write rate: 0.000 MB/s
     system usage: CPU: user: 0.01 s, system: 0.00 s, elapsed: 0.04 s
     WAL usage: 1 records, 0 full page images, 229 bytes

---> commit;



2021-11-28T12:55:34+00:00 database-1.0 2021-11-28 12:55:34 UTC::@:[1583]:LOCATION:  heap_vacuum_rel, vacuumlazy.c:690
2021-11-28T12:55:37+00:00 database-1.0 2021-11-28 12:55:37 UTC:115.66.64.230(55827):postgres@mytest2:[27532]:WARNING:  25P01: there is no transaction in progress
2021-11-28T12:55:37+00:00 database-1.0 2021-11-28 12:55:37 UTC:115.66.64.230(55827):postgres@mytest2:[27532]:LOCATION:  EndTransactionBlock, xact.c:3846
2021-11-28T12:55:42+00:00 database-1.0 2021-11-28 12:55:42 UTC:115.66.64.230(54609):postgres@mytest:[27848]:ERROR:  42601: syntax error at or near "ommit" at character 1
2021-11-28T12:55:42+00:00 database-1.0 2021-11-28 12:55:42 UTC:115.66.64.230(54609):postgres@mytest:[27848]:LOCATION:  scanner_yyerror, scan.l:1181
2021-11-28T12:55:42+00:00 database-1.0 2021-11-28 12:55:42 UTC:115.66.64.230(54609):postgres@mytest:[27848]:STATEMENT:  ommit;
2021-11-28T12:55:48+00:00 database-1.0 2021-11-28 12:55:48 UTC::@:[2061]:LOG:  00000: automatic vacuum of table "mytest.public.pgbench_branches": index scans: 1
     pages: 0 removed, 1162 remain, 0 skipped due to pins, 0 skipped frozen
     tuples: 244 removed, 109 remain, 9 are dead but not yet removable, oldest xmin: 346416
     buffer usage: 3628 hits, 0 misses, 1 dirtied
     avg read rate: 0.000 MB/s, avg write rate: 0.111 MB/s
     system usage: CPU: user: 0.01 s, system: 0.00 s, elapsed: 0.07 s
     WAL usage: 2424 records, 1 full page images, 294126 bytes
2021-11-28T12:55:48+00:00 database-1.0 2021-11-28 12:55:48 UTC::@:[2061]:LOCATION:  heap_vacuum_rel, vacuumlazy.c:690
2021-11-28T12:55:48+00:00 database-1.0 2021-11-28 12:55:48 UTC::@:[2061]:LOG:  00000: automatic analyze of table "mytest.public.pgbench_branches" system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.01 s
2021-11-28T12:55:48+00:00 database-1.0 2021-11-28 12:55:48 UTC::@:[2061]:LOCATION:  do_analyze_rel, analyze.c:714
2021-11-28T12:55:49+00:00 database-1.0 2021-11-28 12:55:49 UTC::@:[2061]:LOG:  00000: automatic vacuum of table "mytest.public.pgbench_tellers": index scans: 1
     pages: 0 removed, 1424 remain, 0 skipped due to pins, 0 skipped frozen
     tuples: 884 removed, 1009 remain, 9 are dead but not yet removable, oldest xmin: 346453
     buffer usage: 4547 hits, 0 misses, 1 dirtied
     avg read rate: 0.000 MB/s, avg write rate: 0.064 MB/s
     system usage: CPU: user: 0.06 s, system: 0.00 s, elapsed: 0.12 s
     WAL usage: 3117 records, 1 full page images, 680117 bytes
2021-11-28T12:55:49+00:00 database-1.0 2021-11-28 12:55:49 UTC::@:[2061]:LOCATION:  heap_vacuum_rel, vacuumlazy.c:690
2021-11-28T12:55:49+00:00 database-1.0 2021-11-28 12:55:49 UTC::@:[2061]:LOG:  00000: automatic analyze of table "mytest.public.pgbench_tellers" system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.02 s
2021-11-28T12:55:49+00:00 database-1.0 2021-11-28 12:55:49 UTC::@:[2061]:LOCATION:  do_analyze_rel, analyze.c:714
2021-11-28T12:55:49+00:00 database-1.0 2021-11-28 12:55:49 UTC::@:[2061]:LOG:  00000: automatic vacuum of table "mytest.pg_catalog.pg_statistic": index scans: 1
     pages: 0 removed, 53 remain, 0 skipped due to pins, 0 skipped frozen
     tuples: 33 removed, 419 remain, 0 are dead but not yet removable, oldest xmin: 346494
     buffer usage: 156 hits, 1 misses, 2 dirtied
     avg read rate: 6.166 MB/s, avg write rate: 12.332 MB/s
     system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.00 s
     WAL usage: 82 records, 3 full page images, 6083 bytes
2021-11-28T12:55:49+00:00 database-1.0 2021-11-28 12:55:49 UTC::@:[2061]:LOCATION:  heap_vacuum_rel, vacuumlazy.c:690
2021-11-28T12:56:03+00:00 database-1.0 2021-11-28 12:56:03 UTC::@:[2288]:LOG:  00000: automatic vacuum of table "mytest.public.pgbench_branches": index scans: 0
     pages: 0 removed, 1162 remain, 0 skipped due to pins, 1158 skipped frozen
     tuples: 311 removed, 200 remain, 0 are dead but not yet removable, oldest xmin: 353071
     buffer usage: 47 hits, 0 misses, 0 dirtied
     avg read rate: 0.000 MB/s, avg write rate: 0.000 MB/s
     system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.00 s
     WAL usage: 8 records, 0 full page images, 1576 bytes
2021-11-28T12:56:03+00:00 database-1.0 2021-11-28 12:56:03 UTC::@:[2288]:LOCATION:  heap_vacuum_rel, vacuumlazy.c:690
2021-11-28T12:56:03+00:00 database-1.0 2021-11-28 12:56:03 UTC::@:[2288]:LOG:  00000: automatic analyze of table "mytest.public.pgbench_branches" system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.01 s
2021-11-28T12:56:03+00:00 database-1.0 2021-11-28 12:56:03 UTC::@:[2288]:LOCATION:  do_analyze_rel, analyze.c:714
2021-11-28T12:56:03+00:00 database-1.0 2021-11-28 12:56:03 UTC::@:[2288]:LOG:  00000: automatic vacuum of table "mytest.public.pgbench_tellers": index scans: 0
     pages: 0 removed, 1424 remain, 0 skipped due to pins, 1362 skipped frozen
     tuples: 1425 removed, 1956 remain, 0 are dead but not yet removable, oldest xmin: 353085
     buffer usage: 150 hits, 0 misses, 0 dirtied
     avg read rate: 0.000 MB/s, avg write rate: 0.000 MB/s
     system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.00 s
     WAL usage: 64 records, 0 full page images, 8492 bytes
2021-11-28T12:56:03+00:00 database-1.0 2021-11-28 12:56:03 UTC::@:[2288]:LOCATION:  heap_vacuum_rel, vacuumlazy.c:690
2021-11-28T12:56:03+00:00 database-1.0 2021-11-28 12:56:03 UTC::@:[2288]:LOG:  00000: automatic analyze of table "mytest.public.pgbench_tellers" system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.02 s
2021-11-28T12:56:03+00:00 database-1.0 2021-11-28 12:56:03 UTC::@:[2288]:LOCATION:  do_analyze_rel, analyze.c:714
2021-11-28T12:56:18+00:00 database-1.0 2021-11-28 12:56:18 UTC::@:[2535]:LOG:  00000: automatic vacuum of table "mytest.public.pgbench_branches": index scans: 0
     pages: 0 removed, 1162 remain, 0 skipped due to pins, 1158 skipped frozen
     tuples: 255 removed, 204 remain, 4 are dead but not yet removable, oldest xmin: 360179
     buffer usage: 52 hits, 0 misses, 0 dirtied
     avg read rate: 0.000 MB/s, avg write rate: 0.000 MB/s
     system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.00 s
     WAL usage: 6 records, 0 full page images, 1302 bytes
2021-11-28T12:56:18+00:00 database-1.0 2021-11-28 12:56:18 UTC::@:[2535]:LOCATION:  heap_vacuum_rel, vacuumlazy.c:690
2021-11-28T12:56:18+00:00 database-1.0 2021-11-28 12:56:18 UTC::@:[2535]:LOG:  00000: automatic analyze of table "mytest.public.pgbench_branches" system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.01 s
2021-11-28T12:56:18+00:00 database-1.0 2021-11-28 12:56:18 UTC::@:[2535]:LOCATION:  do_analyze_rel, analyze.c:714
2021-11-28T12:56:18+00:00 database-1.0 2021-11-28 12:56:18 UTC::@:[2535]:LOG:  00000: automatic vacuum of table "mytest.public.pgbench_tellers": index scans: 0
     pages: 0 removed, 1424 remain, 0 skipped due to pins, 1362 skipped frozen
     tuples: 1402 removed, 1956 remain, 0 are dead but not yet removable, oldest xmin: 360201
     buffer usage: 150 hits, 0 misses, 0 dirtied
     avg read rate: 0.000 MB/s, avg write rate: 0.000 MB/s
     system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.00 s
     WAL usage: 65 records, 0 full page images, 8261 bytes
2021-11-28T12:56:18+00:00 database-1.0 2021-11-28 12:56:18 UTC::@:[2535]:LOCATION:  heap_vacuum_rel, vacuumlazy.c:690
2021-11-28T12:56:18+00:00 database-1.0 2021-11-28 12:56:18 UTC::@:[2535]:LOG:  00000: automatic analyze of table "mytest.public.pgbench_tellers" system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.02 s
2021-11-28T12:56:18+00:00 database-1.0 2021-11-28 12:56:18 UTC::@:[2535]:LOCATION:  do_analyze_rel, analyze.c:714
2021-11-28T12:56:19+00:00 database-1.0 2021-11-28 12:56:19 UTC::@:[2535]:LOG:  00000: automatic analyze of table "mytest.public.pgbench_history" system usage: CPU: user: 0.09 s, system: 0.00 s, elapsed: 0.12 s
2021-11-28T12:56:19+00:00 database-1.0 2021-11-28 12:56:19 UTC::@:[2535]:LOCATION:  do_analyze_rel, analyze.c:714

*/


