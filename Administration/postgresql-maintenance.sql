create extension pgstattuple;

select * from pgstattuple_approx('pgbench_accounts');

-- For a precise calculation of bloat, call the pgstattuple ('pgbench_accounts'). 
-- This function examines every row in the entire table. 
-- This is resource intensive and will temporarily affect performance.
select * from pgstattuple('pgbench_accounts');


/*
postgres=> \x auto
Expanded display is used automatically.
postgres=> \timing
Timing is on.


postgres=> select * from pgstattuple_approx('pgbench_accounts');
-[ RECORD 1 ]--------+----------------------
table_len            | 134299648
scanned_percent      | 0
approx_tuple_count   | 999966
approx_tuple_len     | 132706695
approx_tuple_percent | 98.8138814779321
dead_tuple_count     | 20
dead_tuple_len       | 2420
dead_tuple_percent   | 0.0018019406871416371
approx_free_space    | 1576008
approx_free_percent  | 1.173501214239966

postgres=> select * from pgstattuple('pgbench_accounts');
-[ RECORD 1 ]------+----------
table_len          | 134299648
tuple_count        | 1000000
tuple_len          | 121000000
tuple_percent      | 90.1
dead_tuple_count   | 20
dead_tuple_len     | 2420
dead_tuple_percent | 0
free_space         | 1837976
free_percent       | 1.37

Time: 340.308 ms

*/


-- If xid exhaustion is ever reached, the database will be forced to shut down
-- age is multixacts, watch out wrap around (200 million transactions)

select relname, age(relfrozenxid) as xid_age
  from pg_class c, pg_namespace n
 where c.relnamespace = n.oid
   and n.nspname = 'public'
   and relkind = 'r';
/*

mytest=> select relname, age(relfrozenxid) as xid_age
mytest->   from pg_class c, pg_namespace n
mytest->  where c.relnamespace = n.oid
mytest->    and n.nspname = 'public'
mytest->    and relkind = 'r';
     relname      | xid_age 
------------------+---------
 pgbench_accounts |      18
 pgbench_branches |      18
 pgbench_tellers  |      18
 pgbench_history  |      11
(4 rows)

*/

-- To observe xid wrap around and vacuum effects, set the following parameters
-- autovacuum_freeze_max_age = 200000000 
-- autovacuum_multixact_freeze_max_age = 400000000


-- The VACUUM command marks dead space left in tables and indexes as available for reuse. 
-- Note that running the VACUUM does not reclaim disk space. 
-- Disk space can be reclaimed, however, with some offline options. 
-- Two of these options, the VACUUM FULL command and pg_repack extension, 


-- Basic command to vacuum a table
vacuum pgbench_accounts;

-- Vacuum + statistical analysis
vacuum analyze pgbench_accounts;

-- Vacuum + statistical analysis + freeze and rest xmin
vacuum freeze analyze pgbench_accounts;

/*

mytest=> vacuum freeze verbose analyze pgbench_accounts;
INFO:  aggressively vacuuming "public.pgbench_accounts"
INFO:  "pgbench_accounts": found 0 removable, 37 nonremovable row versions in 1 out of 16394 pages
DETAIL:  0 dead row versions cannot be removed yet, oldest xmin: 625
There were 0 unused item identifiers.
Skipped 0 pages due to buffer pins, 16393 frozen pages.
0 pages are entirely empty.
CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.00 s.
INFO:  analyzing "public.pgbench_accounts"
INFO:  "pgbench_accounts": scanned 16394 of 16394 pages, containing 1000000 live rows and 0 dead rows; 30000 rows in sample, 1000000 estimated total rows
VACUUM
*/


-- Vacuum + statistical analysis + print statistics
vacuum analyze verbose pgbench_accounts;

/*

mytest=> vacuum verbose analyze pgbench_accounts;
INFO:  vacuuming "public.pgbench_accounts"
INFO:  "pgbench_accounts": found 0 removable, 37 nonremovable row versions in 1 out of 16394 pages
DETAIL:  0 dead row versions cannot be removed yet, oldest xmin: 626
There were 0 unused item identifiers.
Skipped 0 pages due to buffer pins, 16393 frozen pages.
0 pages are entirely empty.
CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.00 s.
INFO:  analyzing "public.pgbench_accounts"
INFO:  "pgbench_accounts": scanned 16394 of 16394 pages, containing 1000000 live rows and 0 dead rows; 30000 rows in sample, 1000000 estimated total rows
VACUUM

*/

-- VACUUM FULL actively compacts tables by writing a completely new version of the table with no dead space. 
-- This minimizes the size of the table but can take a long time. 
-- It also requires extra disk space for the new copy of the table until the operation is complete.

vacuum full verbose analyze pgbench_accounts;

/*

mytest=> delete from pgbench_accounts where mod(aid,2)=1;
DELETE 500000

mytest=> vacuum full verbose analyze pgbench_accounts;
INFO:  vacuuming "public.pgbench_accounts"
INFO:  "pgbench_accounts": found 500000 removable, 500000 nonremovable row versions in 16394 pages
DETAIL:  0 dead row versions cannot be removed yet.
CPU: user: 0.69 s, system: 0.05 s, elapsed: 0.91 s.
INFO:  analyzing "public.pgbench_accounts"
INFO:  "pgbench_accounts": scanned 8197 of 8197 pages, containing 500000 live rows and 0 dead rows; 30000 rows in sample, 500000 estimated total rows
VACUUM

*/

select name,setting,short_desc from pg_settings where name like '%autovacuum%';

/*

-- Meansured in seconds: autovacuum_naptime
-- Meansured in milliseconds: log_autovacuum_min_duration

mytest=> select name,setting,short_desc from pg_settings where name like '%autovacuum%';
                 name                  |  setting  |                                        short_desc                                         
---------------------------------------+-----------+-------------------------------------------------------------------------------------------
 autovacuum                            | on        | Starts the autovacuum subprocess.
 autovacuum_analyze_scale_factor       | 0.05      | Number of tuple inserts, updates, or deletes prior to analyze as a fraction of reltuples.
 autovacuum_analyze_threshold          | 50        | Minimum number of tuple inserts, updates, or deletes prior to analyze.
 autovacuum_freeze_max_age             | 200000000 | Age at which to autovacuum a table to prevent transaction ID wraparound.
 autovacuum_max_workers                | 3         | Sets the maximum number of simultaneously running autovacuum worker processes.
 autovacuum_multixact_freeze_max_age   | 400000000 | Multixact age at which to autovacuum a table to prevent multixact wraparound.
 autovacuum_naptime                    | 15        | Time to sleep between autovacuum runs.
 autovacuum_vacuum_cost_delay          | 2         | Vacuum cost delay in milliseconds, for autovacuum.
 autovacuum_vacuum_cost_limit          | 200       | Vacuum cost amount available before napping, for autovacuum.
 autovacuum_vacuum_insert_scale_factor | 0.2       | Number of tuple inserts prior to vacuum as a fraction of reltuples.
 autovacuum_vacuum_insert_threshold    | 1000      | Minimum number of tuple inserts prior to vacuum, or -1 to disable insert vacuums.
 autovacuum_vacuum_scale_factor        | 0.1       | Number of tuple updates or deletes prior to vacuum as a fraction of reltuples.
 autovacuum_vacuum_threshold           | 50        | Minimum number of tuple updates or deletes prior to vacuum.
 autovacuum_work_mem                   | -1        | Sets the maximum memory to be used by each autovacuum worker process.
 log_autovacuum_min_duration           | 10000     | Sets the minimum execution time above which autovacuum actions will be logged.
 rds.force_autovacuum_logging_level    | warning   | Emit autovacuum log messages irrespective of other logging configuration.
(16 rows)

*/


select relname, last_analyze, last_autoanalyze from pg_stat_user_tables;

/*

mytest=> select relname, last_analyze, last_autoanalyze from pg_stat_user_tables;
     relname      |         last_analyze          |       last_autoanalyze        
------------------+-------------------------------+-------------------------------
 pgbench_branches | 2021-10-31 03:50:54.714567+00 | 
 pgbench_accounts | 2021-10-31 05:31:17.832021+00 | 
 pgbench_history  | 2021-10-31 03:50:56.206317+00 | 2021-10-31 06:01:03.699672+00
 pgbench_tellers  | 2021-10-31 03:50:54.947703+00 | 
(4 rows)

*/

-- PostgreSQL extension pg_repack to remove bloat from tables and indexes. 
-- You can also opt to restore the physical order of clustered indexes.
-- Unlike CLUSTER and VACUUM FULL, pg_repack works online, 
-- without maintaining an exclusive lock on the processed tables during implementation.

/*
 pg_repack -k -t pgbench_accounts -h postgres-instance1.c5pjidu07yp7.us-east-1.rds.amazonaws.com -U postgres -d mytest

*/

-- To avoid locking on the index's parent table and index while rebuilding the index, 
-- an alternative is to create a new index concurrently and then drop the old index. 
-- PostgreSQL supports rebuilding indexes with minimum locking of writes.
-- This method is invoked by specifying the CONCURRENTLY option of REINDEX. 

create unique index concurrently pgbench_accounts_pkey_new on pgbench_accounts(aid);

select c.conname, t.relname as indexname, ts.spcname as tablespace, pg_get_indexdef(i.indexrelid) as indexdef
from pg_constraint c join pg_index i on c.conindid = i.indexrelid 
    join pg_class t on  t.oid=i.indexrelid 
    left join pg_tablespace ts on ts.oid =t.reltablespace
where conrelid='pgbench_accounts'::regclass;

begin;
-- drop/add constraint only required as the index supports the constraint
alter table pgbench_accounts drop constraint pgbench_accounts_pkey,
    add constraint pgbench_accounts_pkey primary key using index pgbench_accounts_pkey_new;
commit;


/*/


mytest=> \x auto
Expanded display is used automatically.
mytest=> select * from pg_constraint where conrelid='pgbench_accounts'::regclass;
-[ RECORD 1 ]-+----------------------
oid           | 16438
conname       | pgbench_accounts_pkey
connamespace  | 2200
contype       | p
condeferrable | f
condeferred   | f
convalidated  | t
conrelid      | 16423
contypid      | 0
conindid      | 16437
conparentid   | 0
confrelid     | 0
confupdtype   |  
confdeltype   |  
confmatchtype |  
conislocal    | t
coninhcount   | 0
connoinherit  | t
conkey        | {1}
confkey       | 
conpfeqop     | 
conppeqop     | 
conffeqop     | 
conexclop     | 
conbin        | 

mytest=> select c.conname, t.relname as indexname, ts.spcname as tablespace, pg_get_indexdef(i.indexrelid) as indexdef
mytest-> from pg_constraint c join pg_index i on c.conindid = i.indexrelid 
mytest->     join pg_class t on  t.oid=i.indexrelid 
mytest->     left join pg_tablespace ts on ts.oid =t.reltablespace
mytest-> where conrelid='pgbench_accounts'::regclass;

-[ RECORD 1 ]--------------------------------------------------------------------------------------
conname    | pgbench_accounts_pkey
indexname  | pgbench_accounts_pkey
tablespace | 
indexdef   | CREATE UNIQUE INDEX pgbench_accounts_pkey ON public.pgbench_accounts USING btree (aid)


mytest=> begin;
BEGIN

mytest=*> -- drop/add constraint only required as the index supports the constraint
mytest=*> alter table pgbench_accounts drop constraint pgbench_accounts_pkey,
mytest-*>     add constraint pgbench_accounts_pkey primary key using index pgbench_accounts_pkey_new;
NOTICE:  ALTER TABLE / ADD CONSTRAINT USING INDEX will rename index "pgbench_accounts_pkey_new" to "pgbench_accounts_pkey"
ALTER TABLE

mytest=*> commit;
COMMIT
*/



create index concurrently pgbench_accounts_bid on pgbench_accounts(bid);

-- to replace non-pk index with minimal locking

create index concurrently pgbench_accounts_bid_new on pgbench_accounts(bid);

begin;
drop index pgbench_accounts_bid;
alter index pgbench_accounts_bid_new rename to pgbench_accounts_bid;
commit;

-- find out unused indexes
select relname, indexrelid, idx_scan from pg_stat_user_indexes where idx_scan = 0;


/*

mytest=> select relname, indexrelid, idx_scan from pg_stat_user_indexes where idx_scan = 0;
     relname      | indexrelid | idx_scan 
------------------+------------+----------
 pgbench_branches |      16433 |        0
 pgbench_tellers  |      16435 |        0
 pgbench_accounts |      16495 |        0
 pgbench_accounts |      16499 |        0
(4 rows)


mytest=> select relname from pg_class where oid=16433;
        relname        
-----------------------
 pgbench_branches_pkey
(1 row)

*/
