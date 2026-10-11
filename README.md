# PostgreSQL

A collection of scripts, code snippets, and notes for working with PostgreSQL —
covering administration, performance, development, security, and running on
Amazon RDS.

## Contents

### Administration
Day-to-day operation and maintenance of a PostgreSQL server.

- [managing-postgresql.sql](Administration/managing-postgresql.sql) — common server management tasks
- [postgresql-maintenance.sql](Administration/postgresql-maintenance.sql) — routine maintenance (vacuum, analyze, reindex)
- [postgresql-monitoring.sql](Administration/postgresql-monitoring.sql) — monitoring queries
- [monitor-autovacuum.sql](Administration/monitor-autovacuum.sql) — tracking autovacuum behavior
- [system-catalog.sql](Administration/system-catalog.sql) — querying the system catalogs
- [server-process-memory-with-pmap.txt](Administration/server-process-memory-with-pmap.txt) — inspecting backend memory with `pmap`

### Performance
Query planning and data-type choices that affect performance.

- [join-strategy-and-order.sql](Performance/join-strategy-and-order.sql) — how the planner chooses joins
- [use-right-data-type.sql](Performance/use-right-data-type.sql) — impact of data-type selection

### Development
SQL and application-side examples for building on PostgreSQL.

- [query-examples.md](Development/query-examples.md) — assorted query idioms with output (`format`, date parts, `NOT IN (NULL)`, three-valued logic, window functions)
- [autonomous-transactions.md](Development/autonomous-transactions.md) — autonomous transactions (audit-survives-rollback): the `dblink` loopback pattern, why `pg_background` isn't portable, and RDS/Aurora guidance
- [partition-example.md](Development/partition-example.md) — table partitioning, sub-partitioning, attach/detach, and the cost of deep nesting
- [create-1000-sub-partition.sql](Development/create-1000-sub-partition.sql) — generated DDL for a 1000-partition / 1000-level setup (runnable script)
- [timestamp-with-time-zone.md](Development/timestamp-with-time-zone.md) — `timestamp` vs `timestamptz` behavior
- [char-varchar-and-text-effects-on-trailing-space.md](Development/char-varchar-and-text-effects-on-trailing-space.md) — `char`/`varchar`/`text` trailing-space differences
- [create-table-with-oids.md](Development/create-table-with-oids.md) — legacy `WITH OIDS` tables
- [table-size-estimation.md](Development/table-size-estimation.md) — estimating table size from page layout
- [load-data-daily-equity-volumes.sql](Development/load-data-daily-equity-volumes.sql) / [query-daily-equity-volumes.sql](Development/query-daily-equity-volumes.sql) — US equity volumes dataset
- [load-data-t-oil.sql](Development/load-data-t-oil.sql) — oil dataset load
- [UUIDv7/](Development/UUIDv7/) — UUIDv7 generation and partition migration ([details](Development/UUIDv7/README.md))
- [SampleSchema/](Development/SampleSchema/) — sports-ticketing sample database ([details](Development/SampleSchema/README.md))
- [Python/](Development/Python/) — parallel load/copy and SQLAlchemy examples
- [Java/](Development/Java/) — JDBC examples ([index](Development/Java/README.md)); incl. [prepared-statement plan-cache demo](Development/Java/jdbc-prepared-statement-plan-cache.md)
- [datasets/](Development/datasets/) — sample datasets used by the scripts above

### Security
Authentication, authorization, and access control.

- [postgresql-security.sql](Security/postgresql-security.sql) — general security examples
- [schema-usage-privilege.sql](Security/schema-usage-privilege.sql) — schema-level privileges
- [connect-rds-postgresql-with-iam-authentication.sql](Security/connect-rds-postgresql-with-iam-authentication.sql) — IAM authentication to RDS
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
- [major-upgrade.sql](Installation-Upgrade/major-upgrade.sql) — major version upgrade notes

## Conventions

File names use lowercase `kebab-case` with no spaces so they are friendly on
Linux/macOS shells and in URLs. Java files keep their original names to match
their public class names, and Python files use `snake_case` per Python
convention.

## License

Released under the [MIT License](LICENSE).
