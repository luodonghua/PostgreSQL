# 20 — Amazon RDS for PostgreSQL and Aurora PostgreSQL

Level: L400. This topic covers what differs on the managed services. The native behaviour
is in topics 01–18. The failover/DR behaviour (§5–§7) was **measured on AWS** with Aurora
and RDS PostgreSQL 17.11. The privilege checks in §1 were measured on RDS for PostgreSQL 18.6.
§2 has the parameter baseline for the publisher and the subscriber. Its defaults come from
the AWS parameter API, with some values measured on RDS 18.6.

Apart from the tested parts named above, §1, §3–§4 and §8–§11 are **from AWS documentation**, not tested by me:
[RDS logical replication](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/PostgreSQL.Concepts.General.FeatureSupport.LogicalReplication.html),
[logical slot synchronization](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Appendix.PostgreSQL.CommonDBATasks.pglogical.slot.synchronization.html),
[Aurora logical replication](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/AuroraPostgreSQL.Replication.Logical.html),
[Aurora Global Database switchover/failover](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-global-database-disaster-recovery.html),
[RDS Blue/Green](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/blue-green-deployments-overview.html).
That content is rephrased from those pages; verify it before relying on it.

Sections **§5–§7 and §12 were measured on real AWS resources**.

## 1. Enabling it (publisher)

| Step | Detail |
|---|---|
| Privileges | The user needs `rds_superuser` (to enable) and `rds_replication` (to manage/stream logical slots) |
| Parameter | Set `rds.logical_replication = 1` in a **custom** parameter group (instance) / cluster parameter group (Aurora). It is **static**, so a reboot is needed. It sets `wal_level`, `max_wal_senders`, `max_replication_slots` and `max_connections` accordingly |
| Cost warning | AWS notes this can increase WAL generation; enable only when using logical slots |
| Plugins | `pgoutput` (native), plus `test_decoding` and `wal2json` on RDS; Aurora lists `wal2json` as well |
| Extension | `pglogical` is also supported (set `shared_preload_libraries` and `rds.logical_replication`) |

You cannot edit `postgresql.conf` or `pg_hba.conf`; connectivity is via security groups and
VPC routing. The AWS walkthrough runs `CREATE SUBSCRIPTION` on the target with an admin account
(the docs list `rds_superuser` as the role required to turn logical replication on).

**Every DR target needs this parameter too.** Set `rds.logical_replication = 1` on each Aurora cluster's
parameter group in every region, and on every RDS instance that may be promoted.

### Privileges without a superuser

RDS and Aurora have no superuser. The master user is a member of `rds_superuser`,
`rds_replication` and `pg_create_subscription`, and that covers every superuser-only step
of logical replication (verified on RDS for PostgreSQL 18.6; Aurora uses the same role model):

| Operation | Community PostgreSQL needs | RDS / Aurora needs |
|---|---|---|
| `CREATE PUBLICATION … FOR ALL TABLES` / `FOR TABLES IN SCHEMA` | superuser | `rds_superuser`. Other roles get `must be rds_superuser to create FOR ALL TABLES publication` |
| `CREATE PUBLICATION … FOR TABLE` | table owner + `CREATE` on the database | same |
| Create / drop logical slots, stream changes | superuser or `REPLICATION` | `rds_replication` |
| `CREATE SUBSCRIPTION` | superuser, or `pg_create_subscription` + `CREATE` | same (the master user has both) |
| `ALTER SUBSCRIPTION … SKIP` | subscription owner (PG16+) | same |
| `pg_replication_origin_advance` and the other origin functions | superuser (default `EXECUTE` grant) | `rds_superuser` |

So the stalled-subscription runbooks in [12](12-conflicts-and-error-handling.md) work on
RDS/Aurora when run by a member of `rds_superuser`.

### Copying roles to or from RDS/Aurora

`pg_dumpall --roles-only` needs `--no-role-passwords` when the source is RDS/Aurora, because
`pg_authid` is not readable there. Set the passwords separately. This is managed-service
behaviour I did not test here. Then restore the schema keeping owners and grants
([15 §4](15-best-practices.md#day-0)).

## 2. Parameter baseline (publisher and subscriber)

These are the managed-service equivalents of the native baseline in
[15 §2](15-best-practices.md#2-configuration-baseline). You set the same parameters in a **custom parameter group**:
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

### Source (publisher)

| Parameter | RDS | Aurora | Default | Apply | Suggested / why |
|---|---|---|---|---|---|
| `rds.logical_replication` | instance | cluster | `0` | static | `1`. This is what sets `wal_level = logical` (*measured*: `wal_level = logical` after the reboot). Required on every node that may become the publisher, including DR targets ([§1](#1-enabling-it-publisher)) |
| `max_replication_slots` | instance | cluster | `20` (*measured* on RDS) | static | Same formula as native: subscriptions × (1 + sync workers) + CDC/DMS slots + spare |
| `max_wal_senders` | instance | cluster | RDS `35` (*measured*), Aurora `10` | static | ≥ `max_replication_slots` you actually use + other replication clients. Aurora's default of 10 is the tighter one |
| `max_slot_wal_keep_size` | instance | **instance** | `-1` = unlimited (*measured*) | dynamic | **Set it**. A dead slot can fill RDS storage ([§4](#4-storage-risk-is-the-same-bigger-blast-radius)) |
| `idle_replication_slot_timeout` (PG18) | instance | cluster | `0` = off (*measured*) | dynamic | e.g. `2d`, so abandoned slots (old DMS tasks, deleted subscribers) get invalidated |
| `logical_decoding_work_mem` | instance | instance | engine default (64 MB) | dynamic | Raise if `pg_stat_replication_slots.spill_*` grows ([07](07-reorderbuffer-and-large-transactions.md)) |
| `rds.logical_decoding_work_disk` | — | instance | not set | dynamic | Aurora only: caps the disk space used for logical decoding (spill) |
| `wal_sender_timeout` | instance | cluster | RDS **30 s** (*measured*; community default is 60 s) | dynamic | Keep ≥ the longest expected subscriber stall |
| `rds.force_ssl` | instance | cluster | `1` | — | Subscribers must connect with TLS: put `sslmode=verify-full` + the RDS CA bundle in the conninfo |
| `track_commit_timestamp` | instance | cluster | off | static | `on` if conflict detection on a writable subscriber needs `origin_differs` |
| `rds.replica_identity_full` | instance | — | `0` | dynamic | Leave `0`. It forces `REPLICA IDENTITY FULL` on **all** tables (more WAL, [09](09-replica-identity.md)) |
| `synchronized_standby_slots`, `rds.logical_slot_sync_dbname`; `sync_replication_slots` on the replica | instance | — (`sync_replication_slots` is not modifiable on Aurora) | off | dynamic | RDS 17+ slot sync to a read replica only ([§8](#8-rds-postgresql-17-slot-synchronisation-to-a-read-replica-docs-not-tested)) |
| `rds.logical_wal_cache` | — | cluster | not set | static | Aurora's write-through cache for logical WAL ([§9](#9-aurora-specifics-docs)) |
| `aurora.enhanced_logical_replication` | — | cluster | not set | static | Aurora Enhanced Logical Replication. The parameter descriptions say that `aurora.logical_replication_backup` and `aurora.logical_replication_globaldb` must be `0` when it is on (both default to `1`) |
| `rds.logically_replicate_unlogged_tables` | — | cluster | not set | static | Aurora only: include unlogged tables in the stream |
| `rds.iam_auth_for_replication` | instance | cluster | `0` | dynamic | `1` to allow IAM authentication for replication connections |

The replication user needs `rds_replication` (slots and streaming). `FOR ALL TABLES` /
`TABLES IN SCHEMA` publications need `rds_superuser` (tested, [§1](#privileges-without-a-superuser)).

### Target (subscriber)

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

## 3. Typical flow (docs)

Same SQL as [04](04-step-by-step-setup-guide.md): create the publication on the source,
tables on the target, `CREATE SUBSCRIPTION … CONNECTION 'host=<endpoint> port=5432 dbname=… user=… password=…'`.
After adding a table to the publication, `ALTER SUBSCRIPTION … REFRESH PUBLICATION` is mandatory
(as tested in [03](03-subscriptions.md)).

## 4. Storage risk is the same, bigger blast radius

AWS states that an unread logical slot can fill the instance's storage quickly. Monitor
`pg_replication_slots` and the CloudWatch metrics `OldestReplicationSlotLag` and `TransactionLogsDiskUsage`
(names per RDS docs — verify in your console). Set `max_slot_wal_keep_size` and
`idle_replication_slot_timeout` via the parameter group where your engine version has them
([05](05-replication-slots.md)). Slots survive Aurora role changes (§5), so an abandoned slot keeps
pinning WAL on the **new** primary too.

## 5. What happens to slots and subscriptions on failover (tested on AWS)

| | |
|---|---|
| Engines | Aurora PostgreSQL **17.11** (Serverless v2) and RDS for PostgreSQL **17.11** (`db.t4g.micro`) |
| Regions | One primary region and one secondary region (US West / US East) |
| Subscriber | Local PostgreSQL 18.6 |
| Tooling | AWS CLI 2.39 |
| When | November 2026 |
| Repeat count | Each event ran **once or twice**, so timings are indicative, not SLAs |
| Masking | Resource names, endpoints, ARNs and IPs are left out; only results are shown |

**Do logical slots survive?** Before each event two logical slots were created on the writer: a plain one,
and one with the PG17 `failover = true` flag (`pg_create_logical_replication_slot(name, 'pgoutput', false, false, true)`).
Afterwards `pg_replication_slots` was read on the new primary.

| Event | Slots on the **new primary** | Details |
|---|---|---|
| **Aurora Global Database switchover** (planned, `switchover-global-cluster`) | **Present** (both) | Same `restart_lsn` / `confirmed_flush_lsn` as before. `failover` flag kept as created, `synced = f`, `active = f`. New slots can be created |
| **Aurora Global Database failover** (unplanned, `failover-global-cluster --allow-data-loss`) | **Present** (all, including those carried over from the earlier switchover) | Positions kept. New slots can be created |
| **Aurora in-region failover** to a reader (`failover-db-cluster`) | **Present** | |
| **RDS Multi-AZ (instance) failover** (`reboot-db-instance --force-failover`) | **Present** (both) | |
| **RDS cross-region read replica promotion** (`promote-read-replica`) | **Absent** | And no new slot can be created until the parameter group is fixed (§6) |

Further observations:

- The flag made no difference. Aurora kept the plain slot and the `failover = true` slot alike, so the PG17
  failover-slot setup ([topic 16](16-failover-and-ha.md)) is **not needed on Aurora**.
- On a secondary-region reader, slots are **not visible** before the event: 0 rows in
  `pg_replication_slots`. Their absence on a reader proves nothing about what happens on promotion.
- After the unplanned failover AWS rebuilt the old primary region automatically. It rejoined as a
  secondary after about 15 minutes, and its readers again showed no slots.

**Real subscriber, connected only through the Aurora global writer endpoint.** The global writer endpoint is
`describe-global-clusters … GlobalClusters[0].Endpoint`. The subscription was **never altered** during the test,
and a writer inserted one row per second through the same endpoint. After each event, the rows on the current
writer and on the subscriber were compared, counting only rows written **after** the role change.

| Event | Rows written on the **new primary** after the role change | Arrived at subscriber | Extra rows on subscriber | Writer outage via global endpoint | Subscription changed? |
|---|---|---|---|---|---|
| **Switchover** | 33 | **33 / 33** within 120 s | 0 | Longest gap 15 s (8 failed 1-per-second writes) | **No** |
| **Failover** (run A) | 35 | **35 / 35**; all rows matched about 4.5 min after the failover started | 0 | Not measured in this run | **No** |
| **Failover** (run B) | 24 | **0 / 24 at +3.4 min** (not yet caught up when measured) | 0 | Writes failed intermittently for about 3 min after the role change | **No** |

The `extra rows on subscriber` column was 0 in every run: the subscriber never held rows that the new primary
lacked, which is the silent-divergence risk of a lossy failover. These runs had light, steady load and both
regions were healthy. A real regional outage with heavy writes can still lose unreplicated commits on
`--allow-data-loss`, so compare data after a failover.

What the subscriber logged (masked). Switchover — the apply worker reconnected on its own within about 15 s:

```
ERROR:  could not receive data from WAL stream: SSL error: unexpected eof while reading
ERROR:  apply worker for subscription "s" could not connect to the publisher: … failed: FATAL:  the database system is starting up
ERROR:  apply worker for subscription "s" could not connect to the publisher: … failed: Connection refused
        (retries every 5 s — wal_retrieve_retry_interval — then streams from the new primary)
```

Failover, run B — the slow part:

```
01:06:50  ERROR:  could not receive data from WAL stream: SSL error: unexpected eof while reading
01:09:06  ERROR:  apply worker … could not connect to the publisher: … failed: Connection timed out
```

A **single connection attempt hung for 2 min 16 s**. That is the operating system's TCP SYN-retry timeout,
which applies because the subscription conninfo had no `connect_timeout`. Run A logged the same
`Connection timed out` once and then converged.

**How long each step took** (wall clock as observed by polling, one or two samples each):

| Step | Observed |
|---|---|
| Global Database switchover: command → new region is the global writer | ~33–35 s, plus ~30 s until both clusters report `available` |
| Global Database failover: command → new region is the global writer | ~10–33 s |
| Old primary region rebuilt and rejoined as secondary after a failover | ~14.5 min |
| Aurora in-region failover to a reader | Under 1 min |
| RDS Multi-AZ forced failover | Under 1 min after the reboot call |
| RDS cross-region replica promotion → instance `available` | ~5 min |
| RDS parameter group change + reboot on the promoted instance | ~2.5 min |
| Provisioning (Serverless v2 writer / secondary region / RDS instance / cross-region replica) | ~7 / ~11 / ~9–11 / ~14.5 min |

## 6. RDS cross-region read replica promotion (tested)

| Step | Observed |
|---|---|
| Create the replica with the source's parameter group | **Rejected by the API**: `InvalidParameterCombination: A parameter group can't be specified during Read Replica creation for the following DB engine: postgres`. The replica therefore runs with the destination region's **default** parameter group |
| Replica before promotion | `in_recovery = t`, `wal_level = replica`, `rds.logical_replication = off`, no slots |
| Right after promotion | `in_recovery = f`, still `wal_level = replica`, **no slots**. `pg_create_logical_replication_slot` → `ERROR: logical decoding requires "wal_level" >= "logical"`. One connection attempt timed out while the instance settled |
| Attach a parameter group with `rds.logical_replication = 1`, then reboot | About 2.5 min. Afterwards `wal_level = logical`; old slots are still absent, and **new slots can be created** |

So after promoting an RDS read replica, a logical consumer needs a **new endpoint**, a **parameter group
change plus reboot**, and a **new slot/subscription**. Use `copy_data = true`, or create the slot and then
compare and repair data ([topic 13](13-limitations.md), [topic 14](14-monitoring-and-troubleshooting.md)).
A good place to prepare is right after creating the replica: attach the logical-replication parameter group
to it then (`modify-db-instance --db-parameter-group-name`), so the promotion doesn't need an extra reboot.
I did not test that variant.

## 7. DR runbooks derived from the results

**Aurora Global Database (switchover or failover)**

Prepare beforehand:
1. Point the subscription (or CDC connector) at the **global writer endpoint**, not a cluster or
   instance endpoint. Then no `ALTER SUBSCRIPTION … CONNECTION` is needed after either event (tested).
2. Add **`connect_timeout=10`** (and TCP keepalives) to the subscription conninfo, to avoid the
   2-minute hang on a dead address after an unplanned failover. This is reasoned from the observed failure
   and **not tested**.
3. Set `rds.logical_replication = 1` in the parameter group of **every** region's cluster.
4. Alert on retained WAL and inactive slots on the writer (§4).

After the event:
1. **Switchover:** nothing to change. Verify `pg_stat_subscription` shows the worker streaming and the
   slot is `active` on the new writer.
2. **Failover:** wait for the apply worker to reconnect, which took minutes in run B. Then:
   - Check for rows on the subscriber that the new primary lacks. A failover discards commits that hadn't
     replicated. None appeared in these runs, but with real write load you must check.
   - If you find any, repair them ([12](12-conflicts-and-error-handling.md)) or re-sync the affected tables.
3. Drop slots on the new primary that belong to consumers you no longer run.

**RDS for PostgreSQL**

| Situation | Action |
|---|---|
| Multi-AZ instance failover (same region) | Nothing for slots (they survive). Clients reconnect to the same DNS endpoint |
| Cross-region replica promotion | Repoint to the new endpoint. Apply a parameter group with `rds.logical_replication = 1` and reboot. Recreate slots/subscriptions; old slots are gone. Prepare the parameter group in advance, because replica creation can't set it (§6) |

**If the primary is the subscriber** (not tested): the subscription and its origin progress are catalog
data, so they move with the promoted node. Watch for two hazards:
- **Async lag.** If the new node is behind the old one, the publisher's slot may already be confirmed past
  changes the new node never applied, which leaves a gap. Compare counts.
- **DR drills.** In a DR drill, disable the copied subscription right after promotion. Otherwise it can
  grab the production publisher's slot.

## 8. RDS PostgreSQL 17+ slot synchronisation to a read replica (docs, not tested)

AWS documents the community PG17 slot-sync feature as available from RDS for PostgreSQL 17,
for a primary with a **read replica** plus a subscriber:

| Setting | Where |
|---|---|
| `CREATE SUBSCRIPTION … WITH (failover = true)` | subscriber |
| `rds.logical_replication = 1` | parameter group |
| `hot_standby_feedback = 1` | on the standby/replica |
| `rds.logical_slot_sync_dbname` = a valid database name (default `postgres`) | on the standby/replica |
| `synchronized_standby_slots` = the replica's physical slot | on the primary |
| `sync_replication_slots = 1` | on the standby/replica |

This mirrors [topic 16](16-failover-and-ha.md), where `rds.logical_slot_sync_dbname` plays the
role of the `dbname=` in `primary_conninfo`. After promotion the subscriber does
`ALTER SUBSCRIPTION … CONNECTION` to the new endpoint. This setup would be the way to keep slots across the
RDS promotion that lost them in §6. I didn't test it, so the promotion result in §6 is without it.

## 9. Aurora specifics (docs)

- WAL is on Aurora's shared storage; the writer decodes from there. A **write-through cache**
  (Aurora PostgreSQL 14.5 / 13.8 / 12.12 / 11.17 and later) avoids storage reads during decoding;
  AWS provides functions to monitor it.
- Logical decoding from read replicas (PG16 feature, [topic 16](16-failover-and-ha.md)) is stated as **not supported** on Aurora.
- After an unplanned Global Database failover AWS tries to snapshot the old primary's storage
  (`rds:unplanned-global-failover-…`) so you can recover unreplicated data. It is a system snapshot subject to the
  retention period.
- Slot behaviour across Aurora role changes: measured in §5.

## 10. Blue/Green deployments

AWS RDS Blue/Green for PostgreSQL requires a parameter group with logical replication
enabled, and uses logical replication between blue and green environments. Practical impacts:
slots exist on blue for the life of the deployment (watch WAL), DDL on blue during the
deployment is a replication problem (as in [13](13-limitations.md)), and sequences/large
objects/unlogged tables have the usual logical-replication caveats. See the AWS "limitations"
page for the current list.

## 11. Other managed-service considerations

| Concern | Guidance |
|---|---|
| No OS access | No `pg_waldump`/`pg_recvlogical` on the server; run client tools from EC2 |
| Parameter changes | Static ones (`rds.logical_replication`, `max_replication_slots`, `max_logical_replication_workers`) need reboot — plan a window |
| Read replicas | Physical replicas can't host the publisher's slots (except the slot-sync mechanism in §8) |
| AWS DMS | Uses a logical slot on the source for CDC; a stopped DMS task leaves the slot pinning WAL — drop it |
| Cross-account / cross-region | Security groups, VPC peering/PrivateLink, TLS; `sslmode=verify-full` with the RDS CA bundle |
| Cost | Data transfer + extra storage for retained WAL |
| Related repo notes | [RDS replication lag on a read replica](../../RDS-PostgreSQL/replication-lag-on-read-replica.md) (physical replicas, different mechanism) |

## 12. Reproducing the AWS test (method and pitfalls)

The test scripts are not kept in the repo. These are the AWS CLI calls that matter
(`<…>` are placeholders):

```bash
# Aurora: create a global database from an existing cluster, then a secondary cluster in the other region
aws rds create-global-cluster --region <primary-region> --global-cluster-identifier <global> \
    --source-db-cluster-identifier <primary-cluster-arn>
aws rds create-db-cluster --region <secondary-region> --db-cluster-identifier <secondary> \
    --engine aurora-postgresql --engine-version 17.11 --global-cluster-identifier <global> \
    --db-cluster-parameter-group-name <pg-with-rds.logical_replication=1> …

# the global writer endpoint (use it in CREATE SUBSCRIPTION) and who is the writer now
aws rds describe-global-clusters --global-cluster-identifier <global> \
    --query 'GlobalClusters[0].[Endpoint, GlobalClusterMembers[?IsWriter==`true`].DBClusterArn]'

# planned switchover (RPO 0)  /  unplanned failover (may lose data)
aws rds switchover-global-cluster --region <primary-region> --global-cluster-identifier <global> \
    --target-db-cluster-identifier <secondary-cluster-arn>
aws rds failover-global-cluster --region <primary-region> --global-cluster-identifier <global> \
    --target-db-cluster-identifier <secondary-cluster-arn> --allow-data-loss

# in-region: Aurora reader failover, RDS Multi-AZ failover, RDS cross-region replica promotion
aws rds failover-db-cluster --db-cluster-identifier <cluster> --target-db-instance-identifier <reader>
aws rds reboot-db-instance --db-instance-identifier <instance> --force-failover
aws rds promote-read-replica --region <secondary-region> --db-instance-identifier <replica>
```

```sql
-- probes on the writer before the event, checked on the new primary afterwards
SELECT pg_create_logical_replication_slot('probe',    'pgoutput');
SELECT pg_create_logical_replication_slot('probe_fo', 'pgoutput', false, false, true);  -- failover = true (PG17+)
SELECT slot_name, active, wal_status, restart_lsn, confirmed_flush_lsn, failover, synced FROM pg_replication_slots;
```

Measurement method:
- Record `max(id)` **after** the role change.
- Count rows above it on both the new writer and the subscriber, and diff the full id sets in both directions.
- A matching total count proves nothing about post-event writes.

Pitfalls that cost me reruns:

| Pitfall | Effect | Fix |
|---|---|---|
| Background write loop inside a `set -e` script | The first failed insert during the role change killed the loop silently | `set +e` in the loop's subshell; a hard `timeout` per statement and TCP keepalives |
| Parsing `psql -At … RETURNING id` output | The last line is the status `INSERT 0 1`, so successes counted as failures | Use `psql -q` |
| Measuring from the moment the switchover is *issued* | A switchover drains first, so writes in that window still go to the old primary | Measure from when the new writer is confirmed writable |
| Cleanup removes the global writer 20 s after detaching the secondary | `remove-from-global-cluster` failed silently, and the delete then hung waiting for an instance that was never deleted | Detach secondaries, **retry until the global cluster has 0 members**, then delete instances, clusters, then the global cluster |
| Passing `--db-parameter-group-name` to `create-db-instance-read-replica` (postgres) | API error `InvalidParameterCombination`; the replica uses the default group | Modify the instance after creation (§6) |

Not covered yet:
- An RDS Multi-AZ **DB cluster** (the 3-node variant).
- RDS PG17 slot sync (§8).
- The effect of `connect_timeout` on failover recovery time.
- Heavy write load, and a real regional impairment rather than a controlled failover.
- A subscriber that is itself on AWS and gets failed over.
