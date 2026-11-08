# 15 — Best Practices

Level: L400. A consolidated, opinionated checklist. Each rule points at the topic
where the behaviour was demonstrated on PostgreSQL 18.6. Items that depend on
newer, non-GA releases are marked ⚠️.

## 1. Design

1. **Every published table gets a primary key.** If it cannot, choose
   `REPLICA IDENTITY USING INDEX` on a NOT NULL unique index; use `FULL` only
   as a last resort and add an index on the subscriber
   ([09](09-replica-identity.md): `FULL` doubled WAL in my test; unindexed apply was ~18× slower at 300 updated rows).
2. **Publish explicitly** (`FOR TABLE`, or `FOR TABLES IN SCHEMA`) instead of
   `FOR ALL TABLES`, unless you have a process that creates the target table
   *before* the source table. A new, unmatched table stalls the apply worker
   ([02](02-publications.md), [13](13-limitations.md)).
3. **One writer per row.** Treat the subscriber's replicated tables as read-only
   ([12](12-conflicts-and-error-handling.md)). If you need multi-writer, disjoint key
   ranges + `origin = none` ([17](17-upgrades-and-migrations.md)).
4. **Keep schemas identical** on both sides — same names, compatible types, same
   unique constraints. Subscriber-only unique indexes cause `*_exists` conflicts
   and parallel-apply deadlocks ([11](11-apply-workers-and-parallel-apply.md)).
5. **Group tables that must be consistent together** in one subscription;
   split unrelated high-volume tables into separate subscriptions for parallelism
   ([11](11-apply-workers-and-parallel-apply.md)).
6. Minimise data leaving: column lists and row filters
   ([02](02-publications.md)); make sure the identity columns are included.
7. **Use `streaming = parallel`** (default from 18; earlier set it explicitly) if you
   have large transactions ([07](07-reorderbuffer-and-large-transactions.md): visibility after commit 10.7 s → 0.25 s).
8. Prefer **UUIDs or site-prefixed keys** over independent `serial`s if the
   subscriber may ever take writes.

## 2. Configuration baseline

### Publisher

| Parameter | Suggested | Why |
|---|---|---|
| `wal_level` | `logical` | Required (restart) |
| `max_replication_slots` | (subscriptions × (1 + `max_sync_workers_per_subscription`)) + physical slots + 2 spare | Peak is 1+N slots per subscription during initial sync ([10](10-initial-sync-tablesync.md)) |
| `max_wal_senders` | ≥ `max_replication_slots` + physical standbys + backup tools | One sender per active slot connection |
| `max_slot_wal_keep_size` | **Set it.** E.g. 50–70 % of the WAL volume's free space | Protects the primary's disk from a dead subscriber; costs you the slot when exceeded ([05](05-replication-slots.md)) |
| `idle_replication_slot_timeout` | e.g. `2d` (18+) | Auto-invalidate abandoned slots ([05](05-replication-slots.md)) |
| `logical_decoding_work_mem` | 64 MB default; 128–512 MB if `spill_*` counters grow and memory allows | Per walsender ([07](07-reorderbuffer-and-large-transactions.md)) |
| `wal_sender_timeout` | 60 s default; keep ≥ the longest expected stall of the receiver | Disconnects dead peers |
| `synchronized_standby_slots` | only on HA clusters, standby slots only | ([16](16-failover-and-ha.md)) |
| `max_wal_size`, `checkpoint_timeout` | sized for the extra WAL | `logical` increases WAL |
| `track_commit_timestamp` | `on` if the subscriber might get local writes | Needed for `origin_differs` detection |

### Subscriber

| Parameter | Suggested | Why |
|---|---|---|
| `max_logical_replication_workers` | subscriptions × (1 + sync workers + parallel workers) + spare | Default 4 runs out quickly ([11](11-apply-workers-and-parallel-apply.md)) |
| `max_worker_processes` | > the above + parallel query + autovacuum + extensions | Hard ceiling |
| `max_sync_workers_per_subscription` | 2–4 | Initial copy parallelism |
| `max_parallel_apply_workers_per_subscription` | 2–4 | Large-transaction apply |
| `wal_retrieve_retry_interval` | 5 s default | Retry cadence after errors |
| `track_commit_timestamp` | `on` | Conflict diagnostics ([12](12-conflicts-and-error-handling.md)) |
| `wal_level` | `replica` is enough, `logical` if it will also publish | |

All of these are `postgresql.conf` items; the slot, sender and worker-count ones need a restart.

## 3. Security

1. **Dedicated replication role**: `LOGIN REPLICATION` + `SELECT` on published tables
   only. Not a superuser. `pg_hba.conf` entry restricted to the subscriber's address,
   `hostssl`, `scram-sha-256`, `sslmode=verify-full` in the subscription
   ([04](04-step-by-step-setup-guide.md)).
2. **Passwords out of SQL history**: use a `.pgpass`/passfile in the conninfo, or a
   secret manager. The conninfo is stored in `pg_subscription` (superuser-readable
   only) and may be logged in your statement log.
3. Keep subscription owners non-superuser where possible: membership in
   `pg_create_subscription` + `password_required = true`; leave
   `run_as_owner = false` ([03](03-subscriptions.md)).
4. Publication **column lists and row filters** for data minimisation; but remember they
   filter the replication stream, not direct SQL by the same role.
5. The subscriber has full copies: apply the same at-rest and access controls.
   RLS policies are not replicated; recreate them.
6. Network: private link/VPC peering; do not expose the publisher's port to the internet.

## 4. Operations

### Day-0

- Pre-create objects on the subscriber from `pg_dump --schema-only --no-publications --no-subscriptions --no-privileges --no-owner`
  ([04](04-step-by-step-setup-guide.md)).
- Test the initial sync on a production-sized copy to learn duration, WAL growth,
  `catalog_xmin` impact ([10](10-initial-sync-tablesync.md)).
- Test failover and rebuild procedures before you need them ([16](16-failover-and-ha.md)).

### Day-2

| Change | Procedure |
|---|---|
| Add column | Subscriber first, then publisher ([04](04-step-by-step-setup-guide.md) §9.1) |
| Drop column | Publisher first, after code stops using it |
| Add table | Create on subscriber; `ALTER PUBLICATION … ADD TABLE`; `ALTER SUBSCRIPTION … REFRESH PUBLICATION` (with `two_phase` use `copy_data=false`) |
| Rename / type change | Plan explicitly ([13](13-limitations.md)); pause the subscription |
| Bulk load | Chunk into transactions of ~10⁴–10⁵ rows or use streaming |
| Long maintenance on subscriber (`VACUUM FULL`, `ALTER TABLE`) | Expect apply to block on locks ([14](14-monitoring-and-troubleshooting.md)); schedule or `DISABLE` (and watch WAL) |
| Decommission | `DROP SUBSCRIPTION`; verify no slot left on the publisher ([05](05-replication-slots.md)) |
| Major upgrade | Logical replication or `pg_createsubscriber`/`pg_upgrade` ([17](17-upgrades-and-migrations.md)) |

### Monitoring minimum

Alert on: retained WAL per slot; inactive slots; `wal_status`; byte lag; subscription not
running; `apply_error_count`/`confl_*` rate; tables not `r`; publisher disk
([14](14-monitoring-and-troubleshooting.md)). **Do not alert on lag *time* alone** — it
reported a stale 0.03 s during a real stall.

### Runbooks to write down

1. Slot lost → rebuild a subscription.
2. Poison transaction → fix data / `SKIP` (with approval) ([03](03-subscriptions.md), [12](12-conflicts-and-error-handling.md)).
3. Publisher disk filling → find the slot; drop or repair.
4. Planned publisher failover ([16](16-failover-and-ha.md)); include the
   `synchronized_standby_slots` trap.
5. Sequence synchronisation at cut-over ([13](13-limitations.md)).

## 5. Capacity and performance

- **Estimate WAL growth**: `wal_level=logical` adds old-key data; `REPLICA IDENTITY FULL`
  doubles update WAL. Measure `pg_current_wal_lsn()` deltas before/after.
- The walsender decodes **all** WAL of the database, published or not; a very busy
  unpublished table still costs decoding CPU ([06](06-logical-decoding.md)).
- Subscriber throughput = one worker per subscription; scale by splitting subscriptions
  and by fixing the subscriber's indexes ([11](11-apply-workers-and-parallel-apply.md)).
- Keep subscriber indexes to what is needed; each one slows the single applier.
- Avoid `REPLICA IDENTITY FULL` on wide, hot tables.
- Large initial sync: more sync workers, drop non-essential indexes first, or clone
  physically and use `pg_createsubscriber` ([17](17-upgrades-and-migrations.md)).
- Vacuum/bloat: slot `catalog_xmin` holds back catalog vacuum on the publisher; a stuck slot
  is a bloat problem as well as a disk problem ([05](05-replication-slots.md)).

## 6. Anti-patterns

| Anti-pattern | Consequence |
|---|---|
| Unlimited `max_slot_wal_keep_size` + no slot alerts | Publisher disk full → outage |
| `FOR ALL TABLES` with ad-hoc table creation | Stalled subscription |
| Tables without PK + default identity | Publisher rejects UPDATE/DELETE |
| Letting applications write to subscriber copies | Conflicts, divergence |
| Skipping transactions casually | Permanent, silent divergence |
| Dropping the subscriber database without `DROP SUBSCRIPTION` | Orphan slot pins WAL |
| `ALTER SUBSCRIPTION … DISABLE` and forgetting | Slot accumulates WAL |
| Using a replication user = superuser | Larger blast radius |
| Relying on the subscriber for a consistent snapshot of multiple subscriptions | Cross-stream skew |
| Testing only the happy path | Surprise at the first failover/DDL |
| `pg_basebackup -R` standby with wrong `PGDATABASE`, or inherited `synchronized_standby_slots` | Slots never sync / promoted node stalls logical consumers ([16](16-failover-and-ha.md)) |

## 7. Pre-production checklist

- [ ] All tables: PK / identity; audit query from [09](09-replica-identity.md) returns no rows.
- [ ] Slot retention cap and alerts configured and *tested* (create an idle slot in staging).
- [ ] Worker/slot/sender budgets computed for peak (initial sync) not steady state.
- [ ] Dedicated role, TLS, `pg_hba`, secret management.
- [ ] DDL procedure and CI check that detects drift between publisher/subscriber schemas.
- [ ] Sequences plan; extension and collation parity.
- [ ] Failover/promotion rehearsal; re-point procedure; DNS/VIP.
- [ ] Reconciliation job (row counts + checksums) and an on-call runbook.
- [ ] For managed services: provider parameters, limits and failover behaviour reviewed ([18](18-use-cases-and-patterns.md)).
