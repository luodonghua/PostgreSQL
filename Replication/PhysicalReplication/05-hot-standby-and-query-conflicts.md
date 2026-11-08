# 05 — Hot Standby and Recovery Conflicts

Level: L300. Tested on PostgreSQL 18.6 (all four experiments below). Related note in this
repo for managed services: [RDS replication lag on a read replica](../../RDS-PostgreSQL/replication-lag-on-read-replica.md).

## The tension

A hot standby does two things at once: **replays** WAL from the primary (the primary has
already decided "this old row version can be removed", "this table can be dropped", "this lock
is taken") and **serves read queries** that may still need exactly those row versions or locks.
Both cannot always win. PostgreSQL resolves it with a choice per standby:

- **let queries finish, delay replay** (replication lag grows), or
- **cancel the queries after a grace period** (standby stays fresh).

The grace period is `max_standby_streaming_delay` (default 30 s).

## Conflict types

| Conflict | Caused by (on primary) | Error text on the standby | Counter |
|---|---|---|---|
| **Snapshot** | `VACUUM`/pruning removed row versions the standby query's snapshot can still see | `canceling statement due to conflict with recovery` / `User query might have needed to see row versions that must be removed.` | `confl_snapshot` |
| **Lock** | `ACCESS EXCLUSIVE` lock replayed (`ALTER TABLE`, `DROP`, `TRUNCATE`, `VACUUM` truncation, `LOCK`) | `…` / `User was holding a relation lock for too long.` | `confl_lock` |
| **Buffer pin** | VACUUM needs a buffer that a standby query has pinned | `User was holding shared buffer pin for too long.` | `confl_bufferpin` |
| **Deadlock** | Standby query would deadlock with replay | `User transaction caused buffer deadlock with recovery.` | `confl_deadlock` |
| **Tablespace** | `DROP TABLESPACE` while queries use it | `User was or might have been using tablespace that must be dropped.` | `confl_tablespace` |
| **Database** | `DROP DATABASE` replayed | session terminated | (connection error) |
| **Logical slot** (standby slots) | needed catalog rows removed | slot invalidated | `confl_active_logicalslot` |

`pg_stat_database_conflicts` (standby only) counts **cancelled queries**, per type. Only the snapshot and lock rows
were reproduced below; the buffer-pin, deadlock, tablespace and database texts are from the PostgreSQL documentation. Bursts in the log: set
`log_recovery_conflict_waits = on` to log the wait if replay was blocked longer than `deadlock_timeout`.

## Experiments (18.6)

Setup: `t(id, v)`, 100 000 rows; standby `max_standby_streaming_delay = 2s`. Standby query:
`SELECT count(*), pg_sleep(8) FROM t` (a long snapshot). Primary: `UPDATE` half the rows, then `VACUUM t`.

### 1. Defaults (feedback off): the query is killed

```
ERROR:  canceling statement due to conflict with recovery
DETAIL:  User query might have needed to see row versions that must be removed.
```

`pg_stat_database_conflicts`: `confl_snapshot = 1`, others 0. The cancellation arrives ~2 s (the delay)
after replay reached the vacuum's cleanup record.

### 2. `hot_standby_feedback = on`: the query survives, the primary pays

Same workload; the standby query returned `100000` with no error. The standby told the primary
its oldest snapshot (`xmin`), so the primary's `VACUUM` kept the old row versions.

Cost: while a long query runs on the standby, **primary vacuum cannot clean** dead tuples newer than that
xmin ⇒ bloat on the primary. A forgotten `idle in transaction` session on the standby has the same effect as one on the primary.

### 3. `max_standby_streaming_delay = -1` (wait forever), feedback off: replay stops instead

Replay stopped at the conflicting record until the query finished:

```
while query runs: replay lag = 582 776 bytes, row inserted afterwards on the primary visible on standby? 0
after the query:  visible? 1
```

So with `-1` a single long query can delay replay indefinitely — fine for an offline reporting
standby, dangerous for one you intend to fail over to (failover must replay the backlog first).

### 4. Lock conflict from DDL

Primary: `ALTER TABLE t ADD COLUMN z int` while a standby query was running (delay 2 s):

```
ERROR:  canceling statement due to conflict with recovery
DETAIL:  User was holding a relation lock for too long.
```

`confl_lock = 1`. **Feedback does not help against lock conflicts** — `hot_standby_feedback` only prevents snapshot conflicts.
(An earlier attempt to provoke a lock conflict with `DELETE` + `VACUUM` truncation produced a *snapshot* conflict instead
because the cleanup record is replayed first — a reminder that you often see several conflict types together.)

## Knobs

| Setting | Default | Effect |
|---|---|---|
| `max_standby_streaming_delay` | 30 s | Max time replay waits for conflicting queries while **streaming**; `-1` = forever; `0` = cancel immediately |
| `max_standby_archive_delay` | 30 s | Same, while replaying from an **archive** (restore_command) |
| `hot_standby_feedback` | off | Standby reports its xmin so the primary retains row versions; prevents snapshot conflicts, not lock conflicts |
| `wal_receiver_status_interval` | 10 s | How often the standby reports (also its feedback) |
| `hot_standby` | on | Allow queries during recovery |
| `recovery_min_apply_delay` | 0 | Deliberate delay ([08](08-cascading-delayed-archive.md)) |
| `vacuum_defer_cleanup_age` | removed in PG16 | (old workaround) |
| `old_snapshot_threshold` | removed in PG17 | (old workaround) |
| `log_recovery_conflict_waits` | off | Log long waits in replay |

On the application side: cap query duration with `statement_timeout` on the standby role so one query
doesn't hold back vacuum (feedback on) or replay (delay −1).

## Choosing a strategy

| Standby purpose | Suggested settings |
|---|---|
| **HA failover target** (no or light reads) | defaults or small delay; feedback off; reads limited |
| **Read scale-out for OLTP** (short queries) | feedback on, `max_standby_streaming_delay` 30 s–60 s, `statement_timeout` ≤ that; monitor primary bloat |
| **Reporting / analytics, long queries** | **Dedicated** standby (not the failover target): `max_standby_streaming_delay = -1` or very large, feedback off (so the primary is unaffected), accept lag; or feedback on and accept primary bloat |
| **Mixed** | Don't. Separate HA and reporting standbys |

Remember a reporting standby with `-1` still advances the same WAL position as everyone else once the query
ends; check `replay_lag` ([06](06-monitoring-and-lag.md)).

## Diagnosing "queries cancelled on the replica"

1. Error text → table above → which conflict.
2. `SELECT * FROM pg_stat_database_conflicts;` on the standby.
3. For snapshot conflicts: who runs the vacuum? An aggressive autovacuum on a hot table makes more cleanup records.
   Consider `vacuum_truncate = off` for tables where truncation conflicts hurt (it removes the lock-conflict source).
4. For lock conflicts: DDL on the primary (migrations!), `TRUNCATE`, `VACUUM` truncation. Schedule DDL when no long queries
   run on the standby; use `lock_timeout` on the primary.
5. Check the standby for `idle in transaction` sessions when feedback is on.
6. Compare `replay_lag` before/after to decide between "cancel" and "delay" behaviour.

## Interplay with promotion

`max_standby_*_delay` also applies to the replay done during failover catch-up: when you
promote, the standby first replays everything it has already received, still subject to conflict handling.
With `-1` and a long reporting query this can make a promotion slow unless the query is cancelled
(`pg_terminate_backend`). This follows from how the startup process works; I did not time a promotion under this condition.
Put a `statement_timeout` on HA standbys regardless.
