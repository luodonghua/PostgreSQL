# AI Integration

PostgreSQL in AI workloads: vector similarity search and embeddings, retrieval-
augmented generation (RAG), serving Postgres data to AI tools (e.g. MCP
servers), and AIOps — using LLMs/automation to operate and troubleshoot
PostgreSQL.

## Contents

- [pgvector-installation.md](pgvector-installation.md) — installing the `pgvector` extension (Debian/Ubuntu, other platforms, managed services), enabling it per database, and a smoke test
- [local-embeddings-minilm.md](local-embeddings-minilm.md) — generating text embeddings locally with `sentence-transformers` (MiniLM) and storing/querying them in pgvector — no API key required ([generate_embeddings.py](generate_embeddings.py))
- [embeddings-explained.md](embeddings-explained.md) — what embeddings are, how pgvector stores/compares them, cross-model compatibility, `normalize_embeddings`, and cosine/L2/inner-product similarity
- [pgvector-indexes.md](pgvector-indexes.md) — ANN index **overview & comparison**: distance-metric rulers, HNSW-vs-IVFFlat and when to use which, recall-vs-speed, **data modeling** (vector column vs separate PK-joined table), and **transactional updates without slowing OLTP** ([animations/](animations/README.md))
- [pgvector-hnsw.md](pgvector-hnsw.md) — HNSW deep dive: graph internals, `m` / `ef_construction` / `ef_search`, build & query tuning, large-scale operation ([demo-hnsw.sql](demo-hnsw.sql))
- [pgvector-ivfflat.md](pgvector-ivfflat.md) — IVFFlat deep dive: k-means lists, `lists` / `probes`, build-after-data, measured recall, large-scale operation ([demo-ivfflat.sql](demo-ivfflat.sql))
- [hybrid-search.md](hybrid-search.md) — combining pgvector with scalar (B-tree) filters and full-text (GIN) search; filtering-after-ANN-scan, iterative scans, partial indexes, **Reciprocal Rank Fusion (RRF)** for blending semantic + lexical relevance, and large-scale guidance
- [embedding-pipeline-patterns.md](embedding-pipeline-patterns.md) — **production-grade** async embedding pipeline built on our `documents` → `embedding_queue` → `doc_embeddings` flow: two clocks (transactional vs semantic), enqueue-don't-embed, a worker with scheduled retry (`attempts`/`next_run_at`/backoff) over `FOR UPDATE SKIP LOCKED`, content-hash skip of unchanged re-embeds, re-enqueue on referenced-row change, `LISTEN/NOTIFY` vs polling, a `(query_text, model_id)` query cache with TTL, and `model_id` versioning (verified on PG 18.6 + pgvector 0.8.7)
- [postgres-tooling-checklist.md](postgres-tooling-checklist.md) — a vendor-neutral checklist for **choosing & operating** PostgreSQL tools (migration, tuning, operational/AI & MCP): privilege + locus classification, least-privilege read-only roles, row caps + `statement_timeout`, dynamic-SQL validation, query-views-not-tables, prompt-injection defense, observability logging, and external-API/secrets/egress hygiene (incl. why in-DB model calls are limited on RDS/Aurora)

<!--
Planned / future topics:
- mcp-server.md               — exposing PostgreSQL to AI agents via an MCP server
- aiops.md                    — LLM-assisted operations, monitoring, troubleshooting

Add entries above following the repo convention:
- [file-name.md](file-name.md) — short description
-->
