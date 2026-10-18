# PostgreSQL

A collection of scripts, code snippets, and notes for working with PostgreSQL —
covering administration, performance, development, security, and running on
Amazon RDS.

## Contents

### Administration
Day-to-day operation and maintenance of a PostgreSQL server.

- [managing-postgresql.md](Administration/managing-postgresql.md) — common server management tasks
- [postgresql-monitoring.md](Administration/postgresql-monitoring.md) — monitoring queries (activity, locks, pg_stat_statements)
- [system-catalog.md](Administration/system-catalog.md) — querying the system catalogs
- [server-process-memory-with-pmap.md](Administration/server-process-memory-with-pmap.md) — inspecting backend memory with `pmap`

### Performance
Query planning and data-type choices that affect performance.

- [join-strategy-and-order.sql](Performance/join-strategy-and-order.sql) — how the planner chooses joins
- [use-right-data-type.md](Performance/use-right-data-type.md) — impact of data-type selection on storage and query performance
- [postgresql-as-queue-table.md](Performance/postgresql-as-queue-table.md) — PostgreSQL as a work queue with `FOR UPDATE SKIP LOCKED`: DELETE-on-claim vs UPDATE-to-processing (reaper, retries, dead-letter), their pros/cons, and when to choose each (verified concurrency tests)

### Maintenance
How PostgreSQL keeps tables healthy, explained from the source with animations.

- [vacuum.md](Maintenance/vacuum.md) — VACUUM: MVCC dead tuples, HOT pruning, the visibility map, the three phases (heap scan → index vacuum → heap reap), truncation; includes freezing and XID wraparound (`relfrozenxid`, anti-wraparound vacuum, failsafe)
- [analyze.md](Maintenance/analyze.md) — ANALYZE: fixed-size sampling (`300 × statistics_target`), two-stage block + Vitter reservoir sampling, and the `pg_statistic` it produces (MCV, histogram, `n_distinct`, correlation)
- [autovacuum.md](Maintenance/autovacuum.md) — autovacuum: launcher/worker model, how a database and then tables are chosen across the cluster (`threshold + scale_factor × reltuples`), score-based prioritization, and monitoring
- [parameters.md](Maintenance/parameters.md) — every vacuum/analyze/autovacuum setting grouped by role and how they interrelate, with tuning recipes
- [postgresql-maintenance.md](Maintenance/postgresql-maintenance.md) — routine maintenance commands (vacuum, analyze, reindex, bloat, pg_repack)
- [monitor-autovacuum.md](Maintenance/monitor-autovacuum.md) — tracking autovacuum behavior and XID wraparound in production
- Overview with animations: [Maintenance/README.md](Maintenance/README.md)

### Development
SQL and application-side examples for building on PostgreSQL.

**Queries** ([Queries/](Development/Queries/))
- [query-examples.md](Development/Queries/query-examples.md) — assorted query idioms with output (`format`, date parts, `NOT IN (NULL)`, three-valued logic, window functions)
- [keyset-pagination.md](Development/Queries/keyset-pagination.md) — keyset/seek pagination with row-value comparison `(last_modified_ts, id) < (?, ?)`: why it beats `OFFSET`, tie-safety, and measured `EXPLAIN` plans
- [autonomous-transactions.md](Development/Queries/autonomous-transactions.md) — autonomous transactions (audit-survives-rollback): the `dblink` loopback pattern, why `pg_background` isn't portable, and RDS/Aurora guidance
- [listen-notify.md](Development/Queries/listen-notify.md) — `LISTEN`/`NOTIFY` event-driven wakeups: transactional delivery, best-effort (missed if nobody's listening), duplicate folding, 8000-byte payload limit, the worker-wakeup pattern with a poll fallback, and RDS/Aurora (incl. Serverless) caveats

**Data types** ([DataTypes/](Development/DataTypes/))
- [timestamp-with-time-zone.md](Development/DataTypes/timestamp-with-time-zone.md) — `timestamp` vs `timestamptz` behavior
- [char-varchar-and-text-effects-on-trailing-space.md](Development/DataTypes/char-varchar-and-text-effects-on-trailing-space.md) — `char`/`varchar`/`text` trailing-space differences
- [create-table-with-oids.md](Development/DataTypes/create-table-with-oids.md) — legacy `WITH OIDS` tables
- [table-size-estimation.md](Development/DataTypes/table-size-estimation.md) — estimating table size from page layout

**JSONB** ([JSONB/](Development/JSONB/))
- [hybrid-jsonb-banking.md](Development/JSONB/hybrid-jsonb-banking.md) / [hybrid-jsonb-banking.sql](Development/JSONB/hybrid-jsonb-banking.sql) — hybrid JSONB + relational design (banking): keep hot fields (balance) relational, reserve JSONB for stable data; measured ~6× WAL reduction
- [jsonb-wal-internals.md](Development/JSONB/jsonb-wal-internals.md) — what PostgreSQL writes to the WAL on `UPDATE`, with real `pg_walinspect`-decoded records for inline JSONB, TOAST pointer reuse, and TOAST rewrite cascades

**Partitioning** ([Partitioning/](Development/Partitioning/))
- [partition-example.md](Development/Partitioning/partition-example.md) — table partitioning, sub-partitioning, attach/detach, and the cost of deep nesting
- [create-1000-sub-partition.sql](Development/Partitioning/create-1000-sub-partition.sql) — generated DDL for a 1000-partition / 1000-level setup (runnable script)

**Indexes** ([Indexes/](Development/Indexes/))
- [btree.md](Development/Indexes/btree.md) — B-tree (default): balanced ordered tree, high-key/right-link concurrency, splits, dedup, ordered scans
- [hash.md](Development/Indexes/hash.md) — Hash (equality-only): value→bucket, overflow pages, bucket splits, stores only the hash code
- [brin.md](Development/Indexes/brin.md) — BRIN (Block Range Index): per-range min/max summaries, revmap, lossy bitmap scan, correlation dependence
- [gin.md](Development/Indexes/gin.md) — GIN (Generalized Inverted Index): inverted structure, posting lists/trees, varbyte compression, `fastupdate` pending list
- [gist.md](Development/Indexes/gist.md) — GiST (Generalized Search Tree): bounding-predicate tree, opclass support functions, KNN, NSN/right-link concurrency, buffering build
- [spgist.md](Development/Indexes/spgist.md) — SP-GiST (Space-Partitioned GiST): quadtree/k-d/radix tries, inner/leaf tuples, redirect tuples, triple-parity concurrency
- [index-comparison.md](Development/Indexes/index-comparison.md) — B-tree vs Hash vs BRIN vs GIN vs GiST vs SP-GiST comparison and decision guide (with animations)

**Other**
- [UUIDv7/](Development/UUIDv7/) — UUIDv7 generation and partition migration ([details](Development/UUIDv7/README.md))
- [SampleSchema/](Development/SampleSchema/) — sports-ticketing sample database ([details](Development/SampleSchema/README.md))
- [Python/](Development/Python/) — parallel load/copy and SQLAlchemy examples
- [Java/](Development/Java/) — JDBC examples ([index](Development/Java/README.md)); incl. [prepared-statement plan-cache demo](Development/Java/jdbc-prepared-statement-plan-cache.md)
- [datasets/](Development/datasets/) — sample datasets and their loader scripts ([load-data-t-oil.sql](Development/datasets/load-data-t-oil.sql), [load-data-daily-equity-volumes.sql](Development/datasets/load-data-daily-equity-volumes.sql), [query-daily-equity-volumes.sql](Development/datasets/query-daily-equity-volumes.sql))

### AI-Integration
PostgreSQL in AI workloads: vector similarity search, embeddings, and production embedding pipelines.

- [pgvector-installation.md](AI-Integration/pgvector-installation.md) — installing the `pgvector` extension (Debian/Ubuntu, other platforms, managed services), enabling it per database, and a smoke test
- [embeddings-explained.md](AI-Integration/embeddings-explained.md) — what embeddings are, how pgvector stores/compares them, cross-model compatibility, `normalize_embeddings`, and cosine/L2/inner-product similarity
- [local-embeddings-minilm.md](AI-Integration/local-embeddings-minilm.md) — generating embeddings locally with `sentence-transformers` (MiniLM), a smoke test with verified output, and storing/querying in pgvector — no API key ([generate_embeddings.py](AI-Integration/generate_embeddings.py))
- [pgvector-indexes.md](AI-Integration/pgvector-indexes.md) — ANN index overview & comparison: distance metrics, HNSW-vs-IVFFlat, recall-vs-speed, data modeling, transactional updates, and batch-processing-vs-batch-embedding (OpenAI vs Bedrock Titan) ([animations/](AI-Integration/animations/README.md))
- [pgvector-hnsw.md](AI-Integration/pgvector-hnsw.md) — HNSW deep dive: graph internals, `m` / `ef_construction` / `ef_search`, build & query tuning ([demo-hnsw.sql](AI-Integration/demo-hnsw.sql))
- [pgvector-ivfflat.md](AI-Integration/pgvector-ivfflat.md) — IVFFlat deep dive: k-means lists, `lists` / `probes`, build-after-data, measured recall ([demo-ivfflat.sql](AI-Integration/demo-ivfflat.sql))
- [hybrid-search.md](AI-Integration/hybrid-search.md) — combining pgvector with scalar (B-tree) filters and full-text (GIN) search; filter-after-ANN, partial indexes, and Reciprocal Rank Fusion (RRF)
- [embedding-pipeline-patterns.md](AI-Integration/embedding-pipeline-patterns.md) — production-grade async embedding pipeline on our `documents` → `embedding_queue` → `doc_embeddings` flow: two clocks (transactional vs semantic), enqueue-don't-embed, a worker with scheduled retry (`attempts`/`next_run_at`/backoff) over `FOR UPDATE SKIP LOCKED`, content-hash skip of unchanged re-embeds, re-enqueue on referenced-row change, `LISTEN/NOTIFY` vs polling, a `(query_text, model_id)` query cache with TTL, and `model_id` versioning ([generate_embeddings_with_retries.py](AI-Integration/generate_embeddings_with_retries.py), [generate_embeddings_batched.py](AI-Integration/generate_embeddings_batched.py))
- [postgres-tooling-checklist.md](AI-Integration/postgres-tooling-checklist.md) — vendor-neutral checklist for choosing & operating PostgreSQL tools (migration, tuning, operational/AI & MCP): privilege/locus classification, least-privilege read-only roles, row caps + `statement_timeout`, dynamic-SQL validation, query-views-not-tables, prompt-injection defense, observability logging, and external-API/secrets/egress hygiene
- Overview: [AI-Integration/README.md](AI-Integration/README.md)

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
