# Logical Replication — Study Notes (L200 → L400)

A self-contained learning path for PostgreSQL logical replication: what it is,
how each moving part works (publication, slot, decoding, apply), where it
breaks, and how to run it in production — **without reading the source or the
official docs**. Internals were cross-checked against the PostgreSQL source
(`src/backend/replication/logical/`, `src/backend/replication/pgoutput/`), and
every runnable example was executed.

## Version policy (read this first)

| Label | Meaning |
|---|---|
| **Tested on PostgreSQL 18.6** | Commands and output in these notes were run on a local 18.6 (Ubuntu pgdg) using [`lab.sh`](lab.sh). |
| **GA** | Released and stable: PostgreSQL 10 – 18. |
| ⚠️ **Non-GA** | Present in PostgreSQL 19 or 20devel source, **not run by me**, and may change before/after release. Each such statement is marked ⚠️ and cites the source file. PostgreSQL 19 appeared in the source tree only as `REL_19_RC1` when these notes were written; confirm its GA status before relying on it. |

Rule of thumb: if a section is not marked ⚠️, it is true for PG 18 and was
verified on 18.6 unless it says "(by source/doc only)".

## Reading order

| # | Level | Topic | File |
|---|---|---|---|
| 1 | L200 | Logical vs physical; architecture | [01-logical-vs-physical-and-architecture.md](01-logical-vs-physical-and-architecture.md) |
| 2 | L200 | Publications | [02-publications.md](02-publications.md) |
| 3 | L200 | Subscriptions | [03-subscriptions.md](03-subscriptions.md) |
| 4 | L200 | Step-by-step setup lab | [04-step-by-step-setup-guide.md](04-step-by-step-setup-guide.md) |
| 5 | L300 | Replication slots | [05-replication-slots.md](05-replication-slots.md) |
| 6 | L300 | Logical decoding pipeline | [06-logical-decoding.md](06-logical-decoding.md) |
| 7 | L300 | Reorder buffer & large transactions | [07-reorderbuffer-and-large-transactions.md](07-reorderbuffer-and-large-transactions.md) |
| 8 | L300 | pgoutput protocol | [08-pgoutput-protocol.md](08-pgoutput-protocol.md) |
| 9 | L300 | Replica identity | [09-replica-identity.md](09-replica-identity.md) |
| 10 | L300 | Initial sync / tablesync | [10-initial-sync-tablesync.md](10-initial-sync-tablesync.md) |
| 11 | L300 | Apply workers & parallel apply | [11-apply-workers-and-parallel-apply.md](11-apply-workers-and-parallel-apply.md) |
| 12 | L300 | Conflicts & error handling | [12-conflicts-and-error-handling.md](12-conflicts-and-error-handling.md) |
| 13 | L300 | Limitations | [13-limitations.md](13-limitations.md) |
| 14 | L400 | Monitoring & troubleshooting | [14-monitoring-and-troubleshooting.md](14-monitoring-and-troubleshooting.md) |
| 15 | L400 | Best practices | [15-best-practices.md](15-best-practices.md) |
| 16 | L400 | Failover & HA | [16-failover-and-ha.md](16-failover-and-ha.md) |
| 17 | L400 | Upgrades & migrations | [17-upgrades-and-migrations.md](17-upgrades-and-migrations.md) |
| 18 | L400 | Use cases & patterns (native PostgreSQL) | [18-use-cases-and-patterns.md](18-use-cases-and-patterns.md) |
| 19 | L400 | Source-code map | [19-source-code-map.md](19-source-code-map.md) |
| 20 | L400 | Amazon RDS / Aurora: privileges, parameters, **DR failover measured on AWS** | [20-amazon-rds-and-aurora.md](20-amazon-rds-and-aurora.md) |

Diagrams live in [diagrams/](diagrams/) as editable `.drawio` plus a rendered
`.svg`; regenerate both with `python3 diagrams/gen.py`.

## Feature timeline (when each capability became available)

Release assignments for 10–18 are from PostgreSQL release notes as I know them;
19 and later are from `git tag --contains` on the source tree.

| Release | Logical-replication capability |
|---|---|
| 10 | Publications/subscriptions, `pgoutput` |
| 11 | `TRUNCATE` replication |
| 13 | Partitioned tables as publication members, `publish_via_partition_root`, `logical_decoding_work_mem` (spill), `max_slot_wal_keep_size` |
| 14 | Streaming in-progress transactions (`streaming = on`), `binary` option |
| 15 | Row filters, column lists, `TABLES IN SCHEMA`, `two_phase`, `disable_on_error`, `ALTER SUBSCRIPTION ... SKIP` |
| 16 | Decoding on standbys, parallel apply (`streaming = parallel`), `origin = none`, indexes used on apply for `REPLICA IDENTITY FULL`, non-superuser subscription owners |
| 17 | Failover slots (`failover`, `sync_replication_slots`), `pg_createsubscriber`, slots/subscriptions survive `pg_upgrade` |
| 18 | `publish_generated_columns`, `idle_replication_slot_timeout`, conflict statistics, more conflict types (e.g. multiple-unique conflicts) |
| ⚠️ 19 | `ALL SEQUENCES` publications + sequence sync, `EXCEPT (TABLE …)`, dynamic `effective_wal_level`, `retain_dead_tuples` / `max_retention_duration`, per-subscription `wal_receiver_timeout` |
| ⚠️ 20devel | `conflict_log_destination` (log conflicts to a table) — landed on master 2026-07, after the 19 branch |

## Glossary

- **WAL** — write-ahead log; the ordered record of every change.
- **Logical decoding** — turning WAL records into row-level changes.
- **Output plugin** — formats decoded changes (`pgoutput`, `test_decoding`, `wal2json`).
- **Slot** — server-side bookmark that pins WAL (and catalog rows) for a consumer.
- **Publication** — publisher-side definition of *what* to send.
- **Subscription** — subscriber-side definition of *where from* and *how* to apply.
- **Replica identity** — the columns that identify a row in UPDATE/DELETE messages.
- **Origin** — subscriber-side record of how far a given source has been applied.
- **LSN** — log sequence number; a byte position in WAL (`0/17C6048`).

## Tools

[`tools/slot-peek`](tools/slot-peek/README.md) shows what is waiting in a logical
replication slot (transactions, tables, operations, keys, values) without consuming it,
and can generate replay SQL for reconciliation. Python and psql versions, PostgreSQL 10+,
RDS/Aurora.

## Lab helper

[`lab.sh`](lab.sh) spins up a throwaway publisher (5433) and subscriber (5434)
under `/tmp/lr-lab` and deletes them afterwards. It never touches your real
cluster.

```bash
cd Replication/LogicalReplication
source lab.sh
lab_up          # start both
pub -c "select version()"
sub -c "select 1"
lab_down        # stop + delete
```
