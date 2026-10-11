# PostgreSQL Monitoring Queries

A collection of monitoring queries built around PostgreSQL's cumulative
statistics views (`pg_stat_activity`, `pg_stat_user_tables`,
`pg_stat_statements`, `pg_locks`, and friends). Each query is paired with real
`psql` output captured against an Amazon RDS for PostgreSQL 13 instance running
a `pgbench` workload, with notes on what the numbers reveal and how to interpret
them.

## Sessions and activity

`pg_stat_activity` has one row per backend. The queries below slice it by age,
client, transaction state, and wait event.

### Connection age

Order sessions by how long they have been connected. Long-lived connections are
not inherently a problem, but a session that has been idle in a transaction for
a long time can hold locks and pin old row versions.

```sql
select pid, usename, state, now() - backend_start as connection_time
    from pg_stat_activity
order by connection_time desc;
```

### Connection count by client and user

`cube(client_addr, usename)` produces per-client, per-user, and grand-total
rows in one pass, so you can see where connections originate. Filtering on
`backend_type = 'client backend'` excludes background workers.

```sql
select client_addr, usename, count(*)
    from pg_stat_activity where backend_type='client backend'
group by cube(client_addr, usename)
order by count desc;
```

### Transaction state

There are three main states: `active`, `idle`, and `idle in transaction`. A
growing count of `idle in transaction` is a warning sign — those sessions hold
resources without doing work.

```sql
select state, count(*) from pg_stat_activity
    group by state order by count desc;
```

### Wait events

A non-null `wait_event` means the backend is blocked on something. This is the
starting point for diagnosing contention.

```sql
select pid, wait_event_type, wait_event
    from pg_stat_activity where wait_event is not null;
```

```text
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
```

Here all the waits are benign: background processes idling (`Activity`),
extensions idling (`Extension`), and client backends waiting for the next query
(`Client` / `ClientRead`).

Reference — common wait event categories:

```text
Common lightweight wait types
  - LWLock:       Lock protecting a data structure in shared memory
  - Lock:         Lock protecting SQL-visible objects such as tables
  - BufferPin:    Waiting for access to a data buffer
  - Activity:     Waiting for system processes
  - Extension:    Waiting for activity in an extension module
  - Client:       Waiting for some activity on a socket
  - IPC:          Waiting for another process in the server
  - Timeout:      Waiting for a timeout to expire
  - IO:           Waiting for an IO to complete

A lock is a heavyweight lock. Heavyweight locks are primarily used to protect
SQL-visible objects
  - Advisory:     Waiting to acquire an advisory user lock
  - Page:         Waiting to acquire a lock on a page of a relation
  - Userlock:     Waiting to acquire a user lock
  - Relation:     Waiting to acquire a lock on a relation
  - Tuple:        Waiting to acquire a lock on a tuple

A lightweight lock refers to a quick event. LWLock indicates a lightweight lock.
  - AutoFileL         Waiting to update the PostgreSQL.auto.conf file
  - TablespaceCreate: Waiting to create or drop a tablespace
  - WALWrite:         Waiting for Write Ahead Log (WAL) buffers to be written to disk
```

## SSL connections

`pg_stat_ssl` reports, per backend, whether SSL is in use and which cipher was
negotiated. The example connects with `sslmode=disable` and then inspects the
view.

```sql
select * from pg_stat_ssl;
```

```text
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
```

Even though this session used `sslmode=disable` for its own connection, the
other backends on the instance negotiated TLSv1.2 with
`ECDHE-RSA-AES256-GCM-SHA384`. The row with `ssl = f` is the non-encrypted
backend.

## Running queries

List the longest-running statements with their state and wait event. `runtime`
is derived from `now() - query_start`, so for `idle` sessions it reflects how
long ago the last statement ran rather than active work.

```sql
select now()-query_start as runtime, pid, usename, state, wait_event, query::varchar(50)
from pg_stat_activity where query_start is not null order by runtime desc limit 20;
```

```text
mytest=> select now()-query_start as runtime, pid, usename,state, wait_event, query::varchar(50)
from pg_stat_activity where query_start is not null order by runtime desc limit 20;
     runtime     |  pid  | usename  | state  | wait_event |                       query
-----------------+-------+----------+--------+------------+----------------------------------------------------
 00:00:07.357045 | 20015 | rdsadmin | idle   | ClientRead | select * from public.pg_rds_aws_creds_metadata()
 00:00:00.673014 | 19978 | rdsadmin | idle   | ClientRead | COMMIT
 00:00:00        | 21705 | postgres | active |            | select now()-query_start as runtime, pid, usename,
(3 rows)
```

The only `active` statement is the monitoring query itself; the `rdsadmin`
backends are idle, waiting on `ClientRead`.

## Table usage

`pg_stat_user_tables` tracks scan counts, tuple-level write counts, live/dead
tuple estimates, and the last (auto)vacuum/analyze times for each user table.

The full view, shown here in expanded (`\x`) mode:

```sql
select * from pg_stat_user_tables;
```

```text
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
```

Note that `pgbench_accounts` was populated with a bulk `COPY` of 1,000,000 rows
(`n_tup_ins = 1000000`) and still shows a large `seq_tup_read` — index scans
only kicked in (`idx_scan = 200`) after the primary key was added.

### Narrower projection of scan and write counts

```sql
select relid,schemaname,seq_scan,seq_tup_read,idx_scan,idx_tup_fetch,n_tup_ins,n_tup_upd,n_tup_del
from pg_stat_user_tables;
```

```text
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
```

### Total reads vs. total writes per table

Collapsing scans and write counts into two columns gives a quick read/write
profile of each table, useful for spotting write-heavy tables that may need
tuning or indexing attention.

```sql
select relid,schemaname,(seq_scan+idx_scan) as "Total Reads", (n_tup_ins+n_tup_upd+n_tup_del) as "Total Writes"
from pg_stat_user_tables;
```

```text
mytest=> select relid,schemaname,(seq_scan+idx_scan) as "Total Reads", (n_tup_ins+n_tup_upd+n_tup_del) as "Total Writes"
mytest-> from pg_stat_user_tables;
 relid | schemaname | Total Reads | Total Writes
-------+------------+-------------+--------------
 16426 | public     |          27 |           34
 16423 | public     |          50 |      1000024
 16417 | public     |             |           24
 16420 | public     |          25 |          124
(4 rows)
```

Note that `Total Reads` is null for `relid 16417`: because `idx_scan` is null
(no index), `seq_scan + idx_scan` evaluates to null.

## Vacuum progress

`pg_stat_progress_vacuum` exposes live progress for currently running vacuums —
useful for estimating how far along a large vacuum is.

```sql
select pid, relid, phase, heap_blks_total, heap_blks_scanned, heap_blks_vacuumed
from pg_stat_progress_vacuum;
```

## Statement statistics (pg_stat_statements)

The `pg_stat_statements` extension aggregates execution metrics per normalized
statement. Enable it with:

```sql
create extension pg_stat_statements;
```

### Ordered by total execution time

Total time surfaces the statements that cost the most cumulatively — a cheap
query run millions of times can outrank an expensive one-off. `hit_percent` is
the shared-buffer cache hit ratio for that statement.

```sql
select query::varchar(50),calls,total_exec_time::int,rows,
    round(100.0*shared_blks_hit/nullif(shared_blks_hit+shared_blks_read, 0),2) as hit_percent
from pg_stat_statements order by total_exec_time desc limit 20;
```

```text
mytest=> create extension pg_stat_statements;
CREATE EXTENSION

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
```

The bulk `COPY` of 1,000,000 rows dominates total time, followed by the vacuum
and primary-key creation on `pgbench_accounts`. Note the low cache hit ratios
(`41.76`, `13.24`) on those first-touch operations — the data was being read
from storage, not cache.

### Ordered by average execution time

Dividing total time by `calls` highlights individually expensive statements
regardless of frequency.

```sql
select query::varchar(50),calls,round(total_exec_time::int/calls,0) as avg_exec_time,rows,
    round(100.0*shared_blks_hit/nullif(shared_blks_hit+shared_blks_read, 0),2) as hit_percent
from pg_stat_statements order by avg_exec_time desc limit 20;
```

```text
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
```

Because most of the top rows have `calls = 1`, the average-time ranking looks
similar to the total-time ranking here; the frequently-called monitoring
queries drop down the list.

Other extensions worth knowing for deeper inspection:

```text
Other extensions:

  - pgstattuple:      Provides information about rows in the database.
  - pgrowlocks:       Provides details about a table, such as if there are locks on individual rows.
                      This is important if the user is trying to update a row that has references tied to it.
  - pg_freespacemap:  Shows free space on the individual pages on the database.
                      This is useful to the DBA. It communicates whether there is enough space or
                      if the user might need to add a new page.
```

## Locks and blocking

`pg_locks` shows every lock currently held or awaited. Filtering by a specific
relation (via `'t'::regclass`) narrows it to one table so you can see which
backends hold which lock modes.

```sql
select * from pg_locks where relation='t'::regclass;
```

```text
mytest=> select * from pg_locks where relation='t'::regclass;
-[ RECORD 1 ]------+-----------------
locktype           | relation
database           | 16402
relation           | 16455
page               |
tuple              |
virtualxid         |
transactionid      |
classid            |
objid              |
objsubid           |
virtualtransaction | 7/2941
pid                | 19208
mode               | RowExclusiveLock
granted            | t
fastpath           | t
-[ RECORD 2 ]------+-----------------
locktype           | relation
database           | 16402
relation           | 16455
page               |
tuple              |
virtualxid         |
transactionid      |
classid            |
objid              |
objsubid           |
virtualtransaction | 8/65
pid                | 19813
mode               | RowExclusiveLock
granted            | t
fastpath           | t
-[ RECORD 3 ]------+-----------------
locktype           | tuple
database           | 16402
relation           | 16455
page               | 0
tuple              | 1
virtualxid         |
transactionid      |
classid            |
objid              |
objsubid           |
virtualtransaction | 8/65
pid                | 19813
mode               | ExclusiveLock
granted            | t
fastpath           | f
```

Both backends hold a `RowExclusiveLock` on the table, and backend `19813` has
additionally taken a tuple-level `ExclusiveLock` on `page 0, tuple 1`. That
tuple lock points directly at the contended row.

Cross-referencing the two PIDs against `pg_stat_activity` reveals the classic
blocking pattern — one session is `idle in transaction` holding the row, the
other is `active` but waiting on `Lock / transactionid`:

```text
mytest=> select * from pg_stat_activity where pid in (19208,19813);
-[ RECORD 1 ]----+------------------------------
datid            | 16402
datname          | mytest
pid              | 19813
leader_pid       |
usesysid         | 16400
usename          | postgres
application_name | psql
client_addr      | 116.14.204.216
client_hostname  |
client_port      | 55195
backend_start    | 2021-10-30 16:27:55.308849+00
xact_start       | 2021-10-30 16:28:18.371692+00
query_start      | 2021-10-30 16:28:18.371692+00
state_change     | 2021-10-30 16:28:18.371694+00
wait_event_type  | Lock
wait_event       | transactionid
state            | active
backend_xid      | 665
backend_xmin     | 664
query            | update t set id=2 where id=1;
backend_type     | client backend
-[ RECORD 2 ]----+------------------------------
datid            | 16402
datname          | mytest
pid              | 19208
leader_pid       |
usesysid         | 16400
usename          | postgres
application_name | psql
client_addr      | 116.14.204.216
client_hostname  |
client_port      | 55182
backend_start    | 2021-10-30 16:27:28.804831+00
xact_start       | 2021-10-30 16:28:02.815479+00
query_start      | 2021-10-30 16:28:12.075471+00
state_change     | 2021-10-30 16:28:12.076033+00
wait_event_type  | Client
wait_event       | ClientRead
state            | idle in transaction
backend_xid      | 664
backend_xmin     |
query            | update t set id=2 where id=1;
backend_type     | client backend
```

Backend `19208` ran `update t set id=2 where id=1;` and left its transaction
open (`idle in transaction`, waiting on `ClientRead`), holding the row lock.
Backend `19813` issued the same update and is now `active` but blocked, waiting
on `transactionid` for `19208`'s transaction (`backend_xid 664`) to finish.

### Finding the locked row from the lock coordinates

The `page = 0, tuple = 1` from `pg_locks` can be reassembled into a `ctid`
(`(0,1)`) to look up the exact contended row. The `ctid` will change once the
original transaction commits and the row version moves.

```sql
select ctid,* from t where (ctid::text::point)[0]::int = 0 and (ctid::text::point)[1]::int=1;
```

```text
mytest=> select ctid,* from t where (ctid::text::point)[0]::int = 0 and (ctid::text::point)[1]::int=1;

 ctid  | id
-------+----
 (0,1) |  1
```

## Takeaways

- `pg_stat_activity` is the first stop: slice it by connection age, client,
  transaction state, and wait event to understand what sessions are doing.
- Watch for `idle in transaction` sessions — they hold locks and old row
  versions and are a common source of blocking.
- A non-null `wait_event` tells you *why* a backend is stuck; `Lock /
  transactionid` combined with an `idle in transaction` blocker is the classic
  row-contention signature.
- `pg_stat_user_tables` reveals scan/write mix, dead-tuple accumulation, and
  (auto)vacuum/analyze history per table; null `idx_scan` means no index is
  being used.
- Enable `pg_stat_statements` and rank by both total and average execution time:
  total time finds the biggest cumulative cost, average time finds individually
  expensive statements. Low `hit_percent` points at storage reads.
- `pg_locks` down to tuple granularity plus the `ctid` trick lets you identify
  the exact blocked row, which you can then join back to `pg_stat_activity` by
  PID to see both the blocker and the waiter.
- Extensions like `pgstattuple`, `pgrowlocks`, and `pg_freespacemap` provide
  deeper per-row and per-page inspection when the standard views aren't enough.
