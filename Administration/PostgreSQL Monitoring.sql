-- monitoring process duration
select pid, usename,state,now() - backend_start as connection_time
    from pg_stat_activity
order by connection_time desc;

-- monitoring connection count

select client_addr,usename,count(*)
    from pg_stat_activity where backend_type='client backend'
group by cube(client_addr,usename)
order by count desc;

-- monitoring transaction state
-- There are three states: active, idle, and idle in transaction.

select state, count(*) from pg_stat_activity
    group by state order by count desc;

-- monitoring wait event
select pid,wait_event_type,wait_event 
    from pg_stat_activity where wait_event is not null;


/* 
  Common lightweight wait types
    - LWLock:       Lock protecting a data structure in shared memory
    - Lock:         Lock protecting SQL-visible objects such as tables
    - BufferPin:    Waiting for access to a data buffer
    - Activity:     Waiting for system processes
    - Extension:    Waiting for activity in an extension module
    - Client:       Waiting for some activity on a socket
    - IPC:          Waiting for another process in the server
    - Timeout:      Waiting for a timeout to expire
    -IO:            Waiting for an IO to complete

   A lock is a heavyweight lock. Heavyweight locks are primarily used to protect SQL-visible objects
    - Advisory:     Waiting to acquire an advisory user lock
    - Page:         Waiting to acquire a lock on a page of a relation
    - Userlock:     Waiting to acquire a user lock
    - Relation:     Waiting to acquire a lock on a relation
    - Tuple:        Waiting to acquire a lock on a tuple

   A lightweight lock refers to a quick event. LWLock indicates a lightweight lock.
    - AutoFileL         Waiting to update the PostgreSQL.auto.conf file
    - TablespaceCreate: Waiting to create or drop a tablespace
    - WALWrite:         Waiting for Write Ahead Log (WAL) buffers to be written to disk


mytest=> select pid,wait_event_type,wait_event
mytest->     from pg_stat_activity where wait_event is not null;
  pid  | wait_event_type |     wait_event      
-------+-----------------+---------------------
 19376 | Extension       | Extension
 19372 | Activity        | AutoVacuumMain
 19378 | Activity        | LogicalLauncherMain
 19377 | Extension       | Extension
 19978 | Client          | ClientRead
 20015 | Client          | ClientRead
 19370 | Activity        | BgWriterHibernate
 19369 | Activity        | CheckpointerMain
 19371 | Activity        | WalWriterMain
(9 rows)

*/

-- monitor SSL connection and ciphersuite
select * from pg_stat_ssl;

/*

donghual@88665a1eeb77 Demo % psql "postgresql://postgres@postgres-instance1.c0clzif8j8nh.us-east-1.rds.amazonaws.com/mytest?sslmode=disable"
Password for user postgres: 
psql (13.4)
Type "help" for help.

mytest=> \conninfo
You are connected to database "mytest" as user "postgres" on host "postgres-instance1.c0clzif8j8nh.us-east-1.rds.amazonaws.com" (address "3.210.39.255") at port "5432".


mytest=> select * from pg_stat_ssl;
  pid  | ssl | version |           cipher            | bits | compression | client_dn | client_serial | issuer_dn 
-------+-----+---------+-----------------------------+------+-------------+-----------+---------------+-----------
 19978 | t   | TLSv1.2 | ECDHE-RSA-AES256-GCM-SHA384 |  256 | f           |           |               | 
 20015 | t   | TLSv1.2 | ECDHE-RSA-AES256-GCM-SHA384 |  256 | f           |           |               | 
 21705 | t   | TLSv1.2 | ECDHE-RSA-AES256-GCM-SHA384 |  256 | f           |           |               | 
 15084 | f   |         |                             |      |             |           |               | 
(4 rows)

*/

-- query monitoring
select now()-query_start as runtime, pid, usename,state, wait_event, query::varchar(50)
from pg_stat_activity where query_start is not null order by runtime desc limit 20;

/*

mytest=> select now()-query_start as runtime, pid, usename,state, wait_event, query::varchar(50)
from pg_stat_activity where query_start is not null order by runtime desc limit 20;
     runtime     |  pid  | usename  | state  | wait_event |                       query                        
-----------------+-------+----------+--------+------------+----------------------------------------------------
 00:00:07.357045 | 20015 | rdsadmin | idle   | ClientRead | select * from public.pg_rds_aws_creds_metadata()
 00:00:00.673014 | 19978 | rdsadmin | idle   | ClientRead | COMMIT
 00:00:00        | 21705 | postgres | active |            | select now()-query_start as runtime, pid, usename,
(3 rows)

*/

-- monitor table usage

select * from pg_stat_user_tables;

/*

\x auto
mytest=> select * from pg_stat_user_tables;
-[ RECORD 1 ]-------+------------------------------
relid               | 16417
schemaname          | public
relname             | t
seq_scan            | 7
seq_tup_read        | 14
idx_scan            | 
idx_tup_fetch       | 
n_tup_ins           | 2
n_tup_upd           | 0
n_tup_del           | 0
n_tup_hot_upd       | 0
n_live_tup          | 2
n_dead_tup          | 0
n_mod_since_analyze | 2
n_ins_since_vacuum  | 2
last_vacuum         | 
last_autovacuum     | 
last_analyze        | 
last_autoanalyze    | 
vacuum_count        | 0
autovacuum_count    | 0
analyze_count       | 0
autoanalyze_count   | 0
-[ RECORD 2 ]-------+------------------------------
relid               | 16440
schemaname          | public
relname             | pgbench_tellers
seq_scan            | 101
seq_tup_read        | 10100
idx_scan            | 0
idx_tup_fetch       | 0
n_tup_ins           | 100
n_tup_upd           | 100
n_tup_del           | 0
n_tup_hot_upd       | 100
n_live_tup          | 100
n_dead_tup          | 36
n_mod_since_analyze | 0
n_ins_since_vacuum  | 0
last_vacuum         | 2021-10-30 09:36:28.007766+00
last_autovacuum     | 
last_analyze        | 2021-10-30 08:57:41.749514+00
last_autoanalyze    | 2021-10-30 09:37:08.535848+00
vacuum_count        | 2
autovacuum_count    | 0
analyze_count       | 1
autoanalyze_count   | 1
-[ RECORD 3 ]-------+------------------------------
relid               | 16446
schemaname          | public
relname             | pgbench_branches
seq_scan            | 102
seq_tup_read        | 1020
idx_scan            | 0
idx_tup_fetch       | 0
n_tup_ins           | 10
n_tup_upd           | 100
n_tup_del           | 0
n_tup_hot_upd       | 100
n_live_tup          | 10
n_dead_tup          | 0
n_mod_since_analyze | 0
n_ins_since_vacuum  | 0
last_vacuum         | 2021-10-30 09:36:27.759726+00
last_autovacuum     | 2021-10-30 09:37:08.521386+00
last_analyze        | 2021-10-30 08:57:41.503499+00
last_autoanalyze    | 2021-10-30 09:37:08.523871+00
vacuum_count        | 2
autovacuum_count    | 1
analyze_count       | 1
autoanalyze_count   | 1
-[ RECORD 4 ]-------+------------------------------
relid               | 16437
schemaname          | public
relname             | pgbench_history
seq_scan            | 0
seq_tup_read        | 0
idx_scan            | 
idx_tup_fetch       | 
n_tup_ins           | 100
n_tup_upd           | 0
n_tup_del           | 0
n_tup_hot_upd       | 0
n_live_tup          | 100
n_dead_tup          | 0
n_mod_since_analyze | 0
n_ins_since_vacuum  | 100
last_vacuum         | 2021-10-30 08:57:43.152202+00
last_autovacuum     | 
last_analyze        | 2021-10-30 08:57:43.152373+00
last_autoanalyze    | 2021-10-30 09:37:08.547477+00
vacuum_count        | 1
autovacuum_count    | 0
analyze_count       | 1
autoanalyze_count   | 1
-[ RECORD 5 ]-------+------------------------------
relid               | 16422
schemaname          | public
relname             | t2
seq_scan            | 4
seq_tup_read        | 8
idx_scan            | 
idx_tup_fetch       | 
n_tup_ins           | 2
n_tup_upd           | 0
n_tup_del           | 0
n_tup_hot_upd       | 0
n_live_tup          | 2
n_dead_tup          | 0
n_mod_since_analyze | 2
n_ins_since_vacuum  | 2
last_vacuum         | 
last_autovacuum     | 
last_analyze        | 
last_autoanalyze    | 
vacuum_count        | 0
autovacuum_count    | 0
analyze_count       | 0
autoanalyze_count   | 0
-[ RECORD 6 ]-------+------------------------------
relid               | 16443
schemaname          | public
relname             | pgbench_accounts
seq_scan            | 2
seq_tup_read        | 1000000
idx_scan            | 200
idx_tup_fetch       | 200
n_tup_ins           | 1000000
n_tup_upd           | 100
n_tup_del           | 0
n_tup_hot_upd       | 0
n_live_tup          | 1000000
n_dead_tup          | 100
n_mod_since_analyze | 100
n_ins_since_vacuum  | 0
last_vacuum         | 2021-10-30 08:57:42.775597+00
last_autovacuum     | 
last_analyze        | 2021-10-30 08:57:42.895531+00
last_autoanalyze    | 
vacuum_count        | 1
autovacuum_count    | 0
analyze_count       | 1
autoanalyze_count   | 0

*/

select relid,schemaname,seq_scan,seq_tup_read,idx_scan,idx_tup_fetch,n_tup_ins,n_tup_upd,n_tup_del
from pg_stat_user_tables;

/*

mytest=> 
mytest=> select relid,schemaname,seq_scan,seq_tup_read,idx_scan,idx_tup_fetch,n_tup_ins,n_tup_upd,n_tup_del
mytest-> from pg_stat_user_tables;
 relid | schemaname | seq_scan | seq_tup_read | idx_scan | idx_tup_fetch | n_tup_ins | n_tup_upd | n_tup_del 
-------+------------+----------+--------------+----------+---------------+-----------+-----------+-----------
 16417 | public     |        7 |           14 |          |               |         2 |         0 |         0
 16440 | public     |      101 |        10100 |        0 |             0 |       100 |       100 |         0
 16446 | public     |      102 |         1020 |        0 |             0 |        10 |       100 |         0
 16437 | public     |        0 |            0 |          |               |       100 |         0 |         0
 16422 | public     |        4 |            8 |          |               |         2 |         0 |         0
 16443 | public     |        2 |      1000000 |      200 |           200 |   1000000 |       100 |         0
(6 rows)

*/

select relid,schemaname,(seq_scan+idx_scan) as "Total Reads", (n_tup_ins+n_tup_upd+n_tup_del) as "Total Writes"
from pg_stat_user_tables;

/*
mytest=> select relid,schemaname,(seq_scan+idx_scan) as "Total Reads", (n_tup_ins+n_tup_upd+n_tup_del) as "Total Writes"
mytest-> from pg_stat_user_tables;
 relid | schemaname | Total Reads | Total Writes 
-------+------------+-------------+--------------
 16426 | public     |          27 |           34
 16423 | public     |          50 |      1000024
 16417 | public     |             |           24
 16420 | public     |          25 |          124
(4 rows)
*/


select pid, relid, phase, heap_blks_total, heap_blks_scanned, heap_blks_vacuumed
from pg_stat_progress_vacuum;

-- order by total_exec_time desc
select query::varchar(50),calls,total_exec_time::int,rows,
    round(100.0*shared_blks_hit/nullif(shared_blks_hit+shared_blks_read, 0),2) as hit_percent
from pg_stat_statements order by total_exec_time desc limit 20;

/*

mytest=> select query::varchar(50),calls,total_exec_time::int,rows,
mytest->     round(100.0*shared_blks_hit/nullif(shared_blks_hit+shared_blks_read, 0),2) as hit_percent
mytest-> from pg_stat_statements order by total_exec_time desc limit 20;
                       query                        | calls | total_exec_time |  rows   | hit_percent 
----------------------------------------------------+-------+-----------------+---------+-------------
 copy pgbench_accounts from stdin                   |     1 |            4388 | 1000000 |      100.00
 vacuum analyze pgbench_accounts                    |     1 |            1492 |       0 |       41.76
 alter table pgbench_accounts add primary key (aid) |     1 |            1186 |       0 |       13.24
 select sum(numbackends) numbackends, sum(xact_comm |    91 |             981 |      91 |      100.00
 select pid, usename, client_addr, client_hostname, |  5429 |             531 |    5439 |      100.00
 select * from public.pg_rds_aws_creds_metadata()   |   334 |             238 |     334 |            
 create extension pg_stat_statements                |     1 |             106 |       0 |       97.19
 CREATE database "mytest" WITH owner = "postgres"   |     1 |              65 |       0 |       87.50
 BEGIN                                              |  7239 |              47 |       0 |            
 MOVE ALL IN "query-cursor_1"                       |    87 |              44 |       0 |      100.00
 DECLARE "query-cursor_1" SCROLL CURSOR FOR select  |    87 |              31 |       0 |      100.00
 select count(*) active_count from pg_stat_activity |   273 |              30 |     273 |            
 select count(distinct transactionid::varchar) acti |    91 |              29 |      91 |      100.00
 vacuum analyze pgbench_branches                    |     1 |              29 |       0 |       83.25
 CREATE EXTENSION IF NOT EXISTS pg_stat_statements  |     1 |              27 |       0 |       94.78
 select count(distinct pid) blocked_transactions fr |    91 |              26 |      91 |      100.00
 COMMIT                                             |  7255 |              25 |       0 |            
 select query,calls,total_exec_time,rows,          +|     1 |              24 |      20 |      100.00
     $1*sh                                          |       |                 |         | 
 alter table pgbench_branches add primary key (bid) |     1 |              23 |       0 |       88.40
 vacuum pgbench_branches                            |     2 |              21 |       0 |      100.00
(20 rows)

*/


-- order by avg_exec_time desc
select query::varchar(50),calls,round(total_exec_time::int/calls,0) as avg_exec_time,rows,
    round(100.0*shared_blks_hit/nullif(shared_blks_hit+shared_blks_read, 0),2) as hit_percent
from pg_stat_statements order by avg_exec_time desc limit 20;

/*

mytest=> select query::varchar(50),calls,round(total_exec_time::int/calls,0) as avg_exec_time,rows,
mytest->     round(100.0*shared_blks_hit/nullif(shared_blks_hit+shared_blks_read, 0),2) as hit_percent
mytest-> from pg_stat_statements order by avg_exec_time desc limit 20;
                       query                        | calls | avg_exec_time |  rows   | hit_percent 
----------------------------------------------------+-------+---------------+---------+-------------
 copy pgbench_accounts from stdin                   |     1 |          4388 | 1000000 |      100.00
 vacuum analyze pgbench_accounts                    |     1 |          1492 |       0 |       41.76
 alter table pgbench_accounts add primary key (aid) |     1 |          1186 |       0 |       13.24
 create extension pg_stat_statements                |     1 |           106 |       0 |       97.19
 CREATE database "mytest" WITH owner = "postgres"   |     1 |            65 |       0 |       87.50
 vacuum analyze pgbench_branches                    |     1 |            29 |       0 |       83.25
 CREATE EXTENSION IF NOT EXISTS pg_stat_statements  |     1 |            27 |       0 |       94.78
 select query,calls,total_exec_time,rows,          +|     1 |            24 |      20 |      100.00
     $1*sh                                          |       |               |         | 
 alter table pgbench_branches add primary key (bid) |     1 |            23 |       0 |       88.40
 vacuum analyze pgbench_history                     |     1 |            11 |       0 |       97.00
 vacuum pgbench_branches                            |     2 |            10 |       0 |      100.00
 select sum(numbackends) numbackends, sum(xact_comm |    93 |            10 |      93 |      100.00
 select relid,schemaname,(seq_scan+idx_scan) as "To |     1 |            10 |       4 |      100.00
 CREATE TABLE rds_heartbeat2(id INTEGER PRIMARY KEY |     1 |             9 |       0 |       83.14
 create table pgbench_history(tid int,bid int,aid   |     1 |             6 |       0 |       82.29
 SELECT DATNAME, LARGEST_DB_BYTES, ALL_DB_BYTES, OL |     1 |             5 |       3 |      100.00
 alter table pgbench_tellers add primary key (tid)  |     1 |             3 |       0 |      100.00
 SELECT e.extname AS "Name", e.extversion AS "Versi |     1 |             3 |       1 |       20.00
 SELECT public.rds_set_password($1,$2)              |     4 |             3 |       4 |       96.93
 vacuum analyze pgbench_tellers                     |     1 |             2 |       0 |       95.79
(20 rows)

*/

/*
 Other extensions:

    - pgstattuple:      Provides information about rows in the database. 
    - pgrowlocks:       Provides details about a table, such as if there are locks on individual rows. 
                        This is important if the user is trying to update a row that has references tied to it.
    - pg_freespacemap:  Shows free space on the individual pages on the database. 
                        This is useful to the DBA. It communicates whether there is enough space or 
                        if the user might need to add a new page.
*/



