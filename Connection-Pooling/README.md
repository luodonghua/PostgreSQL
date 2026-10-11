# Connection Pooling

Notes and examples on connection pooling for PostgreSQL — why it's needed, the
main options (self-hosted PgBouncer, managed Amazon RDS Proxy, and
application-framework pools), and how to choose between them.

PostgreSQL forks one backend process per connection, so `max_connections` is a
hard ceiling. Serverless and scaled-out applications exhaust it quickly
(`FATAL: sorry, too many clients already`). A pooler multiplexes many client
connections onto a small set of backend connections to avoid this.

## Contents

- [pgbouncer-vs-rds-proxy.md](pgbouncer-vs-rds-proxy.md) — detailed comparison of PgBouncer vs Amazon RDS Proxy: differences, when to choose each, and what you gain/lose migrating between them (with diagrams)
- [rds-proxy/](rds-proxy/) — Amazon RDS Proxy setup, IAM auth, and failover notes ([details](rds-proxy/README.md))
- [pgbouncer/](pgbouncer/) — PgBouncer pooling modes (session/transaction/statement) and configuration ([details](pgbouncer/README.md))
- [application-framework/](application-framework/) — application-side pools (HikariCP, SQLAlchemy, pgx, node-pg, Npgsql) ([details](application-framework/README.md))
- [lock-contention-pool-exhaustion.md](lock-contention-pool-exhaustion.md) — playbook for when a long batch job's row locks block OLTP and drain the application connection pool

## Conventions

File names use lowercase `kebab-case` with no spaces, matching the rest of this
repository.
