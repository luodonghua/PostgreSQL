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

### RDS for PostgreSQL and Aurora PostgreSQL

On the managed services, you set the same parameters in a **custom parameter group**:
a DB parameter group for RDS, and for Aurora either the **cluster** or the **instance**
parameter group, depending on the parameter. "Static" means a reboot.

Sources for the tables below:
- Defaults, apply type and level are from
  `aws rds describe-engine-default-parameters` / `describe-engine-default-cluster-parameters`
  for the `postgres18` and `aurora-postgresql18` families (Nov 2026).
- Values marked *measured* come from `SHOW` on an RDS for PostgreSQL 18.6 `db.t4g.micro`
  with `rds.logical_replication = 1`.
- Aurora values were not measured on a running instance.

Re-check them for your engine version.

#### Source (publisher)

| Parameter | RDS | Aurora | Default | Apply | Suggested / why |
|---|---|---|---|---|---|
| `rds.logical_replication` | instance | cluster | `0` | static | `1`. This is what sets `wal_level = logical` (*measured*: `wal_level = logical` after the reboot). Required on every node that may become the publisher, including DR targets ([20 §1](20-amazon-rds-and-aurora.md#1-enabling-it-publisher)) |
| `max_replication_slots` | instance | cluster | `20` (*measured* on RDS) | static | Same formula as native: subscriptions × (1 + sync workers) + CDC/DMS slots + spare |
| `max_wal_senders` | instance | cluster | RDS `35` (*measured*), Aurora `10` | static | ≥ `max_replication_slots` you actually use + other replication clients. Aurora's default of 10 is the tighter one |
| `max_slot_wal_keep_size` | instance | **instance** | `-1` = unlimited (*measured*) | dynamic | **Set it**. A dead slot can fill RDS storage ([20 §3](20-amazon-rds-and-aurora.md#3-storage-risk-is-the-same-bigger-blast-radius)) |
| `idle_replication_slot_timeout` (PG18) | instance | cluster | `0` = off (*measured*) | dynamic | e.g. `2d`, so abandoned slots (old DMS tasks, deleted subscribers) get invalidated |
| `logical_decoding_work_mem` | instance | instance | engine default (64 MB) | dynamic | Raise if `pg_stat_replication_slots.spill_*` grows ([07](07-reorderbuffer-and-large-transactions.md)) |
| `rds.logical_decoding_work_disk` | — | instance | not set | dynamic | Aurora only: caps the disk space used for logical decoding (spill) |
| `wal_sender_timeout` | instance | cluster | RDS **30 s** (*measured*; community default is 60 s) | dynamic | Keep ≥ the longest expected subscriber stall |
| `rds.force_ssl` | instance | cluster | `1` | — | Subscribers must connect with TLS: put `sslmode=verify-full` + the RDS CA bundle in the conninfo |
| `track_commit_timestamp` | instance | cluster | off | static | `on` if conflict detection on a writable subscriber needs `origin_differs` |
| `rds.replica_identity_full` | instance | — | `0` | dynamic | Leave `0`. It forces `REPLICA IDENTITY FULL` on **all** tables (more WAL, [09](09-replica-identity.md)) |
| `synchronized_standby_slots`, `rds.logical_slot_sync_dbname`; `sync_replication_slots` on the replica | instance | — (`sync_replication_slots` is not modifiable on Aurora) | off | dynamic | RDS 17+ slot sync to a read replica only ([20 §7](20-amazon-rds-and-aurora.md#7-rds-postgresql-17-slot-synchronisation-to-a-read-replica-docs-not-tested)) |
| `rds.logical_wal_cache` | — | cluster | not set | static | Aurora's write-through cache for logical WAL ([20 §8](20-amazon-rds-and-aurora.md#8-aurora-specifics-docs)) |
| `aurora.enhanced_logical_replication` | — | cluster | not set | static | Aurora Enhanced Logical Replication. The parameter descriptions say that `aurora.logical_replication_backup` and `aurora.logical_replication_globaldb` must be `0` when it is on (both default to `1`) |
| `rds.logically_replicate_unlogged_tables` | — | cluster | not set | static | Aurora only: include unlogged tables in the stream |
| `rds.iam_auth_for_replication` | instance | cluster | `0` | dynamic | `1` to allow IAM authentication for replication connections |

The replication user needs `rds_replication` (slots and streaming). `FOR ALL TABLES` /
`TABLES IN SCHEMA` publications need `rds_superuser` (tested, [20 §1](20-amazon-rds-and-aurora.md#privileges-without-a-superuser-tested-rds-for-postgresql-186)).

#### Target (subscriber)

| Parameter | RDS | Aurora | Default | Apply | Suggested / why |
|---|---|---|---|---|---|
| `max_logical_replication_workers` | instance | cluster | **4** (*measured* on RDS) | static | subscriptions × (1 + sync + parallel apply workers) + spare. 4 runs out with 2 subscriptions during the initial sync |
| `max_worker_processes` | instance | instance | `GREATEST(vCPU×2, 8)`; *measured* 8 on a 2-vCPU class | static | Must exceed logical workers + parallel query + autovacuum-related + extension workers. On small classes this, not the setting above, is the real ceiling |
| `max_sync_workers_per_subscription` | instance | cluster | `2` | dynamic | 2–4 for faster initial copy (also costs publisher slots and senders) |
| `max_parallel_apply_workers_per_subscription` | instance | cluster | `2` | dynamic | 2–4 for large-transaction apply ([11](11-apply-workers-and-parallel-apply.md)) |
| `max_active_replication_origins` (PG18) | instance | cluster | `20` (*measured*) | static | One origin per subscription plus one per running tablesync worker; raise with many subscriptions |
| `wal_receiver_timeout` | instance | cluster | `30 s` | dynamic | Keep it consistent with the publisher's `wal_sender_timeout` |
| `track_commit_timestamp` | instance | cluster | off | static | `on` for conflict diagnostics ([12](12-conflicts-and-error-handling.md)) |
| `rds.logical_replication` | instance | cluster | `0` | static | Not needed just to subscribe. Set it if the target will also publish, run CDC, or become the source after cut-over |

Also check:
- **Outbound connectivity.** An RDS/Aurora subscriber opens the connection itself, so it needs a
  network route and security-group egress to the publisher.
- **Static parameters need a reboot,** so set them before the initial sync.

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

- Pre-create the schema on the subscriber, **roles first**:
  1. `pg_dumpall --roles-only` and review the output. On RDS/Aurora add `--no-role-passwords`:
     `pg_authid` is not readable there, so set passwords separately (managed-service
     behaviour, not tested here). Apply it on the subscriber.
  2. `pg_dump --schema-only --no-publications --no-subscriptions` and apply it, **keeping**
     owners and `GRANT`s.

  `--no-owner --no-privileges` (used in the lab of [04](04-step-by-step-setup-guide.md)) is a
  shortcut for a throwaway lab where the roles don't exist on the subscriber. It is a poor
  default for real systems, for two reasons:
  - The subscriber becomes a usable copy only if readers have their grants and RLS policies.
  - Since PG16 the apply worker runs as the **table owner** (`run_as_owner = false`).
    The owners must exist, and the subscription owner must be able to `SET ROLE` to them.
    Tested on 18.6 with a non-superuser subscription owner `subown` and tables owned by
    `app_owner`:

    | Subscriber state | Result |
    |---|---|
    | `subown` not a member of `app_owner` | `ERROR: role "subown" cannot SET ROLE to "app_owner"` (sync retries) |
    | `GRANT app_owner TO subown`, but `app_owner` lacks rights on the table | `ERROR: permission denied for table t` |
    | Plus `GRANT SELECT, INSERT, UPDATE, DELETE ON t TO app_owner` | Copy succeeds |

    With `--no-owner`, every table is owned by the role that ran the restore, so this check
    passes trivially. The real owners and grants are then lost.
- Test the initial sync on a production-sized copy to learn duration, WAL growth,
  and the **`xmin` + `catalog_xmin` impact** ([10](10-initial-sync-tablesync.md)). Both
  matter, and the horizon is **database-wide, not per table**. Tested on 18.6:
  `a` was published, `b` was **not** in any publication.

  | What holds the horizon | `pg_replication_slots` | `VACUUM b` (unpublished user table) | `VACUUM pg_class` |
  |---|---|---|---|
  | A logical slot that exists (created, no snapshot held) | `xmin` empty, `catalog_xmin = 753` | 50 000 dead removed, **0 kept** | **300 dead kept** ("not yet removable") until the slot was dropped, then 297 removed |
  | A slot being created with an exported snapshot that stays open (`CREATE_REPLICATION_SLOT … (SNAPSHOT 'export')`, the same kind of snapshot a tablesync worker holds for its whole `COPY`) | `catalog_xmin = 756`, walsender `backend_xmin = 756` | **40 000 dead kept**, removable cutoff stuck at 756 | cutoff also stuck at 756 |
  | After the snapshot was released | | 40 000 removed | |

  So in steady state a logical slot holds back only **catalog** vacuum (`catalog_xmin`).
  During the initial copy, each tablesync worker's snapshot (`backend_xmin` of its walsender
  and of the `COPY` transaction) holds back vacuum of **every table in the database**, published
  or not, for as long as the largest table takes to copy. Plan the initial sync of big tables
  for low-churn periods, and watch `backend_xmin` in `pg_stat_activity` during it, not only
  `pg_replication_slots`.
- Test failover and rebuild procedures before you need them ([16](16-failover-and-ha.md)).

### Day-2

| Change | Procedure |
|---|---|
| Add column | Subscriber first, then publisher ([04](04-step-by-step-setup-guide.md) §9.1) |
| Drop column | Publisher first, after code stops using it |
| Add table | Create on subscriber; `ALTER PUBLICATION … ADD TABLE`; `ALTER SUBSCRIPTION … REFRESH PUBLICATION` (with `two_phase` use `copy_data=false`) |
| Rename / type change | Plan explicitly ([13](13-limitations.md)); pause the subscription |
| Re-sync one diverged table | Drop from publication → `REFRESH` → `TRUNCATE` → re-add → `REFRESH` (copy) — no quiesce needed ([10](10-initial-sync-tablesync.md#re-syncing-one-table-of-a-subscription)) |
| Move a hot table to its own subscription, or merge two | Atomic publication switch with a pre-created slot; no re-copy, no downtime ([03](03-subscriptions.md#moving-a-table-between-subscriptions-without-re-copying-split-and-merge)) |
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
  is a bloat problem as well as a disk problem ([05](05-replication-slots.md)). During an
  initial copy the tablesync snapshot also holds the **database-wide** `xmin`, which stops
  vacuum of unpublished tables too (§4 Day-0).

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
- [ ] For managed services: provider parameters, limits and failover behaviour reviewed ([20](20-amazon-rds-and-aurora.md)).
