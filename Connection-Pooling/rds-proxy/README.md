# Amazon RDS Proxy

Managed connection pooler for Amazon RDS and Aurora. See the top-level
[pgbouncer-vs-rds-proxy.md](../pgbouncer-vs-rds-proxy.md) for how RDS Proxy
compares to PgBouncer.

## Contents

_Placeholder — setup scripts, IAM auth configuration, and failover notes will go
here._

Planned topics:

- Creating a proxy and target group (console / CLI / Terraform)
- Standard IAM auth (Secrets Manager) vs end-to-end IAM auth
- `MaxConnectionsPercent` and borrow-timeout tuning
- Monitoring pinning via the `DatabaseConnectionsCurrentlySessionPinned` CloudWatch metric
- Failover behavior and connection holding
