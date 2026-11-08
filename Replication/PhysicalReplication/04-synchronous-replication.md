# 04 — Synchronous Replication

Level: L300 → L400. Tested on PostgreSQL 18.6, primary + 1–2 standbys on one machine over
loopback. **Absolute timings are not representative of a real network** — only the ratios and
the behaviours matter.

## What "synchronous" actually changes

By default (`synchronous_standby_names = ''`) a `COMMIT` returns after the **local** WAL flush.
If you name standbys in `synchronous_standby_names`, `COMMIT` additionally waits until
the standby(s) acknowledge the commit record up to a level chosen by `synchronous_commit`.
The primary still writes to the local disk first; the wait is added afterwards.

```
client COMMIT ──► primary WAL flush ──► [send to standby] ──► standby acks ──► client gets OK
                                            ▲ synchronous_commit decides which ack
```

## `synchronous_commit` levels (with a synchronous standby configured)

| Value | Client OK after… | Survives primary crash+loss? | Standby crash? | Readable on standby immediately? |
|---|---|---|---|---|
| `off` | Nothing flushed yet (up to ~3× `wal_writer_delay` data loss on crash; never corrupts) | No | — | No |
| `local` | Local WAL flush only; **ignores** standbys | No (if primary disk lost) | — | No |
| `remote_write` | Standby has **received and written** (OS cache) | Yes, unless both OS crash | Might lose in the standby OS cache | No |
| `on` (default) | Standby has **flushed (fsynced)** the WAL | **Yes** | Yes | No (not yet replayed) |
| `remote_apply` | Standby has **replayed** it | Yes | Yes | **Yes — read-your-writes on the standby** |

(`synchronous_commit` can be set per session/transaction/role — e.g. `SET LOCAL synchronous_commit = off` for
non-critical writes.)

### Measured (single client, one INSERT per transaction, `pgbench -c1 -T3`, loopback)

| `synchronous_commit` | latency avg | tps |
|---|---|---|
| `off` | 0.55 ms | 1805 |
| `local` | 0.49 ms | 2031 |
| `remote_write` | 1.65 ms | 607 |
| `on` | 2.12 ms | 472 |
| `remote_apply` | 3.29 ms | 304 |

Order of magnitude: each added step costs more (a network round trip for `remote_write`, a standby
`fsync` for `on`, replay for `remote_apply`). `off` and `local` are noise-level apart (single run, same
box). On a real network the round-trip time (RTT) dominates: **per-commit latency ≥ RTT + standby fsync**, so
a single-session loop of tiny commits drops to ~1/RTT commits per second; throughput scales with
concurrency (group commit amortises the wait).

## Choosing which standbys are synchronous

```
synchronous_standby_names = 'standby_a'                        -- one named standby (= FIRST 1)
synchronous_standby_names = 'FIRST 2 (a, b, c)'                -- priority: first 2 connected in list order are sync
synchronous_standby_names = 'ANY 1 (a, b, c)'                  -- quorum: any 1 of them is enough
synchronous_standby_names = '*'                                -- any (not recommended: unpredictable)
```

Names match the standby's `application_name` (set in its `primary_conninfo`).

### Tested (two standbys, `a` and `b`)

| Setting | State of standbys | Result |
|---|---|---|
| `FIRST 1 (a, b)` | both up | `a` = `sync` (priority 1), `b` = `potential` (priority 2); commit OK |
| same | `b` stopped | `a` still sync; commit OK |
| same | `a` stopped, `b` up | `b` **promoted to `sync`**; commit OK (once `a` is gone, the next in the list takes over) |
| `ANY 1 (a, b)` | `a` down, `b` up | `b` shown as `quorum`; commit OK |
| `ANY 2 (a, b)` | only `b` up | **commit blocked** (psql timed out at 5 s) |

`sync_state` meanings in `pg_stat_replication`: `sync` (currently counted for FIRST), `potential` (will take over),
`quorum` (member of an ANY set), `async`.

## The availability trap: no sync standby ⇒ writes stop

Single synchronous standby `standby_a`; I killed it and tried an `INSERT`:

```
 state  | wait_event_type | wait_event |               q
 active | IPC             | SyncRep    | insert into t(v) values (999)
```

- The committing backend waits forever in `wait_event = SyncRep`.
- The row is **not visible** to other sessions yet (`count(*)` → 0): the transaction is
  already committed locally in WAL but the commit is not "released" until acked.
- Every other writer piles up behind it too (all commits wait).
- Recovery: bring the standby back, or remove it from `synchronous_standby_names` and reload —
  the waiting commit completed immediately and the row became visible (`count` → 1).

If you cancel the wait (`Ctrl-C`/`pg_cancel_backend`), PostgreSQL warns that the transaction **was already committed
locally** and may not be on the standby (documented behaviour; not run here). Terminating the session does the same.

Design implications:

| Goal | Configuration |
|---|---|
| Zero data loss with one standby, willing to lose write availability when it is down | `FIRST 1 (a)` / default `on` |
| Zero data loss **and** survive one standby failure | **Two or more** candidate standbys: `ANY 1 (a, b)` or `FIRST 1 (a, b)` — requires ≥2 standbys, ideally 3 with `ANY 2 (a, b, c)` for safe automated failover |
| Keep writes available automatically, accept a small data-loss window | Async (default), or an HA manager that downgrades to async on standby loss (Patroni's `synchronous_mode`) |
| Low latency for most writes, strong guarantee for some | Async by default; `SET LOCAL synchronous_commit = on` only for critical transactions (needs sync names set) |

### Quorum arithmetic for safe failover

With `ANY k (n standbys)`, any acknowledged commit exists on ≥ k standbys. To promote without losing acknowledged
commits you must be able to reach at least `n − k + 1` standbys and promote the **most advanced** of them
(compare `pg_last_wal_receive_lsn()`). Example: `ANY 1 (a, b)` — if you can contact only `a`, you can't prove `a` has everything
(the commit may have gone to `b` alone); with `ANY 2 (a, b, c)` reaching any 2 is enough. Many HA tools implement this.

## Sync and the rest of the system

- `synchronous_commit` affects **only transactions that write WAL**; read-only queries are unaffected.
- Sync replication does not make the standby consistent with queries — only `remote_apply` does; with
  `on` you may query the standby and not yet see a transaction you just committed.
- Logical consumers can also be in `synchronous_standby_names` (their `application_name`) — same blocking behaviour.
- DDL, `VACUUM`, checkpoints etc. also wait for `COMMIT` records (though VACUUM itself doesn't).
- Two-phase commit: `PREPARE TRANSACTION` and `COMMIT PREPARED` each wait for the sync standby.
- Large transactions: only the final `COMMIT` waits, not each statement.
- Startup: with sync names set but no standby connected, **even `CREATE ROLE` blocks** — I hit this while building
  the lab (the setup script hung until I enabled sync names *after* the standby connected).

## Monitoring checklist

```sql
-- who is sync and how far behind
SELECT application_name, sync_state, sync_priority,
       pg_wal_lsn_diff(pg_current_wal_lsn(), flush_lsn)  AS flush_lag_bytes,
       write_lag, flush_lag, replay_lag
FROM pg_stat_replication ORDER BY sync_priority;

-- writers currently blocked on the standby
SELECT pid, state, left(query, 60) FROM pg_stat_activity WHERE wait_event = 'SyncRep';
```

Alert on: `count(wait_event='SyncRep') > 0` for more than a few seconds; no row with `sync_state IN ('sync','quorum')`.

## Recommended defaults

1. Start async; measure the lag you actually have ([06](06-monitoring-and-lag.md)).
2. If RPO = 0 is a requirement: ≥ 2 standbys, `ANY 1` or `FIRST 1` with 2+ names, `synchronous_commit = on`.
3. Put synchronous standbys **close** (same region/low RTT; cross-region sync usually costs too much).
4. Use `remote_apply` only where read-your-writes on the standby is a real requirement.
5. Test the "last sync standby dies" scenario in staging and decide the policy up front.
