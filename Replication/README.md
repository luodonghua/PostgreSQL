# Replication

Study notes on PostgreSQL replication, written for learning without reading the source or the official
docs. All commands were run on a local **PostgreSQL 18.6**; anything newer than GA is marked ⚠️ non-GA. The AWS DR behaviour (Aurora Global Database switchover/failover, RDS promotion) was measured on real AWS resources — see [logical topic 20](LogicalReplication/20-amazon-rds-and-aurora.md).

| Folder | What it covers |
|---|---|
| [LogicalReplication/](LogicalReplication/README.md) | Publications, subscriptions, slots, decoding, `pgoutput`, replica identity, tablesync, parallel apply, conflicts, limitations, monitoring, best practices, failover slots, upgrades, RDS/Aurora, source map, with AWS DR behaviour measured on real resources (20 topics, L200–L400) |
| [PhysicalReplication/](PhysicalReplication/README.md) | Streaming replication architecture, standby setup, slots and WAL retention, synchronous replication, hot standby conflicts, lag monitoring, failover and `pg_rewind`, cascading/delayed/archive/PITR, troubleshooting, RDS/Aurora, source map (11 topics, L200–L400) |

Each folder has a `lab.sh` that creates throwaway local clusters (never touching your real one) and diagrams in
editable draw.io format with rendered SVG next to them.
