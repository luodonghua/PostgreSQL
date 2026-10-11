# Replication Lag & Query Conflicts on an RDS Read Replica

A hands-on experiment showing how `hot_standby_feedback` and
`max_standby_streaming_delay` affect two competing goals on a hot-standby /
read replica:

1. **Letting long read queries finish** on the replica, versus
2. **Keeping replication lag low** so the replica stays current.

These two goals are in tension: a long-running read on the replica can conflict
with WAL replay (the primary vacuumed away row versions the query still needs),
and PostgreSQL must either **cancel the query** or **pause replay** (increasing
lag). The two parameters decide which.

> Captured on Amazon RDS for PostgreSQL (PG 10-era). LSNs/timestamps are from the
> original run and shortened here for readability.

## The parameters

```sql
SELECT name, setting FROM pg_settings
WHERE name IN ('max_standby_streaming_delay','hot_standby_feedback');
```

| Parameter | Meaning |
|---|---|
| `max_standby_streaming_delay` | Max delay (ms) the standby will **pause WAL replay** to let a conflicting query finish before it cancels the query. `-1` = wait forever (never cancel). |
| `max_standby_archive_delay` | Same idea, but while replaying **archived** WAL. |
| `hot_standby_feedback` | When `on`, the standby tells the primary which old row versions its running queries still need, so the primary's vacuum won't remove them — preventing the conflict at the source. |

## The data and workload

A one-row table on the primary, updated in a tight loop to continuously advance
the WAL (LSN) so the replica always has something to replay:

```sql
CREATE TABLE t1 (id int);
INSERT INTO t1 VALUES (1);

-- continuously advance the LSN on the primary
DO $$
DECLARE i bigint;
BEGIN
  FOR i IN 1..100000000 LOOP
     UPDATE t1 SET id = i;
     COMMIT;
  END LOOP;
END;
$$;
```

On the replica, a long read is simulated with a repeatable-read transaction that
reads `t1` repeatedly over several seconds.

## Experiment 1 — defaults: `hot_standby_feedback=off`, `max_standby_streaming_delay=30000`

```sql
-- hot_standby_feedback        | off
-- max_standby_streaming_delay | 30000   (30 s)
```

On the **read replica**, hold a repeatable-read snapshot and keep reading:

```sql
BEGIN TRANSACTION;
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SELECT * FROM t1;   -- id = 299543
SELECT * FROM t1;   -- id = 299543  (snapshot held)
SELECT * FROM t1;   -- id = 299543
SELECT * FROM t1;   -- after ~30 s of blocked replay:
```

```text
FATAL:  terminating connection due to conflict with recovery
DETAIL:  User query might have needed to see row versions that must be removed.
HINT:  In a moment you should be able to reconnect to the database and repeat your command.
```

**Result:** the standby paused replay up to `max_standby_streaming_delay` (30 s),
then **cancelled/terminated** the query to resume replay. During the stall, lag
on the primary spiked, then dropped back to ~0 once the query was cancelled:

```text
-- pg_stat_replication on the primary, mid-conflict
replay_lag       | 00:00:17.262337

-- after the replica query was cancelled
replay_lag       | 00:00:00.000677
```

**Trade-off:** replica stays current, but long reads get killed.

## Experiment 2 — `hot_standby_feedback=on`, `max_standby_streaming_delay=30000`

```sql
-- hot_standby_feedback        | on
-- max_standby_streaming_delay | 30000
```

Same long read on the replica — this time it **completes** (five reads, then
`COMMIT`, all returning the same snapshot value `845974`) with no cancellation.
Because the replica fed its xmin back to the primary, the primary's vacuum kept
the needed row versions, so there was no conflict and lag stayed near zero:

```text
-- pg_stat_replication on the primary
backend_xmin     | 846573        <-- primary now holds back vacuum for the replica
replay_lag       | 00:00:00.000646
```

**Trade-off:** long reads succeed and lag stays low — but the primary now retains
dead tuples longer (bloat risk) because vacuum is held back by the replica's
oldest query.

## Experiment 3 — `hot_standby_feedback=on`, `max_standby_streaming_delay=-1`

```sql
-- hot_standby_feedback        | on
-- max_standby_streaming_delay | -1   (never cancel queries)
```

The replica query again runs to completion over ~1 minute (snapshot `1204392`
held across reads spaced seconds apart). With feedback on there's no conflict to
begin with, and `-1` guarantees replay would wait indefinitely rather than cancel.

## Experiment 4 — two replicas with different feedback settings

- Primary + **first replica**: `hot_standby_feedback=on`, `max_standby_streaming_delay=-1`
- **Second replica**: `hot_standby_feedback=off`, `max_standby_streaming_delay=-1`

Long reads were started on both replicas while the primary generated workload.
Observed on the primary via `pg_stat_replication` (two `walreceiver` records,
one per replica):

- With `max_standby_streaming_delay=-1` on both, neither query was cancelled.
- When a replica with `hot_standby_feedback=off` held a long snapshot, its
  `replay_lag` grew (replay paused to protect the query) — e.g.
  `replay_lag | 00:05:25.417925` — and only recovered after that replica's
  transaction committed. The feedback-on replica kept `replay_lag` near zero.

This shows `hot_standby_feedback` is **per-replica**: a replica that doesn't send
feedback trades lag (paused replay) to keep its own queries alive under `-1`,
while a feedback-on replica avoids the conflict entirely at the cost of primary
bloat.

## Monitoring replication lag

On the **primary**, lag per connected standby:

```sql
SELECT * FROM pg_stat_replication;
-- key columns: state, sent_lsn, replay_lsn, write_lag, flush_lag, replay_lag, backend_xmin
```

On the **standby / read replica**:

```sql
SELECT * FROM pg_stat_wal_receiver;

SELECT pg_last_wal_receive_lsn(),
       pg_last_wal_replay_lsn(),
       pg_last_xact_replay_timestamp();
```

Lag in seconds, refreshed every second with `psql \watch`:

```sql
SELECT extract(epoch FROM now() - pg_last_xact_replay_timestamp()) AS replica_lag;
\watch 1

SELECT last_msg_receipt_time,
       pg_last_xact_replay_timestamp(),
       extract(epoch FROM now() - pg_last_xact_replay_timestamp()) AS replica_lag
FROM pg_stat_wal_receiver;
\watch 1
```

## Takeaways

| Setting | Long reads on replica | Replication lag | Primary bloat |
|---|---|---|---|
| `hot_standby_feedback=off`, delay = 30 s | **cancelled** after 30 s | low | none |
| `hot_standby_feedback=off`, delay = `-1` | survive | **grows** while query runs | none |
| `hot_standby_feedback=on`, delay = 30 s / `-1` | survive | low | **grows** (vacuum held back) |

- Use `hot_standby_feedback=on` when the replica runs important long analytic queries and you can tolerate some extra dead-tuple retention on the primary.
- Keep it `off` (and rely on a bounded `max_standby_streaming_delay`) when protecting the primary from bloat and keeping lag low matters more than any single replica query.
- `max_standby_streaming_delay=-1` removes query cancellation but lets lag grow without bound on a feedback-off replica — monitor lag closely if you use it.
