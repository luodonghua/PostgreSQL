# 11 — Apply Workers and Parallel Apply

Level: L300. Tested on PostgreSQL 18.6. Source: `replication/logical/worker.c`,
`applyparallelworker.c` (the design comments are the basis for the locking and
pool notes), `launcher.c`.

## One subscription = one serial applier

Each enabled subscription has exactly one **apply worker** (leader). It reads
the stream, and for each remote transaction opens a local transaction, executes
each change through the normal executor machinery (index maintenance,
constraints, triggers marked as replica triggers), and commits in the same
order as the publisher.

Consequences that drive tuning:

- **Throughput is bounded by one process.** The publisher might commit 20 000
  small transactions/s from many backends; the subscriber replays them with a
  single backend. When it falls behind, lag grows without bound.
- **Commit order is preserved**, so a slow transaction delays everything behind it.
- Apply speed is that of the *subscriber's* write path: indexes, triggers,
  `synchronous_commit` (default `off` for the worker), I/O.
- Applying is **not** WAL replay. It's logical, row-at-a-time through
  the executor: usually several times more expensive per change than physical
  replay.

## Scaling levers, in order of effectiveness

| # | Lever | How | Trade-off |
|---|---|---|---|
| 1 | **Split into several subscriptions** | Put disjoint tables in separate publications/subscriptions | Loses atomic visibility across the groups; FKs between groups can transiently fail |
| 2 | **Fix the subscriber's write path** | Remove unneeded indexes/triggers; keep the replica-identity index; `FULL` ⇒ add an index ([topic 09](09-replica-identity.md)) | Subscriber-only indexes slow everything |
| 3 | **`streaming = parallel`** | For large transactions only (below) | Needs worker slots; deadlock-handling corner |
| 4 | Batch smaller transactions on the publisher | Group many tiny transactions into fewer large ones | Larger lag spikes |
| 5 | Faster subscriber storage / `synchronous_commit` (already `off`) / bigger shared_buffers | Standard tuning | |

## Parallel apply: what it does and doesn't do

Introduced in PG 16 as `streaming = parallel`; the **default from PG 18**
(tested: a plain `CREATE SUBSCRIPTION` stored `substream = 'p'`).

- It only parallelises **large, streamed in-progress transactions**
  ([topic 07](07-reorderbuffer-and-large-transactions.md)). Ordinary
  small transactions arrive complete and are applied by the leader, serially.
- The leader hands the transaction's stream chunks to a **parallel apply
  worker** over shared memory as they arrive, so by the time `COMMIT` shows up,
  almost everything is already applied.
- Commit order is still enforced: the leader waits for the worker to finish
  before moving on.
- If no worker is free, the leader falls back to spooling the stream to a
  file (exactly like `streaming = on`).

### Measured: time from COMMIT until the subscriber sees the rows

Transaction: 400 000 rows (~130 MB), held open 12 s after the inserts so streaming
modes could ship in advance. `logical_decoding_work_mem = 1MB`. Time from the
client sending `COMMIT` until all 400 000 rows were visible on the subscriber.
One run each, 18.6, single machine:

| `streaming` | Visible after COMMIT | Why |
|---|---|---|
| `off` | **10.7 s** | Spilled on the publisher; sent at commit; applied serially afterwards |
| `on` | 10.0 s | Shipped early but staged in files on the subscriber; applied at commit |
| `parallel` | **0.25 s** | Applied as it streamed; commit just finishes |

The gain is for *commit visibility latency* of big transactions. Total CPU
work is the same; it just moved off the critical path.

### How to see the workers

```sql
-- subscriber
SELECT subname, pid, leader_pid, worker_type FROM pg_stat_subscription ORDER BY pid;
 subname | pid | leader_pid |  worker_type
---------+-----+------------+----------------
 s       |  72 |            | apply
 s       |  81 |         72 | parallel apply

SELECT pid, leader_pid, backend_type FROM pg_stat_activity WHERE backend_type LIKE 'logical%';
  60 |    | logical replication launcher
  72 |    | logical replication apply worker
  81 | 72 | logical replication parallel worker
```

`worker_type` values: `apply`, `parallel apply`, `table synchronization`.
`pg_stat_subscription` reports one row per worker, with LSNs and timestamps:

| Column | Meaning |
|---|---|
| `received_lsn` | last WAL position received from the publisher |
| `last_msg_send_time` / `last_msg_receipt_time` | publisher send / local receipt times of the last message (their difference ≈ network + queue) |
| `latest_end_lsn` / `latest_end_time` | last position reported **back** to the publisher |

`received_lsn` far ahead of `latest_end_lsn` means the worker is receiving but
not finished applying.

`pg_stat_subscription_stats` has error and conflict counters (18.6 columns):
`apply_error_count`, `sync_error_count`, `confl_insert_exists`,
`confl_update_origin_differs`, `confl_update_exists`, `confl_update_missing`,
`confl_delete_origin_differs`, `confl_delete_missing`,
`confl_multiple_unique_conflicts`, `stats_reset`.

## Worker budget (the GUCs)

All on the **subscriber** (except where noted):

| GUC | Default | Context | Role |
|---|---|---|---|
| `max_logical_replication_workers` | 4 | restart | Pool for apply + tablesync + parallel apply workers on the subscriber |
| `max_sync_workers_per_subscription` | 2 | reload | Concurrent tablesync workers per subscription |
| `max_parallel_apply_workers_per_subscription` | 2 | reload | Parallel apply workers per subscription |
| `max_worker_processes` | 8 | restart | Hard ceiling for all background workers; must exceed the sum of everything using it (parallel query, autovacuum launcher/workers' separate, replication) |
| `wal_retrieve_retry_interval` | 5 s | reload | Delay before restarting a failed worker |
| `wal_receiver_timeout` | 60 s | user-settable (and per-subscription in ⚠️ 19) | Subscriber-side keepalive timeout |

Budget formula:

```
max_logical_replication_workers ≥
    Σ over subscriptions [ 1 apply + (sync workers during initial copy) + (parallel apply workers) ]
```

With the defaults (4), a single subscription using 2 sync workers + 1 apply
already leaves one for parallel apply. **A second subscription's apply worker
may fail to start** with: `WARNING: out of logical replication worker slots`
and `HINT: You might need to increase "max_logical_replication_workers".`
Raise it (restart needed) *and* `max_worker_processes`.

Pool behaviour (source): parallel apply workers are kept in a pool for reuse,
retaining at most **half** of `max_parallel_apply_workers_per_subscription`;
extra ones exit after their transaction.

## Locking and deadlocks (L400)

Independent transactions on the publisher can become dependent on the
subscriber when the subscriber's schema differs — e.g. no unique key on the
publisher but a unique index on the subscriber. In parallel mode that can
create wait cycles that are invisible to the normal deadlock detector (leader
waiting for a worker, worker waiting for the next chunk from the leader).

PostgreSQL handles it by having the leader and workers take **session-level
heavyweight locks on the remote transaction** at well-defined points, turning
the cycle into an ordinary, detectable lock-graph cycle; one participant is
then aborted. You would see `ERROR:  deadlock detected` in the subscriber log
(I did not reproduce a deadlock in testing; this is from the design comments
in `applyparallelworker.c`). A third case — the
shared-memory queue between leader and worker being full — is handled
separately in code.

Practical rules:

- Keep subscriber constraints **identical** to the publisher's unless you have a reason.
- Do not add unique indexes on the subscriber that don't exist on the
  publisher if you use parallel apply.
- Treat repeated deadlock errors as a signal to set `streaming = on` for that
  subscription (`ALTER SUBSCRIPTION s SET (streaming = on)`).

## Restart, retries and progress tracking

- The worker commits its local transaction together with an **origin
  progress update** (`pg_replication_origin_status.remote_lsn`) — atomic with
  the data. After a crash it resumes from there; nothing is applied twice.
- On an error, the worker exits and the launcher restarts it after
  `wal_retrieve_retry_interval`. `disable_on_error = true` stops this loop
  after the first failure.
- Stuck on one transaction: see skip / conflict handling in
  [topic 12](12-conflicts-and-error-handling.md).

## Summary

| Question | Answer |
|---|---|
| Why is my subscriber behind? | One serial applier; check `pg_stat_subscription` for `received_lsn` vs `latest_end_lsn`, and the subscriber's I/O and indexes |
| Will `streaming=parallel` speed up my OLTP stream? | No — only large transactions |
| Biggest easy win? | More subscriptions (disjoint tables) and correct indexes on the subscriber |
| What bites in production? | Worker budget exhaustion, unique-key mismatch deadlocks, `FULL` identity without index |
