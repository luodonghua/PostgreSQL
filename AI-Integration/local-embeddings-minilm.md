# Generating Text Embeddings Locally (MiniLM, no API key)

You do **not** need an OpenAI/Claude/Cohere subscription to generate embeddings.
A small sentence-transformer model runs on your own CPU, free and offline. This
guide uses **`all-MiniLM-L6-v2`** (384 dimensions, ~90 MB) with
[`sentence-transformers`](https://www.sbert.net/) and stores the vectors in
PostgreSQL via [pgvector](pgvector-installation.md).

Verified on Python 3.12 / PostgreSQL 18.6 / pgvector 0.8.7, CPU only.

> **Why MiniLM?** `all-MiniLM-L6-v2` is a widely used general-purpose embedding
> model: tiny, fast on CPU, and good enough for semantic search, clustering, and
> RAG prototyping. For higher quality you can later swap in a larger model
> (e.g. `all-mpnet-base-v2`, 768-dim, or a BGE/E5 model) — only the model name
> and the `vector(N)` dimension change.

---

## 1. Prerequisites

- pgvector installed and a database to use (see
  [pgvector-installation.md](pgvector-installation.md); this guide targets the
  `ai_demo` database).
- Python 3 with `venv`.
- Internet access **once** to download the model; afterwards it is cached under
  `~/.cache/huggingface` and runs offline.

---

## 2. Set up an isolated Python environment

Modern Debian/Ubuntu Python is "externally managed" (PEP 668), so install into a
**virtual environment**, not system pip:

```bash
cd AI-Integration
python3 -m venv .venv
. .venv/bin/activate
pip install --upgrade pip
pip install "sentence-transformers" "psycopg[binary]"
```

> **Do not commit the virtual environment.** `.venv/` is large (several GB, mostly
> PyTorch) and is already listed in this repo's `.gitignore`. Only the scripts and
> this doc are tracked — never the `.venv/` directory or the model cache.

---

## 3. Minimal example

```python
from sentence_transformers import SentenceTransformer

model = SentenceTransformer("all-MiniLM-L6-v2")   # downloads once, then cached
vec = model.encode("PostgreSQL vector search", normalize_embeddings=True)
print(len(vec))        # 384
```

`normalize_embeddings=True` makes the vectors unit-length, so **cosine** distance
(pgvector's `<=>`) is the right metric and `1 - (a <=> b)` is cosine similarity.

---

## 4. Store and query in pgvector

A runnable version of this is in
[`generate_embeddings.py`](generate_embeddings.py). The essentials:

```python
import psycopg
from sentence_transformers import SentenceTransformer

model = SentenceTransformer("all-MiniLM-L6-v2")
DIM = 384

def to_pgvector(v):                       # format as pgvector literal [x,y,z]
    return "[" + ",".join(f"{x:.6f}" for x in v) + "]"

docs = [
    "PostgreSQL is an open-source relational database.",
    "pgvector adds vector similarity search to Postgres.",
    "The cat sat on the mat.",
]
emb = model.encode(docs, normalize_embeddings=True)

with psycopg.connect("dbname=ai_demo") as conn:
    conn.execute("CREATE EXTENSION IF NOT EXISTS vector")
    conn.execute("DROP TABLE IF EXISTS doc_embeddings")
    conn.execute(f"CREATE TABLE doc_embeddings "
                 f"(id bigserial PRIMARY KEY, content text, embedding vector({DIM}))")
    with conn.cursor() as cur:
        for d, v in zip(docs, emb):
            cur.execute("INSERT INTO doc_embeddings (content, embedding) VALUES (%s, %s)",
                        (d, to_pgvector(v)))
    conn.commit()

    q = to_pgvector(model.encode("database vector search", normalize_embeddings=True))
    rows = conn.execute(
        "SELECT content, 1 - (embedding <=> %s) AS cosine_similarity "
        "FROM doc_embeddings ORDER BY embedding <=> %s LIMIT 3", (q, q)).fetchall()
    for content, sim in rows:
        print(f"{sim:.4f}  {content}")
```

Verified output — the query ranks the semantically related rows first, the
unrelated sentence last:

```
query: 'database vector search'
  0.5653  pgvector adds vector similarity search to Postgres.
  0.4218  PostgreSQL is an open-source relational database.
  0.0354  The cat sat on the mat.
```

That's semantic search with **zero external API calls**.

---

## 5. Run the included script

```bash
cd AI-Integration
. .venv/bin/activate
python generate_embeddings.py                       # default query
python generate_embeddings.py "how to store vectors in postgres"
```

---

## 6. Add an ANN index (HNSW / IVFFlat) for scale

The example uses an exact scan (fine for small tables). For many rows, add an
approximate-nearest-neighbor (ANN) index — pgvector's **HNSW** or **IVFFlat** —
so lookups stay fast. Match the index operator
class to your distance metric — cosine (`<=>`) → `vector_cosine_ops`:

```sql
-- HNSW: best recall/speed, slower to build, more memory
CREATE INDEX ON doc_embeddings USING hnsw (embedding vector_cosine_ops);

-- IVFFlat: faster build, needs data present first and a lists= choice
-- CREATE INDEX ON doc_embeddings USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);
```

Use `vector_l2_ops` with `<->` or `vector_ip_ops` with `<#>` if you switch
metrics. ANN indexes return *approximate* results — tune `hnsw.ef_search` /
IVFFlat `probes` for the recall you need.

---

## 7. Choosing a different model

| Model | Dim | Notes |
|-------|-----|-------|
| `all-MiniLM-L6-v2` | 384 | default here; fast, small, good baseline |
| `all-mpnet-base-v2` | 768 | higher quality, slower |
| `BAAI/bge-small-en-v1.5` | 384 | strong retrieval model |
| `intfloat/e5-small-v2` | 384 | strong retrieval; prefix inputs with `query:`/`passage:` |

Changing model ⇒ change the model name **and** the `vector(N)` column dimension
to match the new model's output size. Embeddings from different models are **not**
comparable — re-embed everything if you switch.

---

## Summary

1. Local embeddings need no subscription: `sentence-transformers` + MiniLM on CPU.
2. Install into a **venv** (PEP 668); never commit `.venv/` or the model cache
   (both are `.gitignore`d).
3. `normalize_embeddings=True` + pgvector's `<=>` = cosine similarity.
4. Store as `vector(384)`, query with `ORDER BY embedding <=> :q LIMIT k`.
5. Add an **HNSW/IVFFlat** index for large tables; match the opclass to the metric.
6. Swap models by changing the name and the `vector(N)` dimension.
