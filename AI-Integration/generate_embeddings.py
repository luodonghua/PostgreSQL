#!/usr/bin/env python3
"""
generate_embeddings.py — generate text embeddings locally with sentence-transformers
(MiniLM) and store/query them in PostgreSQL via pgvector.

No API key or subscription required. The model (~90 MB) is downloaded from the
Hugging Face Hub on first run and cached under ~/.cache/huggingface; every run
after that is fully offline.

Setup (see local-embeddings-minilm.md):
    python3 -m venv .venv
    . .venv/bin/activate
    pip install "sentence-transformers" "psycopg[binary]"

Run:
    python generate_embeddings.py              # uses dbname=ai_demo
"""
import sys
from sentence_transformers import SentenceTransformer
import psycopg

MODEL_NAME = "all-MiniLM-L6-v2"   # 384-dim, CPU-friendly, ~90 MB
DIM = 384
DSN = "dbname=ai_demo"            # adjust as needed, e.g. "host=... user=... dbname=..."


def to_pgvector(vec) -> str:
    """Format a numeric sequence as a pgvector literal: [x,y,z]."""
    return "[" + ",".join(f"{x:.6f}" for x in vec) + "]"


def main() -> None:
    model = SentenceTransformer(MODEL_NAME)
    assert model.get_embedding_dimension() == DIM

    documents = [
        "PostgreSQL is an open-source relational database.",
        "pgvector adds vector similarity search to Postgres.",
        "The cat sat on the mat.",
    ]
    # normalize so that cosine distance (<=>) is meaningful
    embeddings = model.encode(documents, normalize_embeddings=True)

    with psycopg.connect(DSN) as conn:
        conn.execute("CREATE EXTENSION IF NOT EXISTS vector")
        conn.execute("DROP TABLE IF EXISTS doc_embeddings")
        conn.execute(
            f"CREATE TABLE doc_embeddings "
            f"(id bigserial PRIMARY KEY, content text, embedding vector({DIM}))"
        )
        with conn.cursor() as cur:
            for content, vec in zip(documents, embeddings):
                cur.execute(
                    "INSERT INTO doc_embeddings (content, embedding) VALUES (%s, %s)",
                    (content, to_pgvector(vec)),
                )
        conn.commit()

        query = sys.argv[1] if len(sys.argv) > 1 else "database vector search"
        qvec = to_pgvector(model.encode(query, normalize_embeddings=True))
        rows = conn.execute(
            "SELECT content, 1 - (embedding <=> %s) AS cosine_similarity "
            "FROM doc_embeddings ORDER BY embedding <=> %s LIMIT 5",
            (qvec, qvec),
        ).fetchall()

        print(f"\nquery: {query!r}")
        for content, sim in rows:
            print(f"  {sim:.4f}  {content}")


if __name__ == "__main__":
    main()
