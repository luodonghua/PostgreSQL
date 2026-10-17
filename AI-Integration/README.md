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

<!--
Planned / future topics:
- mcp-server.md               — exposing PostgreSQL to AI agents via an MCP server
- aiops.md                    — LLM-assisted operations, monitoring, troubleshooting

Add entries above following the repo convention:
- [file-name.md](file-name.md) — short description
-->
