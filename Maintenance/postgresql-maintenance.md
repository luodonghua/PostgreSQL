# PostgreSQL Maintenance

Routine maintenance keeps a PostgreSQL server healthy: reclaiming dead space,
keeping planner statistics current, preventing transaction-ID wraparound, and
rebuilding bloated indexes. This document walks through the common maintenance
tasks — measuring bloat, `VACUUM`/`ANALYZE`/`VACUUM FULL`, autovacuum tuning,
`pg_repack`, and online index rebuilds — with real captured output and notes on
why and when to run each.

All examples were run against a `pgbench`-generated schema (`pgbench_accounts`,
`pgbench_branches`, `pgbench_tellers`, `pgbench_history`).

## Measuring bloat with pgstattuple

The `pgstattuple` extension reports how much of a table is live tuples, dead
tuples, and free space — the raw material for a bloat assessment.

```sql
create extension pgstattuple;

select * from pgstattuple_approx('pgbench_accounts');
```

`pgstattuple_approx` is cheap: it samples the table and skips pages already
known (via the visibility map) to contain only live tuples, so `scanned_percent`
can be `0`. For a precise calculation, call `pgstattuple('pgbench_accounts')`
instead. That function examines every row in the entire table — it is resource
intensive and will temporarily affect performance.

```sql
-- For a precise calculation of bloat, call pgstattuple('pgbench_accounts').
-- This function examines every row in the entire table.
-- This is resource intensive and will temporarily affect performance.
select * from pgstattuple('pgbench_accounts');
```

Enabling `\x auto` makes `psql` switch to expanded (record) display when a row
is too wide, and `\timing` reports execution time:

```text
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
```

Here `dead_tuple_percent` is effectively zero and `free_percent` is only ~1.4%,
so this table is not bloated. The precise `pgstattuple` scan took 340 ms on a
one-million-row table — a reminder to prefer the approximate function on large,
busy tables.

## Monitoring transaction-ID age (wraparound)

Every row carries the transaction ID (xid) that created it. Because xids are a
finite 32-bit space, PostgreSQL must periodically "freeze" old rows. If xid
exhaustion is ever reached, the database will be forced to shut down. The same
applies to multixact IDs. The rule of thumb is to watch for wraparound around
200 million transactions.

The `age(relfrozenxid)` of a table tells you how many transactions have elapsed
since its oldest unfrozen row:

```sql
select relname, age(relfrozenxid) as xid_age
  from pg_class c, pg_namespace n
 where c.relnamespace = n.oid
   and n.nspname = 'public'
   and relkind = 'r';
```

```text
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
```

These ages are tiny — the tables were just created. To observe xid wraparound
and the vacuum/freeze effects in a lab, you can set the thresholds that trigger
anti-wraparound autovacuum:

```text
autovacuum_freeze_max_age = 200000000
autovacuum_multixact_freeze_max_age = 400000000
```

## VACUUM, ANALYZE, and FREEZE

The `VACUUM` command marks dead space left in tables and indexes as available
for reuse. Note that running `VACUUM` does not reclaim disk space back to the
operating system. Disk space can be reclaimed with some offline options — two of
these are the `VACUUM FULL` command and the `pg_repack` extension.

The common variants:

```sql
-- Basic command to vacuum a table
vacuum pgbench_accounts;

-- Vacuum + statistical analysis
vacuum analyze pgbench_accounts;

-- Vacuum + statistical analysis + freeze and reset xmin
vacuum freeze analyze pgbench_accounts;
```

`VACUUM FREEZE` aggressively freezes all eligible tuples, which resets their xid
to the special frozen value and lowers the table's `relfrozenxid` age. Adding
`VERBOSE` prints progress:

```sql
vacuum freeze verbose analyze pgbench_accounts;
```

```text
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
```

Read the `VERBOSE` output as: how many removable vs. nonremovable row versions
were found, the `oldest xmin` that pins dead rows (rows newer than this cannot
be removed yet), how many pages were already frozen or skipped, and the
`ANALYZE` sample size (`30000 rows in sample`) used to refresh statistics.

A plain `VACUUM ANALYZE VERBOSE` looks almost identical, minus the aggressive
freeze messaging:

```sql
vacuum analyze verbose pgbench_accounts;
```

```text
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
```

## VACUUM FULL to reclaim disk space

`VACUUM FULL` actively compacts tables by writing a completely new version of
the table with no dead space. This minimizes the size of the table but can take
a long time. It also requires extra disk space for the new copy of the table
until the operation is complete, and it holds an exclusive lock on the table for
the duration.

To demonstrate, delete half the rows first and then compact:

```sql
vacuum full verbose analyze pgbench_accounts;
```

```text
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
```

After deleting 500,000 rows, `VACUUM FULL` found 500,000 removable row versions
and rewrote the table down from 16,394 pages to 8,197 — the physical size was
halved and the freed space returned to the filesystem.

## Autovacuum settings

Autovacuum runs `VACUUM` and `ANALYZE` automatically in the background. Its
behavior is governed by a family of parameters that you can inspect via
`pg_settings`:

```sql
select name,setting,short_desc from pg_settings where name like '%autovacuum%';
```

Note the units differ between parameters: `autovacuum_naptime` is measured in
seconds, while `log_autovacuum_min_duration` is measured in milliseconds.

```text
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
```

The scale factors and thresholds decide when a table is vacuumed or analyzed:
roughly, when dead/changed tuples exceed `threshold + scale_factor * reltuples`.
The `*_freeze_max_age` values force an anti-wraparound vacuum regardless of
activity. The `rds.force_autovacuum_logging_level` entry is Amazon RDS specific.

To see when each table was last (auto)analyzed:

```sql
select relname, last_analyze, last_autoanalyze from pg_stat_user_tables;
```

```text
mytest=> select relname, last_analyze, last_autoanalyze from pg_stat_user_tables;
     relname      |         last_analyze          |       last_autoanalyze        
------------------+-------------------------------+-------------------------------
 pgbench_branches | 2021-10-31 03:50:54.714567+00 | 
 pgbench_accounts | 2021-10-31 05:31:17.832021+00 | 
 pgbench_history  | 2021-10-31 03:50:56.206317+00 | 2021-10-31 06:01:03.699672+00
 pgbench_tellers  | 2021-10-31 03:50:54.947703+00 | 
(4 rows)
```

`last_analyze` reflects manual `ANALYZE` runs; `last_autoanalyze` reflects
autovacuum-driven ones. Only `pgbench_history` has been auto-analyzed so far,
because it is the table receiving ongoing changes.

## Removing bloat online with pg_repack

The `pg_repack` extension removes bloat from tables and indexes. You can also
opt to restore the physical order of clustered indexes. Unlike `CLUSTER` and
`VACUUM FULL`, `pg_repack` works online, without maintaining an exclusive lock
on the processed tables during implementation.

```bash
pg_repack -k -t pgbench_accounts -h postgres-instance1.c5pjidu07yp7.us-east-1.rds.amazonaws.com -U postgres -d mytest
```

The `-k` flag skips the superuser check (useful on managed services like RDS
where you connect as a privileged-but-not-superuser account), `-t` names the
table, and `-h/-U/-d` are the usual connection options.

## Rebuilding indexes with minimal locking

To avoid locking the index's parent table while rebuilding an index, an
alternative is to create a new index concurrently and then drop the old one.
PostgreSQL supports rebuilding indexes with minimum locking of writes; this is
also invoked via the `CONCURRENTLY` option of `REINDEX`.

### Replacing a primary-key index

First build a replacement unique index concurrently:

```sql
create unique index concurrently pgbench_accounts_pkey_new on pgbench_accounts(aid);
```

Inspect the constraint and its backing index:

```sql
select c.conname, t.relname as indexname, ts.spcname as tablespace, pg_get_indexdef(i.indexrelid) as indexdef
from pg_constraint c join pg_index i on c.conindid = i.indexrelid 
    join pg_class t on  t.oid=i.indexrelid 
    left join pg_tablespace ts on ts.oid =t.reltablespace
where conrelid='pgbench_accounts'::regclass;
```

Then swap the constraint to use the new index in a single transaction. The
drop/add of the constraint is only required because the index backs a primary
key constraint:

```sql
begin;
-- drop/add constraint only required as the index supports the constraint
alter table pgbench_accounts drop constraint pgbench_accounts_pkey,
    add constraint pgbench_accounts_pkey primary key using index pgbench_accounts_pkey_new;
commit;
```

```text
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
...

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
```

Note the `NOTICE`: when you attach the new index to the primary-key constraint,
PostgreSQL automatically renames `pgbench_accounts_pkey_new` back to
`pgbench_accounts_pkey`, so the final name is unchanged.

### Replacing an ordinary (non-PK) index

For a plain secondary index there is no constraint to juggle — just build the
new index concurrently and rename it over the old one:

```sql
create index concurrently pgbench_accounts_bid on pgbench_accounts(bid);

-- to replace non-pk index with minimal locking

create index concurrently pgbench_accounts_bid_new on pgbench_accounts(bid);

begin;
drop index pgbench_accounts_bid;
alter index pgbench_accounts_bid_new rename to pgbench_accounts_bid;
commit;
```

## Finding unused indexes

Indexes that are never used cost write throughput and disk space for no benefit.
`pg_stat_user_indexes` tracks scan counts; an `idx_scan` of `0` flags a
candidate for removal (after confirming the workload has run long enough to be
representative):

```sql
select relname, indexrelid, idx_scan from pg_stat_user_indexes where idx_scan = 0;
```

```text
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
```

Resolve the `indexrelid` to a name via `pg_class` (here OID `16433` is
`pgbench_branches_pkey`). Be cautious: a primary-key or unique index may show
zero scans yet still be required for correctness, so never drop an index purely
on the scan count without understanding its role.

## Takeaways

- Use `pgstattuple_approx` for a cheap bloat estimate; reserve the exact
  `pgstattuple` for when precision justifies a full-table scan.
- Plain `VACUUM` reuses dead space but does not return disk to the OS;
  `VACUUM FULL` and `pg_repack` reclaim it — `VACUUM FULL` locks the table,
  `pg_repack` works online.
- `ANALYZE` keeps planner statistics fresh; `FREEZE` resets row xids to defend
  against transaction-ID wraparound (watch `age(relfrozenxid)` toward 200M).
- Read `VACUUM VERBOSE` output for removable vs. nonremovable rows, `oldest
  xmin`, frozen/skipped pages, and the analyze sample size.
- Tune autovacuum via thresholds and scale factors; mind that `naptime` is in
  seconds while `log_autovacuum_min_duration` is in milliseconds.
- Rebuild indexes with `CREATE INDEX CONCURRENTLY` + swap (or `REINDEX
  CONCURRENTLY`) to minimize write locking; swapping a PK index auto-renames the
  new index to the old name.
- Use `pg_stat_user_indexes` to spot `idx_scan = 0` indexes, but confirm an
  index isn't backing a constraint before dropping it.
