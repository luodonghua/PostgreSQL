#!/usr/bin/env python3
"""
generate_embeddings_batched.py — demonstrate TRUE batch embedding vs. per-row.

A very common confusion: "batch processing" (bounded rows per run — e.g. a SQL
LIMIT N loop that calls an embed function once per row) is NOT the same as "batch
embedding" (one model/API call that embeds MANY texts at once). The first controls
*how many rows you attempt per run*; the second controls *how many texts ride in a
single call* — and only the second cuts round-trips and per-call overhead.

This script makes the difference concrete and measurable:

  * PER-ROW   : call model.encode(text) once per row in a Python loop   (N calls)
  * BATCHED   : call model.encode([t1..tN]) ONCE for all rows           (1 call)

Both produce identical vectors; the batched path is several times faster on CPU
and would be the difference between 1 and N HTTP requests against a hosted API.

Setup (see local-embeddings-minilm.md):
    python3 -m venv .venv && . .venv/bin/activate
    pip install "sentence-transformers" "psycopg[binary]" numpy

Run:
    python generate_embeddings_batched.py            # 200 synthetic rows, dbname=ai_demo
    python generate_embeddings_batched.py 1000        # N rows
"""
import os
import sys
import time

import numpy as np
import psycopg
from sentence_transformers import SentenceTransformer

MODEL_NAME = "all-MiniLM-L6-v2"
DIM = 384
DSN = os.environ.get("PG_DSN", "dbname=ai_demo")
ENCODE_BATCH = 64     # how many texts the model processes per forward pass


def to_pgvector(vec) -> str:
    return "[" + ",".join(f"{x:.6f}" for x in vec) + "]"


def embed_per_row(model, texts):
    """The 'book' shape: one call per row (what a LIMIT-N loop does). N calls."""
    return [model.encode(t, normalize_embeddings=True) for t in texts]


def embed_batched(model, texts):
    """TRUE batch embedding: ONE call carries all texts, returns all vectors."""
    return model.encode(texts, normalize_embeddings=True, batch_size=ENCODE_BATCH)


def store_batched(conn, ids, vecs):
    """ONE multi-row upsert for the whole batch (one txn, one round-trip to DB)."""
    with conn.cursor() as cur:
        cur.executemany(
            "INSERT INTO doc_embeddings (id, content, embedding) "
            "VALUES (%s, %s, %s) "
            "ON CONFLICT (id) DO UPDATE SET embedding = EXCLUDED.embedding",
            [(i, f"row-{i}", to_pgvector(v)) for i, v in zip(ids, vecs)],
        )
    conn.commit()


def main() -> None:
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 200
    model = SentenceTransformer(MODEL_NAME)
    assert model.get_embedding_dimension() == DIM

    # synthetic corpus
    ids = list(range(1, n + 1))
    texts = [f"Product number {i} is a useful item with a short description." for i in ids]

    model.encode(["warmup"], normalize_embeddings=True)  # exclude one-time warmup from timings

    # ---- PER-ROW: N separate calls ----
    t0 = time.perf_counter()
    per_row = np.array(embed_per_row(model, texts))
    t_row = time.perf_counter() - t0

    # ---- BATCHED: ONE call for all N ----
    t0 = time.perf_counter()
    batched = np.array(embed_batched(model, texts))
    t_batch = time.perf_counter() - t0

    same = np.allclose(per_row, batched, atol=1e-5)
    print(f"\nrows                : {n}")
    print(f"per-row ({n} calls) : {t_row:.3f}s   ({n / t_row:.0f} rows/s)")
    print(f"batched (1 call)    : {t_batch:.3f}s   ({n / t_batch:.0f} rows/s)")
    print(f"speedup             : {t_row / t_batch:.1f}x")
    print(f"identical vectors   : {same}   <-- same result, far fewer calls")

    # store the batched result (the production path: 1 encode call + 1 multi-row upsert)
    with psycopg.connect(DSN) as conn:
        conn.execute("CREATE EXTENSION IF NOT EXISTS vector")
        conn.execute(
            f"CREATE TABLE IF NOT EXISTS doc_embeddings "
            f"(id bigint PRIMARY KEY, content text, embedding vector({DIM}))"
        )
        conn.commit()
        store_batched(conn, ids, batched)
        stored = conn.execute("SELECT count(*) FROM doc_embeddings").fetchone()[0]
        print(f"stored (upserted)   : {stored} rows in one multi-row UPSERT\n")


if __name__ == "__main__":
    main()
