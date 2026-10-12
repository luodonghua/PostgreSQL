# PostgreSQL

A collection of scripts, code snippets, and notes for working with PostgreSQL —
covering administration, performance, development, security, and running on
Amazon RDS.

## Contents

### Administration
Day-to-day operation and maintenance of a PostgreSQL server.

- [managing-postgresql.md](Administration/managing-postgresql.md) — common server management tasks
- [postgresql-maintenance.md](Administration/postgresql-maintenance.md) — routine maintenance (vacuum, analyze, reindex, bloat, pg_repack)
- [postgresql-monitoring.md](Administration/postgresql-monitoring.md) — monitoring queries (activity, locks, pg_stat_statements)
- [monitor-autovacuum.md](Administration/monitor-autovacuum.md) — tracking autovacuum behavior and XID wraparound
- [system-catalog.md](Administration/system-catalog.md) — querying the system catalogs
- [server-process-memory-with-pmap.md](Administration/server-process-memory-with-pmap.md) — inspecting backend memory with `pmap`

### Performance
Query planning and data-type choices that affect performance.

- [join-strategy-and-order.sql](Performance/join-strategy-and-order.sql) — how the planner chooses joins
- [use-right-data-type.md](Performance/use-right-data-type.md) — impact of data-type selection on storage and query performance

### Development
SQL and application-side examples for building on PostgreSQL.

- [query-examples.md](Development/query-examples.md) — assorted query idioms with output (`format`, date parts, `NOT IN (NULL)`, three-valued logic, window functions)
- [keyset-pagination.md](Development/keyset-pagination.md) — keyset/seek pagination with row-value comparison `(last_modified_ts, id) < (?, ?)`: why it beats `OFFSET`, tie-safety, and measured `EXPLAIN` plans
- [autonomous-transactions.md](Development/autonomous-transactions.md) — autonomous transactions (audit-survives-rollback): the `dblink` loopback pattern, why `pg_background` isn't portable, and RDS/Aurora guidance
- [partition-example.md](Development/partition-example.md) — table partitioning, sub-partitioning, attach/detach, and the cost of deep nesting
- [create-1000-sub-partition.sql](Development/create-1000-sub-partition.sql) — generated DDL for a 1000-partition / 1000-level setup (runnable script)
- [timestamp-with-time-zone.md](Development/timestamp-with-time-zone.md) — `timestamp` vs `timestamptz` behavior
- [char-varchar-and-text-effects-on-trailing-space.md](Development/char-varchar-and-text-effects-on-trailing-space.md) — `char`/`varchar`/`text` trailing-space differences
- [create-table-with-oids.md](Development/create-table-with-oids.md) — legacy `WITH OIDS` tables
- [table-size-estimation.md](Development/table-size-estimation.md) — estimating table size from page layout
- [hybrid-jsonb-banking.md](Development/hybrid-jsonb-banking.md) / [hybrid-jsonb-banking.sql](Development/hybrid-jsonb-banking.sql) — hybrid JSONB + relational design (banking): keep hot fields (balance) relational, reserve JSONB for stable data; measured ~6× WAL reduction
- [jsonb-wal-internals.md](Development/jsonb-wal-internals.md) — what PostgreSQL writes to the WAL on `UPDATE`, with real `pg_walinspect`-decoded records for inline JSONB, TOAST pointer reuse, and TOAST rewrite cascades
- [btree.md](Development/Indexes/btree.md) — B-tree (default): balanced ordered tree, high-key/right-link concurrency, splits, dedup, ordered scans
- [hash.md](Development/Indexes/hash.md) — Hash (equality-only): value→bucket, overflow pages, bucket splits, stores only the hash code
- [brin.md](Development/Indexes/brin.md) — BRIN (Block Range Index): per-range min/max summaries, revmap, lossy bitmap scan, correlation dependence
- [gin.md](Development/Indexes/gin.md) — GIN (Generalized Inverted Index): inverted structure, posting lists/trees, varbyte compression, `fastupdate` pending list
- [gist.md](Development/Indexes/gist.md) — GiST (Generalized Search Tree): bounding-predicate tree, opclass support functions, KNN, NSN/right-link concurrency, buffering build
- [spgist.md](Development/Indexes/spgist.md) — SP-GiST (Space-Partitioned GiST): quadtree/k-d/radix tries, inner/leaf tuples, redirect tuples, triple-parity concurrency
- [index-comparison.md](Development/Indexes/index-comparison.md) — B-tree vs Hash vs BRIN vs GIN vs GiST vs SP-GiST comparison and decision guide (with animations)
- [load-data-daily-equity-volumes.sql](Development/load-data-daily-equity-volumes.sql) / [query-daily-equity-volumes.sql](Development/query-daily-equity-volumes.sql) — US equity volumes dataset
- [load-data-t-oil.sql](Development/load-data-t-oil.sql) — oil dataset load
- [UUIDv7/](Development/UUIDv7/) — UUIDv7 generation and partition migration ([details](Development/UUIDv7/README.md))
- [SampleSchema/](Development/SampleSchema/) — sports-ticketing sample database ([details](Development/SampleSchema/README.md))
- [Python/](Development/Python/) — parallel load/copy and SQLAlchemy examples
- [Java/](Development/Java/) — JDBC examples ([index](Development/Java/README.md)); incl. [prepared-statement plan-cache demo](Development/Java/jdbc-prepared-statement-plan-cache.md)
- [datasets/](Development/datasets/) — sample datasets used by the scripts above

### Extension
PostgreSQL extensions and low-level inspection.

- [pageinspect_heap_index.md](Extension/pageinspect_heap_index.md) — inspecting heap and B-tree index page internals with `pageinspect`

### Security
Authentication, authorization, and access control.

- [postgresql-security.sql](Security/postgresql-security.sql) — general security examples
- [schema-usage-privilege.md](Security/schema-usage-privilege.md) — schema-level `USAGE` vs object privileges, walked through two sessions
- [connect-rds-postgresql-with-iam-authentication.md](Security/connect-rds-postgresql-with-iam-authentication.md) — IAM authentication to RDS, with SSL modes
- [krb5_pac_info.md](Security/krb5_pac_info.md) / [krb5_pac_info.c](Security/krb5_pac_info.c) — Kerberos PAC info

### RDS-PostgreSQL
Amazon RDS for PostgreSQL specifics.

- [replication-lag-on-read-replica.md](RDS-PostgreSQL/replication-lag-on-read-replica.md) — measuring replica lag and query-vs-replay conflicts (`hot_standby_feedback`, `max_standby_streaming_delay`)
- [simulate-long-running-query.md](RDS-PostgreSQL/simulate-long-running-query.md) — reproducing long-running queries with `pg_sleep`

### Connection-Pooling
Connection pooling options for PostgreSQL and how to choose between them.

- [pgbouncer-vs-rds-proxy.md](Connection-Pooling/pgbouncer-vs-rds-proxy.md) — detailed PgBouncer vs Amazon RDS Proxy comparison with diagrams
- [rds-proxy/](Connection-Pooling/rds-proxy/) — managed RDS Proxy setup, IAM auth, failover ([details](Connection-Pooling/rds-proxy/README.md))
- [pgbouncer/](Connection-Pooling/pgbouncer/) — PgBouncer pooling modes and configuration ([details](Connection-Pooling/pgbouncer/README.md))
- [application-framework/](Connection-Pooling/application-framework/) — application-side pools (HikariCP, SQLAlchemy, pgx, node-pg, Npgsql) ([details](Connection-Pooling/application-framework/README.md))
- [lock-contention-pool-exhaustion.md](Connection-Pooling/lock-contention-pool-exhaustion.md) — playbook: batch row locks blocking OLTP and draining the app connection pool
- Overview: [Connection-Pooling/README.md](Connection-Pooling/README.md)

### Installation-Upgrade
Installing and upgrading PostgreSQL.

- [install-postgresql-13-on-amazon-linux-2.sh](Installation-Upgrade/install-postgresql-13-on-amazon-linux-2.sh) — install on Amazon Linux 2
- [major-upgrade.md](Installation-Upgrade/major-upgrade.md) — major version upgrade pre-checks

## Conventions

File names use lowercase `kebab-case` with no spaces so they are friendly on
Linux/macOS shells and in URLs. Java files keep their original names to match
their public class names, and Python files use `snake_case` per Python
convention.

## License

Released under the [MIT License](LICENSE).
