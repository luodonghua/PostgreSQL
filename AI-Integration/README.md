# AI Integration

PostgreSQL in AI workloads: vector similarity search and embeddings, retrieval-
augmented generation (RAG), serving Postgres data to AI tools (e.g. MCP
servers), and AIOps — using LLMs/automation to operate and troubleshoot
PostgreSQL.

## Contents

- [pgvector-installation.md](pgvector-installation.md) — installing the `pgvector` extension (Debian/Ubuntu, other platforms, managed services), enabling it per database, and a smoke test
- [local-embeddings-minilm.md](local-embeddings-minilm.md) — generating text embeddings locally with `sentence-transformers` (MiniLM) and storing/querying them in pgvector — no API key required ([generate_embeddings.py](generate_embeddings.py))
- [embeddings-explained.md](embeddings-explained.md) — what embeddings are, how pgvector stores/compares them, cross-model compatibility, `normalize_embeddings`, and cosine/L2/inner-product similarity
- [pgvector-indexes.md](pgvector-indexes.md) — HNSW & IVFFlat ANN indexes with animations, the recall-vs-speed balance, large-scale operation, and when to use which ([animations/](animations/README.md))
- [hybrid-search.md](hybrid-search.md) — combining pgvector with scalar (B-tree) filters and full-text (GIN) search; filtering-after-ANN-scan, iterative scans, partial indexes, and large-scale guidance

<!--
Planned / future topics:
- mcp-server.md               — exposing PostgreSQL to AI agents via an MCP server
- aiops.md                    — LLM-assisted operations, monitoring, troubleshooting

Add entries above following the repo convention:
- [file-name.md](file-name.md) — short description
-->
