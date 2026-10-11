# Java / JDBC with PostgreSQL

Java and JDBC (pgjdbc) examples and experiments against PostgreSQL.

## Topics

- [jdbc-prepared-statement-plan-cache.md](jdbc-prepared-statement-plan-cache.md) — how pgjdbc's `prepareThreshold` interacts with the server's `plan_cache_mode` to choose custom vs generic plans; includes result tables and raw server logs in [`server-logs/`](server-logs/). Source: [`JdbcPreparedPlanCacheModeDemo.java`](JdbcPreparedPlanCacheModeDemo.java).

## Conventions

Each topic is its own descriptive `kebab-case.md` file. Supporting Java sources
keep their original class names (e.g. `JdbcPreparedPlanCacheModeDemo.java`) to
match their public class, and bulky raw output (server logs, EXPLAIN dumps) goes
in a per-topic subfolder such as [`server-logs/`](server-logs/).
