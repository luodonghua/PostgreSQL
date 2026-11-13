# 10 — Physical Replication on Amazon RDS and Aurora

Level: L300. **Taken from AWS documentation, not tested by me** (I have no AWS environment in this
setup). Managed services change; every statement here should be re-checked on the linked
page for your engine version. Sources:
[RDS for PostgreSQL read replicas](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PostgreSQL.Replication.ReadReplicas.html),
[Aurora replication](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Aurora.Replication.html).
Content is paraphrased from those pages. Logical replication on RDS/Aurora is in
[logical topic 20](../LogicalReplication/20-amazon-rds-and-aurora.md).
A hands-on conflict experiment on an RDS read replica already exists in this repo:
[RDS replication lag on a read replica](../../RDS-PostgreSQL/replication-lag-on-read-replica.md).

## Mapping the concepts

| Concept in these notes | RDS for PostgreSQL | Aurora PostgreSQL |
|---|---|---|
| Streaming physical replication, hot standby | **Read replicas** — AWS says they use PostgreSQL's native replication | **Not used inside a cluster**: Aurora Replicas read the *same shared storage volume* as the writer |
| `pg_basebackup`, `primary_conninfo`, slots, `pg_hba.conf`, `postgresql.conf` | Managed for you; you cannot edit these files or run `pg_ctl` | Managed |
| Cascading standbys ([08](08-cascading-delayed-archive.md)) | Supported from RDS for PostgreSQL **14.1** onward; before that, no replica-of-replica | N/A (all readers attach to the same volume) |
| Promotion ([07](07-failover-switchover-promotion.md)) | Promote a read replica to a standalone instance — **irreversible**; replicas downstream of a promoted cascading replica keep receiving WAL from it | Automatic failover promotes an Aurora Replica to writer; "brief interruption" |
| Replica lag | CloudWatch replica-lag metric; see lag semantics below | Typically "much less than 100 ms" per AWS; grows with write rate |
| Delayed standby, PITR on a replica ([08](08-cascading-delayed-archive.md)) | **PITR is not supported on read replicas**; automated backups on replicas only from 14.1 | Cluster-level backups/PITR (not covered by the pages I read; check the Aurora docs) |
| Synchronous replication ([04](04-synchronous-replication.md)) | The pages I read describe read replicas as native-replication replicas but say nothing about `synchronous_standby_names`; I could not confirm user control — check before assuming. Multi-AZ options are a separate feature (not covered here) | The cluster volume is made of multiple physical copies (per the AWS page); durability comes from the storage layer, not PostgreSQL sync replication |
| Max replicas | Per AWS RDS limits (check the quota) | Up to **15** Aurora Replicas per cluster |

## RDS read replicas — details from the docs

- Read replicas are read-only; you can promote one into a standalone instance (not reversible).
- Cascading read replicas: RDS for PostgreSQL **14.1+** only.
- After promoting a replica in a chain, downstream replicas continue receiving WAL from it automatically.
- **Idle-lag artefact (documented):** with no transactions on the source, the replica can report up to five minutes of lag, because
  lag is computed as `currentTime − lastCommittedTransactionTimestamp`; it drops when the WAL segment switch (every 5 minutes by
  default) produces a transaction record. This is exactly the idle-primary trap in [06](06-monitoring-and-lag.md)
  (`now() - pg_last_xact_replay_timestamp()` grows on an idle system): *if the lag metric rises on a quiet source, check the byte/LSN gap
  before reacting.*
- No automated backups on replicas for versions before 14.1; use snapshots.
- Password rotation can briefly disconnect replicas on PG13+ (reconnect automatically); on PG12 and older they reboot during the
  rotation maintenance.

## What you tune on RDS

You manage replication through parameter groups on the **replica** (and source) rather than config files:

| Parameter (same meaning as in [05](05-hot-standby-and-query-conflicts.md)) | Effect |
|---|---|
| `max_standby_streaming_delay` | How long replay waits for a conflicting query |
| `hot_standby_feedback` | Prevents snapshot conflicts, can bloat the source |
| `max_standby_archive_delay` | Same during archive replay (only relevant if the replica replays archived WAL; the pages I read don't describe that path) |
| `max_wal_senders`, `wal_keep_size`, `max_slot_wal_keep_size` | Source-side capacity and WAL retention |

Read replica conflict behaviour is the same community PostgreSQL behaviour demonstrated in [05](05-hot-standby-and-query-conflicts.md)
(the repo's RDS note shows it on a real replica).

## Aurora specifics (from the AWS replication page)

- A cluster has one writer and up to 15 readers sharing a single logical **cluster volume** (multiple physical copies across AZs).
  All readers see the same data with minimal lag, typically well under 100 ms after the writer wrote it.
- Readers are for scaling reads and as **failover targets** (same instance class, different AZ recommended).
  If there are no readers the cluster is unavailable while the instance recovers.
- Failover can reboot some replicas depending on engine version; a read-availability feature avoids reader restarts when the writer is
  unreachable on newer Aurora PostgreSQL versions.
- Aurora PostgreSQL has no cross-region *Aurora Replicas*; use an **Aurora Global Database** (primary + up to 10 secondary clusters in
  other regions) for cross-region physical-style replication.
- Replication into/out of the cluster using PostgreSQL's logical replication is supported; an RDS PostgreSQL instance can be the source for
  an Aurora read replica (typically for migration).

## What this means for the lessons in this folder

| Lesson | On RDS/Aurora |
|---|---|
| Slots pin WAL ([03](03-replication-slots-and-wal-retention.md)) | Still applies to **logical** slots you create (storage can fill); replica internals are managed. Monitor `OldestReplicationSlotLag`/free storage (names per AWS docs — verify) |
| Parameter parity ([02](02-standby-setup-guide.md)) | AWS manages replica parameters; custom parameter groups are your lever |
| Failover checklist ([07](07-failover-switchover-promotion.md)) | Client endpoint (cluster/instance DNS) handles routing; test failover with the provided API/console action; connection pools must reconnect |
| Monitoring ([06](06-monitoring-and-lag.md)) | Use CloudWatch lag + `pg_stat_replication` on the source (visible on RDS), but prefer bytes where you can query them |
| Bloat from feedback ([05](05-hot-standby-and-query-conflicts.md)) | Same mechanism; high-write sources show it quickly |
| Backups | RDS/Aurora automated backups + PITR on the source/writer; replicas are not a backup |

## Questions to ask before designing around a managed replica

1. Which engine version? (cascading, replica backups, slot sync all depend on it)
2. Is lag measured in time or bytes by the metric I alert on, and does it have the idle artefact?
3. What does failover do to my connections/endpoints and to logical slots?
4. What are the instance-count and cross-region limits?
5. Which parameters can I change on the replica, and which need a reboot?
