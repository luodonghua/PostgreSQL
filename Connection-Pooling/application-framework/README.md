# Application-Framework Connection Pools

Client-side connection pools built into application frameworks and drivers
(HikariCP, SQLAlchemy, `pgx`, `node-pg`, Npgsql). These complement — and
sometimes conflict with — a server-side pooler (PgBouncer or RDS Proxy).

For how these pools interact with RDS Proxy pinning, see
[../pgbouncer-vs-rds-proxy.md §2.6](../pgbouncer-vs-rds-proxy.md#26-pinning--application-side-connection-pools-the-dangerous-combination).

## The core principle: don't fight the server-side pooler

An application pool keeps connections **open and idle for reuse**. A
transaction-mode pooler (PgBouncer transaction mode, or RDS Proxy) wants
connections **released between transactions** so a backend can be reused by
another client.

Two rules keep them compatible:

1. **Pooled connections must be pin-free / stateless.** No session `SET`s run on
   checkout, no driver-level named prepared statements, no session-lifetime temp
   tables. If a pooled connection trips a pin trigger, RDS Proxy pins the backend
   and — because the app pool never closes the connection — the pin never
   releases.
2. **Right-size the local pool; don't over-provision it.** Let the server-side
   pooler do the fan-in. Size the application pool to the instance's real request
   concurrency (small, but not so small that threads block on `connectionTimeout`
   — see the HikariCP sizing note below), and give connections a finite lifetime
   so any accidental pin eventually rotates out.

The two biggest pin/break triggers to control at the framework level are:

- **`SET` statements run on connection setup/checkout** → move them to the proxy
  **initialization query** (RDS Proxy) or `server_reset_query` / app-side removal
  (PgBouncer), so the pool itself issues none.
- **Driver auto-prepared (named) statements** → disable them for transaction-mode
  poolers. PgBouncer transaction mode does not track client prepared statements
  by default (pre-1.21), and on RDS Proxy a named prepared statement pins the
  session on PostgreSQL.

## Quick reference — disable named prepared statements per driver

| Stack | Setting to avoid pinning / breakage | Notes |
|---|---|---|
| **Java / pgjdbc + HikariCP** | `prepareThreshold=0` (JDBC URL or datasource prop) | Disables server-side prepared statements. Also avoid `connectionInitSql` with `SET`s. |
| **Python / psycopg3** | `prepare_threshold=None` | psycopg3 **auto-prepares by default** — the classic footgun under transaction pooling. |
| **Python / asyncpg** (incl. SQLAlchemy async) | `statement_cache_size=0` | Also disable prepared-statement name reuse; SQLAlchemy passes this via `connect_args`. |
| **Go / pgx** | `QueryExecModeSimpleProtocol` (or avoid `QueryExecModeCacheStatement`) | Do not use explicit prepared statements; `Deallocate` is a SQL query the pooler won't track. |
| **Node.js / node-pg** | Don't pass a `name` to queries | node-pg only creates named prepared statements when you give the query a `name`. |
| **.NET / Npgsql** | `Max Auto Prepare=0` (the default) and avoid `NpgsqlCommand.Prepare()` | Npgsql auto-prepare is **off by default**, so the risk is enabling it or calling `.Prepare()` explicitly. |

## HikariCP (Java)

```properties
# JDBC URL — disable server-side prepared statements for transaction pooling
jdbc:postgresql://proxy-endpoint:5432/app?prepareThreshold=0

# HikariCP config
maximumPoolSize=10          # see sizing note below — NOT a universal value
minimumIdle=10              # tip: set == maximumPoolSize for a fixed-size pool
connectionTimeout=30000     # ms a thread waits for a free conn before failing
maxLifetime=600000          # 10 min — ensure accidental pins eventually rotate out
idleTimeout=120000
# DO NOT use connectionInitSql to run `SET ...` — that pins every pooled
# connection on RDS Proxy. Move those settings to the proxy init query instead.
# connectionInitSql=SET search_path=app   <-- avoid
```

### Sizing the pool (important — don't just copy `10`)

`maximumPoolSize` must match **this app instance's real concurrency**, not the
database's capacity. The pool is deliberately *small* (small pools improve DB
throughput — see HikariCP's sizing guide), but **too small** means application
threads block waiting for a connection and you get latency/timeouts *even when
the database and proxy have spare capacity*. That is an application-side
bottleneck, not a database one.

What actually happens when the pool is exhausted (all connections busy):

- A thread requesting a connection **blocks for up to `connectionTimeout`** (default 30 s).
- If none frees up in time, HikariCP throws `SQLTransientConnectionException: ... connection is not available, request timed out`.
- The app does **not** silently open more connections — `maximumPoolSize` is a hard cap.

So size it from load, not from a round number. HikariCP's rule of thumb for a
CPU/IO-bound DB workload:

```
pool size ≈ (CPU cores × 2) + effective_spindle_count
```

More practically, size to **peak concurrent in-flight queries per instance**,
then validate against metrics:

- Watch HikariCP's `hikaricp_connections_pending` (threads waiting) and `connectionTimeout` exceptions. If pending > 0 under normal load, the pool is too small — raise it.
- Remember the fan-in math across the fleet: `instances × maximumPoolSize` must stay well under the database's `max_connections` (and, with RDS Proxy, under `MaxConnectionsPercent`). A pooler helps here, but only if pooled connections stay pin-free (see §2.6 of the comparison guide).
- If you need more app-side concurrency than the DB can back, that is exactly the signal to put a server-side pooler (RDS Proxy / PgBouncer) in front — raise the *app* pool to serve request concurrency and let the pooler fan many app connections into a smaller backend set.

If you genuinely need a per-connection setting, prefer putting it in the RDS
Proxy initialization query (uniform for all backends) rather than
`connectionInitSql`.

## SQLAlchemy (Python)

```python
from sqlalchemy import create_engine

# psycopg3 (sync): disable auto-prepared statements
engine = create_engine(
    "postgresql+psycopg://app@proxy-endpoint:5432/app",
    connect_args={"prepare_threshold": None},
    pool_size=5,            # size to instance concurrency (see HikariCP sizing note)
    max_overflow=5,
    pool_recycle=600,       # recycle so stray pins release
    pool_pre_ping=True,
)

# asyncpg (async): disable the statement cache
# create_async_engine(
#     "postgresql+asyncpg://app@proxy-endpoint:5432/app",
#     connect_args={"statement_cache_size": 0},
# )
```

Avoid running `SET` in a `connect`/`checkout` event listener — that is the
SQLAlchemy equivalent of HikariCP `connectionInitSql` and will pin.

## pgx (Go)

```go
cfg, _ := pgxpool.ParseConfig("postgres://app@proxy-endpoint:5432/app")

// Use the simple protocol so pgx doesn't auto-prepare named statements.
cfg.ConnConfig.DefaultQueryExecMode = pgx.QueryExecModeSimpleProtocol

cfg.MaxConns = 10          // size to instance concurrency (see HikariCP sizing note)
cfg.MaxConnLifetime = 10 * time.Minute

pool, _ := pgxpool.NewWithConfig(ctx, cfg)
```

Do not use `QueryExecModeCacheStatement` behind a transaction-mode pooler, and
avoid explicit `conn.Prepare(...)` — pgx's `Deallocate` is a SQL statement the
pooler can't intercept.

## node-pg (Node.js)

```js
const { Pool } = require('pg');

const pool = new Pool({
  connectionString: 'postgres://app@proxy-endpoint:5432/app',
  max: 10,                       // size to instance concurrency (see HikariCP sizing note)
  idleTimeoutMillis: 30000,
  maxLifetimeSeconds: 600,       // recycle connections
});

// Safe: unnamed query → no server-side prepared statement, no pin.
await pool.query('SELECT * FROM orders WHERE id = $1', [id]);

// Avoid: a `name` creates a named prepared statement that pins on RDS Proxy.
// await pool.query({ name: 'get_order', text: '...', values: [id] });
```

## Npgsql (.NET)

Npgsql is the standard ADO.NET provider for PostgreSQL and has its own built-in
connection pool (enabled by default; `NpgsqlDataSource` is the modern entry
point). Unlike psycopg3, **automatic prepared statements are off by default**
(`Max Auto Prepare=0`), so the main things to control are not enabling them, not
calling `.Prepare()`, and not running `SET`s on each connection.

```csharp
using Npgsql;

var connString = new NpgsqlConnectionStringBuilder
{
    Host = "proxy-endpoint",
    Port = 5432,
    Database = "app",
    Username = "app",

    // Pooling: size to instance concurrency (see HikariCP sizing note).
    Pooling = true,
    MaxPoolSize = 10,
    MinPoolSize = 0,

    // Recycle connections so an accidental pin eventually releases.
    ConnectionIdleLifetime = 120,   // seconds idle before pruning
    ConnectionLifetime = 600,       // max total lifetime (seconds)

    // Leave auto-prepare OFF (default) for transaction-mode poolers / RDS Proxy.
    MaxAutoPrepare = 0,
}.ToString();

await using var dataSource = NpgsqlDataSource.Create(connString);

// Safe: an unprepared command → no server-side prepared statement, no pin.
await using var cmd = dataSource.CreateCommand("SELECT * FROM orders WHERE id = $1");
cmd.Parameters.AddWithValue(id);
await using var reader = await cmd.ExecuteReaderAsync();

// Avoid: cmd.Prepare() / cmd.PrepareAsync() creates a server-side prepared
// statement that pins the session on RDS Proxy (PostgreSQL).
```

Do not run `SET`s via an `NpgsqlDataSourceBuilder` connection-init callback (the
.NET equivalent of HikariCP `connectionInitSql`); move those into the RDS Proxy
initialization query instead. If you must set per-connection state, be aware it
pins.

## Verifying it works

- **RDS Proxy:** watch the CloudWatch metric `DatabaseConnectionsCurrentlySessionPinned`. If it rises to roughly your app-pool size, your pooled connections are pinning — revisit the settings above.
- **PgBouncer:** check `SHOW POOLS;` / `SHOW STATS;` on the PgBouncer admin console; a healthy transaction-mode pool shows far fewer server connections than client connections.
