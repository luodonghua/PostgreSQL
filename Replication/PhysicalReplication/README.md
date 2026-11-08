# Physical (Streaming) Replication — Study Notes (L200 → L400)

A self-contained learning path for PostgreSQL physical replication: how the primary ships WAL to
standbys, how to set one up, keep it safe (slots, synchronous commit), serve reads (hot standby),
measure it, and fail over — without reading the source or the official docs. Companion to
[LogicalReplication/](../LogicalReplication/README.md).

## Version policy

| Label | Meaning |
|---|---|
| **Tested on PostgreSQL 18.6** | Commands and output were run on a local 18.6 (Ubuntu pgdg) with [`lab.sh`](lab.sh) (primary `:5433`, standby `:5435`, optional second standby `:5436`) |
| **(docs)** / "not tested" | Taken from documentation or source reading, not run by me. Each such statement is labelled |
| **Managed services** | [Topic 10](10-rds-aurora-physical-replication.md) is from AWS documentation and may change; verify before relying on it |
| ⚠️ **Non-GA** | PostgreSQL 19 / 20devel source features. The physical-replication notes rarely need them; where they do, they are marked ⚠️ |

## Reading order

| # | Level | Topic | File |
|---|---|---|---|
| 1 | L200 | Architecture: walsender, walreceiver, startup, LSN stages, timelines | [01-streaming-replication-architecture.md](01-streaming-replication-architecture.md) |
| 2 | L200 | Step-by-step standby setup (tested) | [02-standby-setup-guide.md](02-standby-setup-guide.md) |
| 3 | L300 | Slots, `wal_keep_size`, WAL retention and the "segment already removed" failure | [03-replication-slots-and-wal-retention.md](03-replication-slots-and-wal-retention.md) |
| 4 | L300 | Synchronous replication: levels, quorum, the availability trap | [04-synchronous-replication.md](04-synchronous-replication.md) |
| 5 | L300 | Hot standby and recovery conflicts | [05-hot-standby-and-query-conflicts.md](05-hot-standby-and-query-conflicts.md) |
| 6 | L300 | Monitoring and measuring lag (bytes vs time) | [06-monitoring-and-lag.md](06-monitoring-and-lag.md) |
| 7 | L300–400 | Failover, switchover, promotion, `pg_rewind` | [07-failover-switchover-promotion.md](07-failover-switchover-promotion.md) |
| 8 | L300 | Cascading, delayed standby, archive, PITR, `pg_receivewal` | [08-cascading-delayed-archive.md](08-cascading-delayed-archive.md) |
| 9 | L400 | Best practices and troubleshooting catalog | [09-best-practices-and-troubleshooting.md](09-best-practices-and-troubleshooting.md) |
| 10 | L300 | RDS / Aurora (from AWS docs) | [10-rds-aurora-physical-replication.md](10-rds-aurora-physical-replication.md) |
| 11 | L400 | Source-code map | [11-source-code-map.md](11-source-code-map.md) |

Diagrams are in [diagrams/](diagrams/) as editable `.drawio` plus rendered `.svg`;
regenerate with `python3 diagrams/gen.py` (it reuses the engine in the logical folder).

## Highlights of what was measured (18.6)

- A standby that falls behind **without** a slot or archive fails with `requested WAL segment … has already been removed`;
  **with** an archive the same standby restores from it and resumes streaming ([03](03-replication-slots-and-wal-retention.md), [08](08-cascading-delayed-archive.md)).
- A slot without a cap lets a dead standby fill the primary's disk; with `max_slot_wal_keep_size` the slot is invalidated instead ([03](03-replication-slots-and-wal-retention.md)).
- Synchronous commit costs, single client loopback: `local` 0.49 ms → `on` 2.1 ms → `remote_apply` 3.3 ms; losing the only sync standby makes commits wait in `SyncRep` forever ([04](04-synchronous-replication.md)).
- `hot_standby_feedback` prevents snapshot conflicts but **not** lock conflicts; `max_standby_streaming_delay = -1` makes replay stall instead ([05](05-hot-standby-and-query-conflicts.md)).
- `replay_lag` stayed at 0.1 s while replay was 16 MB behind; `now() - pg_last_xact_replay_timestamp()` showed 9 s on a perfectly synced idle system ([06](06-monitoring-and-lag.md)).
- An old primary that took a write after the failover cannot rejoin (`new timeline 2 forked off…`); `pg_rewind` fixes it, but needs retained WAL, checksums/hints and file-read privileges, and **overwrites `postgresql.conf`** ([07](07-failover-switchover-promotion.md)).

## Lab helper

[`lab.sh`](lab.sh) builds a throwaway primary + standby under `/tmp/pr-lab` and deletes them afterwards. It never touches
an existing cluster.

```bash
cd Replication/PhysicalReplication
source lab.sh
plab_up                      # primary :5433, standby :5435 (trust auth)
prim -c "select * from pg_stat_replication"
stby -c "select pg_is_in_recovery()"
plab_add_standby2            # cascaded standby :5436 (from the first standby)
plab_down
```

`plab_up` takes extra `postgresql.conf` lines for the primary as arguments, e.g. `plab_up "wal_keep_size = 256MB"`.
