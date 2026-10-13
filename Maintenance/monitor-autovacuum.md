# Monitoring Autovacuum

PostgreSQL relies on `VACUUM` to reclaim space left behind by dead row versions
(the result of `UPDATE` and `DELETE`) and to prevent transaction-ID
wraparound. The `autovacuum` daemon does this automatically in the background.
This note walks through monitoring autovacuum behavior on an Amazon RDS for
PostgreSQL instance: watching per-table statistics, reading the autovacuum log
messages, understanding why dead tuples accumulate when a long-running
transaction holds back the oldest snapshot, and checking how close each
database is to a wraparound-driven emergency vacuum.

All commands and output below are transcribed from a real session on
`2021-11-28` against a `pgbench`-populated database named `mytest`.

## Per-table vacuum statistics

`pg_stat_user_tables` records, among other things, when each table was last
vacuumed manually (`last_vacuum`) and by autovacuum (`last_autovacuum`), along
with the current estimate of dead tuples (`n_dead_tup`).

```sql
SELECT relname, last_vacuum, last_autovacuum, n_dead_tup FROM pg_stat_user_tables;
```

Immediately after loading the `pgbench` tables, only manual vacuums have run,
`last_autovacuum` is empty, and there are no dead tuples:

```text
mytest=> SELECT relname, last_vacuum, last_autovacuum,n_dead_tup FROM pg_stat_user_tables;
     relname      |          last_vacuum          | last_autovacuum | n_dead_tup 
------------------+-------------------------------+-----------------+------------
 pgbench_branches | 2021-11-28 11:52:06.075918+00 |                 |          0
 pgbench_accounts | 2021-11-28 11:52:26.421433+00 |                 |          0
 pgbench_history  | 2021-11-28 11:52:26.874922+00 |                 |          0
 pgbench_tellers  | 2021-11-28 11:52:06.35523+00  |                 |          0
(4 rows)
```

## Reading autovacuum activity from the RDS log

On RDS you can tail the PostgreSQL log stream with the AWS CLI to see
autovacuum and analyze events as they happen:

```bash
aws logs tail "/aws/rds/instance/database-1/postgresql" --follow
```

Once `pgbench` traffic starts generating row churn, autovacuum begins firing on
the small, hot tables. A single automatic vacuum of `pgbench_branches` reports
how many pages and tuples it touched, how many dead tuples were *not yet
removable*, the `oldest xmin` snapshot bound, buffer usage, I/O rates, and WAL
generated:

```text
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
```

At this point every vacuum reports `0 are dead but not yet removable` — nothing
is holding back cleanup, so dead tuples get reclaimed immediately.

## A long-running transaction holds back the oldest snapshot

Now open a `REPEATABLE READ` transaction in one session and leave it open. The
snapshot it took pins the `oldest xmin`, so even though autovacuum keeps
running, it cannot remove rows that became dead *after* that snapshot:

```sql
mytest=> begin transaction isolation level repeatable read;
mytest=*> select * from pgbench_branches;
```

The log now shows the "dead but not yet removable" count climbing while
`oldest xmin` stays pinned at `1092`:

```text
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

... (vacuums keep running; "dead but not yet removable" keeps growing, oldest xmin still 1092) ...

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
```

Notice `tuples: 0 removed` on every run — vacuum is doing work but reclaiming
nothing, because the still-open snapshot might need those rows.

## Checking distance to transaction-ID wraparound

The following query reports the oldest unfrozen transaction age across all
databases that allow connections, expressed both as a percentage toward hard
wraparound (`max_old_xid`, 2 billion) and toward the point where PostgreSQL
forces an *emergency* anti-wraparound autovacuum
(`autovacuum_freeze_max_age`):

```sql
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
```

Here the oldest XID age is tiny, so both percentages round to `0`:

```text
 oldest_current_xid | percent_towards_wraparound | percent_towards_emergency_autovac 
--------------------+----------------------------+-----------------------------------
               1418 |                          0 |                                 0
(1 row)
```

### Per-database freeze age

A simpler per-database view of `age(datfrozenxid)` alongside the configured
`autovacuum_freeze_max_age`:

```sql
SELECT datname
, age(datfrozenxid)
, current_setting('autovacuum_freeze_max_age') 
FROM pg_database 
ORDER BY 2 DESC;
```

```text
  datname  | age  | current_setting 
-----------+------+-----------------
 template0 | 1442 | 200000000
 rdsadmin  | 1442 | 200000000
 template1 | 1442 | 200000000
 postgres  | 1442 | 200000000
 mytest    | 1442 | 200000000
```

### Per-relation freeze age and size

Drilling down to individual relations shows `age(relfrozenxid)` and on-disk
size, which helps identify which tables an anti-wraparound vacuum would need to
process:

```sql
SELECT c.oid::regclass
, age(c.relfrozenxid)
, pg_size_pretty(pg_total_relation_size(c.oid)) 
FROM pg_class c
JOIN pg_namespace n on c.relnamespace = n.oid
WHERE relkind IN ('r', 't', 'm') 
AND n.nspname NOT IN ('pg_toast')
ORDER BY 2 DESC LIMIT 100;
```

The catalog tables all share the same age; among user tables, `pgbench_accounts`
is by far the largest at 1496 MB:

```text
                    oid                     | age  | pg_size_pretty 
--------------------------------------------+------+----------------
 information_schema.sql_features            | 1467 | 104 kB
 pg_subscription_rel                        | 1467 | 8192 bytes
 information_schema.sql_implementation_info | 1467 | 48 kB
 information_schema.sql_parts               | 1467 | 48 kB
 information_schema.sql_sizing              | 1467 | 48 kB
 pg_statistic                               | 1467 | 368 kB
 pg_type                                    | 1467 | 192 kB

... (catalog relations elided; all show age 1467) ...

 pg_publication                             | 1467 | 16 kB
 pg_publication_rel                         | 1467 | 16 kB
 pgbench_branches                           | 1363 | 96 kB
 pgbench_tellers                            | 1363 | 184 kB
 pgbench_accounts                           | 1363 | 1496 MB
 pgbench_history                            | 1352 | 136 kB
(70 rows)
```

Meanwhile, with the old snapshot still open, even catalog tables such as
`pg_statistic` accumulate non-removable dead tuples at `oldest xmin: 1092`:

```text
2021-11-28T12:26:44+00:00 database-1.0 2021-11-28 12:26:44 UTC::@:[528]:LOG:  00000: automatic vacuum of table "mytest.pg_catalog.pg_statistic": index scans: 0
     pages: 0 removed, 31 remain, 0 skipped due to pins, 0 skipped frozen
     tuples: 0 removed, 564 remain, 145 are dead but not yet removable, oldest xmin: 1092
     buffer usage: 70 hits, 0 misses, 0 dirtied
     avg read rate: 0.000 MB/s, avg write rate: 0.000 MB/s
     system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.00 s
     WAL usage: 0 records, 0 full page images, 0 bytes
2021-11-28T12:26:44+00:00 database-1.0 2021-11-28 12:26:44 UTC::@:[528]:LOCATION:  heap_vacuum_rel, vacuumlazy.c:690
```

## Committing releases the held-back tuples

Once the long transaction commits, the pinning snapshot is gone. The next
autovacuum advances `oldest xmin` (now `2325`) and finally reports
`tuples ... removed` with `0 are dead but not yet removable`:

```sql
mytest=*> commit;
```

```text
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
```

## A snapshot only blocks removal of rows that die after it

Opening a new `REPEATABLE READ` transaction that only reads one small table
still takes a snapshot (`txid_current()` returns `2854`):

```sql
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
```

Vacuums continue, and now the number held back is small (just a handful of
tuples that died after `oldest xmin: 2852`):

```text
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
```

## A single open write transaction can block the whole system

A more dramatic case: open a transaction, insert a row, and read back a very
large `txid_current()` (`81848`) — then leave it open:

```sql
mytest=> begin transaction;
BEGIN
mytest=*> insert into pgbench_branches values(100000,0,0);
INSERT 0 1
mytest=*> select txid_current();
 txid_current 
--------------
        81848
(1 row)
```

With this transaction pinning `oldest xmin: 81848`, autovacuum runs on table
after table but can remove almost nothing. The dead-but-not-removable counts
balloon into the tens of thousands:

```text
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
```

Querying `pg_stat_user_tables` now shows large `n_dead_tup` on the hot tables,
and watching it (via `\watch`) shows the counts still climbing second by
second:

```text
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
```

## Autovacuum is per-database

The oldest-snapshot pin is global, but each database has its own autovacuum
scheduling. In a different database `mytest2`, a freshly churned table `t2`
gets vacuumed on its own schedule and its dead tuples are reclaimed
(`last_autovacuum` set, `n_dead_tup` back to 0):

```sql
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
```

The corresponding log confirms `t2` had 500000 tuples actually removed (its
`oldest xmin: 299104` is local to `mytest2`), while over in `mytest` the vacuum
of `pgbench_branches` is still blocked at `oldest xmin: 81848` with over 200k
unremovable dead tuples:

```text
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
```

## Recovery after the blocking transaction ends

When the blocking transaction in `mytest` finally ends (note the operator
fat-fingered `commit` as `ommit`, which the log records as a syntax error), the
next autovacuum pass finally removes the backlog — hundreds of tuples per run,
with `oldest xmin` jumping to the mid-300000s and dead-but-not-removable
dropping back to single digits:

```text
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
2021-11-28T12:55:49+00:00 database-1.0 2021-11-28 12:55:49 UTC::@:[2061]:LOG:  00000: automatic vacuum of table "mytest.public.pgbench_tellers": index scans: 1
     pages: 0 removed, 1424 remain, 0 skipped due to pins, 0 skipped frozen
     tuples: 884 removed, 1009 remain, 9 are dead but not yet removable, oldest xmin: 346453
     buffer usage: 4547 hits, 0 misses, 1 dirtied
     avg read rate: 0.000 MB/s, avg write rate: 0.064 MB/s
     system usage: CPU: user: 0.06 s, system: 0.00 s, elapsed: 0.12 s
     WAL usage: 3117 records, 1 full page images, 680117 bytes
2021-11-28T12:55:49+00:00 database-1.0 2021-11-28 12:55:49 UTC::@:[2061]:LOCATION:  heap_vacuum_rel, vacuumlazy.c:690
2021-11-28T12:55:49+00:00 database-1.0 2021-11-28 12:55:49 UTC::@:[2061]:LOG:  00000: automatic vacuum of table "mytest.pg_catalog.pg_statistic": index scans: 1
     pages: 0 removed, 53 remain, 0 skipped due to pins, 0 skipped frozen
     tuples: 33 removed, 419 remain, 0 are dead but not yet removable, oldest xmin: 346494
     buffer usage: 156 hits, 1 misses, 2 dirtied
     avg read rate: 6.166 MB/s, avg write rate: 12.332 MB/s
     system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.00 s
     WAL usage: 82 records, 3 full page images, 6083 bytes
2021-11-28T12:55:49+00:00 database-1.0 2021-11-28 12:55:49 UTC::@:[2061]:LOCATION:  heap_vacuum_rel, vacuumlazy.c:690

... (subsequent passes at 12:56:03 and 12:56:18 continue reclaiming tuples; "skipped frozen" rises as pages become all-frozen) ...

2021-11-28T12:56:18+00:00 database-1.0 2021-11-28 12:56:18 UTC::@:[2535]:LOG:  00000: automatic vacuum of table "mytest.public.pgbench_branches": index scans: 0
     pages: 0 removed, 1162 remain, 0 skipped due to pins, 1158 skipped frozen
     tuples: 255 removed, 204 remain, 4 are dead but not yet removable, oldest xmin: 360179
     buffer usage: 52 hits, 0 misses, 0 dirtied
     avg read rate: 0.000 MB/s, avg write rate: 0.000 MB/s
     system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.00 s
     WAL usage: 6 records, 0 full page images, 1302 bytes
2021-11-28T12:56:18+00:00 database-1.0 2021-11-28 12:56:18 UTC::@:[2535]:LOCATION:  heap_vacuum_rel, vacuumlazy.c:690
2021-11-28T12:56:18+00:00 database-1.0 2021-11-28 12:56:18 UTC::@:[2535]:LOG:  00000: automatic vacuum of table "mytest.public.pgbench_tellers": index scans: 0
     pages: 0 removed, 1424 remain, 0 skipped due to pins, 1362 skipped frozen
     tuples: 1402 removed, 1956 remain, 0 are dead but not yet removable, oldest xmin: 360201
     buffer usage: 150 hits, 0 misses, 0 dirtied
     avg read rate: 0.000 MB/s, avg write rate: 0.000 MB/s
     system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.00 s
     WAL usage: 65 records, 0 full page images, 8261 bytes
2021-11-28T12:56:18+00:00 database-1.0 2021-11-28 12:56:18 UTC::@:[2535]:LOCATION:  heap_vacuum_rel, vacuumlazy.c:690
```

## Identifying the backend behind a snapshot

To track down which backend is holding things back, find your own PID and
inspect `pg_stat_activity`:

```sql
postgres=# select pg_backend_pid();
 pg_backend_pid 
----------------
           2278
(1 row)

postgres=# \x 
Expanded display is on.
postgres=# select * from pg_stat_activity where pid = pg_backend_pid();
-[ RECORD 1 ]----+-------------------------------------------------------------
datid            | 14231
datname          | postgres
pid              | 2278
leader_pid       | 
usesysid         | 16384
usename          | donghua
application_name | psql
client_addr      | 116.14.204.216
client_hostname  | 
client_port      | 51331
backend_start    | 2021-10-31 13:01:34.664489+00
xact_start       | 2021-10-31 13:05:35.6382+00
query_start      | 2021-10-31 13:05:35.6382+00
state_change     | 2021-10-31 13:05:35.638202+00
wait_event_type  | 
wait_event       | 
state            | active
backend_xid      | 
backend_xmin     | 489
query            | select * from pg_stat_activity where pid = pg_backend_pid();
backend_type     | client backend
```

The key fields for autovacuum troubleshooting are `state` (an `idle in
transaction` backend is the usual culprit), `xact_start` (how long the
transaction has been open), and `backend_xmin` (the snapshot bound this backend
is pinning).

## Takeaways

- `pg_stat_user_tables` (`last_vacuum`, `last_autovacuum`, `n_dead_tup`) is the
  first stop for seeing whether autovacuum is keeping up with dead tuples.
- The autovacuum log lines report `tuples: N removed ... M are dead but not yet
  removable` and the `oldest xmin` bound. When `removed` stays at `0` while the
  not-yet-removable count grows, something is holding back the oldest snapshot.
- A long-running or `idle in transaction` session (especially under `REPEATABLE
  READ`, or any transaction that has an assigned XID) pins `oldest xmin`.
  Autovacuum keeps running and burning I/O but cannot reclaim space until that
  transaction ends.
- The snapshot pin is cluster-wide for XID visibility, but autovacuum
  *scheduling* is per-database — one database can vacuum cleanly while another
  is blocked by the same old snapshot.
- Watch `age(datfrozenxid)` / `age(relfrozenxid)` against
  `autovacuum_freeze_max_age` to gauge distance to an emergency anti-wraparound
  vacuum; the wraparound query reports `percent_towards_wraparound` and
  `percent_towards_emergency_autovac`.
- To fix a stuck situation, identify the offending backend via
  `pg_stat_activity` (look at `state`, `xact_start`, `backend_xmin`) and get
  that transaction committed, rolled back, or terminated.
