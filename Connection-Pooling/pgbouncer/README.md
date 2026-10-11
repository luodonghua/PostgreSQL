# PgBouncer

Lightweight self-hosted connection pooler for PostgreSQL. See the top-level
[pgbouncer-vs-rds-proxy.md](../pgbouncer-vs-rds-proxy.md) for how PgBouncer
compares to Amazon RDS Proxy.

## Contents

_Placeholder — pooling-mode notes and sample configuration will go here._

Planned topics:

- Deployment topology: sidecar (co-located per pod) vs centralized tier vs hybrid — see the tradeoff table in [../pgbouncer-vs-rds-proxy.md](../pgbouncer-vs-rds-proxy.md) §3.1
- Pooling modes: `session`, `transaction`, `statement`
- `pgbouncer.ini` and `userlist.txt` / `auth_query` setup
- Prepared statements in transaction mode (`max_prepared_statements`, 1.21+)
- Pool sizing (`default_pool_size`, `max_client_conn`, `reserve_pool_size`)
- High availability with multiple instances
