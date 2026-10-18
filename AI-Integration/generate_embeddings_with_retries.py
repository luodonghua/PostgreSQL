#!/usr/bin/env python3
"""
generate_embeddings_with_retries.py — a retry-hardened version of
generate_embeddings.py.

Same job (embed text locally with MiniLM, store/query in pgvector), but with the
operational hygiene a real pipeline needs. At scale, conditions that are *normal*
in distributed systems will happen:

  * temporary network glitches        (first-run model download from HF Hub)
  * short-lived service hiccups       (DB restart/failover, PgBouncer recycle)
  * brief contention                  (lock timeouts, serialization failures)
  * transient 5xx-style errors         (if you swap in a hosted embedding API)

The goal is NOT more complexity — it's fewer failed runs, fewer reruns, and fewer
half-populated embedding tables. So we wrap the operations that can *transiently*
fail (model load, DB connect, DB writes) in a small reusable retry with
exponential backoff + jitter, retrying ONLY on transient error classes and failing
fast on everything else.

Note on scope: the local MiniLM model makes no network call at encode time, so the
expensive-API retry logic from the book (OpenAI 429/5xx + Retry-After) does not
apply to `model.encode()`. It DOES apply to (a) the one-time model download and
(b) every database operation. If you call a hosted API instead, see
`embed_via_openai_with_retries()` at the bottom — the same backoff shape adapted to
HTTP, mirroring the book's `api.openai_embed`.

Setup (see local-embeddings-minilm.md):
    python3 -m venv .venv
    . .venv/bin/activate
    pip install "sentence-transformers" "psycopg[binary]"

Run:
    python generate_embeddings_with_retries.py              # uses dbname=ai_demo
    python generate_embeddings_with_retries.py "your query"
"""
import os
import sys
import time
import random
import logging
from functools import wraps

import psycopg
from sentence_transformers import SentenceTransformer

MODEL_NAME = "all-MiniLM-L6-v2"   # 384-dim, CPU-friendly, ~90 MB
DIM = 384
DSN = os.environ.get("PG_DSN", "dbname=ai_demo")  # override via env, e.g. PG_DSN="host=... dbname=..."

MAX_ATTEMPTS = 6                  # total tries per operation (1 + 5 retries)
BASE_DELAY = 0.5                  # seconds; backoff is BASE_DELAY * 2**attempt
MAX_DELAY = 30.0                  # cap any single sleep

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("embeddings")


# --------------------------------------------------------------------------- #
# Reusable retry with exponential backoff + jitter.
#
# Retries ONLY on the exception types passed in `transient` (so a bug or a bad
# query fails fast instead of being retried 6 times). Backoff is exponential with
# full jitter — the jitter spreads out retries from many workers so they don't
# reconverge into a thundering herd after a shared outage.
# --------------------------------------------------------------------------- #
def with_retries(transient, *, attempts=MAX_ATTEMPTS, base=BASE_DELAY, cap=MAX_DELAY):
    def decorator(fn):
        @wraps(fn)
        def wrapper(*args, **kwargs):
            for i in range(attempts):
                try:
                    return fn(*args, **kwargs)
                except transient as exc:
                    if i == attempts - 1:
                        log.error("%s failed after %d attempts: %s", fn.__name__, attempts, exc)
                        raise
                    sleep_s = min(cap, base * (2 ** i)) + random.uniform(0, base)
                    log.warning(
                        "%s transient failure (attempt %d/%d): %s — retrying in %.2fs",
                        fn.__name__, i + 1, attempts, exc, sleep_s,
                    )
                    time.sleep(sleep_s)
        return wrapper
    return decorator


# Transient DB errors worth retrying: connection loss/restart, lock timeouts,
# serialization/deadlock on commit. A ProgrammingError (bad SQL) is NOT here —
# retrying it would just waste 6 attempts.
TRANSIENT_DB = (
    psycopg.OperationalError,        # connection reset, server restart, timeout
    psycopg.errors.SerializationFailure,
    psycopg.errors.DeadlockDetected,
    psycopg.errors.LockNotAvailable,
)

# The first-run model download hits the network; after that it's cached offline.
# urllib/requests/OS errors surface as OSError subclasses — retry those.
TRANSIENT_DOWNLOAD = (OSError,)


def to_pgvector(vec) -> str:
    """Format a numeric sequence as a pgvector literal: [x,y,z]."""
    return "[" + ",".join(f"{x:.6f}" for x in vec) + "]"


@with_retries(TRANSIENT_DOWNLOAD)
def load_model() -> SentenceTransformer:
    """Load (download on first run) the embedding model, retrying network blips."""
    log.info("loading model %s", MODEL_NAME)
    return SentenceTransformer(MODEL_NAME)


@with_retries(TRANSIENT_DB)
def setup_schema(conn) -> None:
    """Create the extension/table. Idempotent, so safe to retry."""
    conn.execute("CREATE EXTENSION IF NOT EXISTS vector")
    conn.execute(
        f"CREATE TABLE IF NOT EXISTS doc_embeddings "
        f"(id bigserial PRIMARY KEY, content text UNIQUE, embedding vector({DIM}))"
    )
    conn.commit()


@with_retries(TRANSIENT_DB)
def upsert_batch(conn, rows) -> None:
    """Idempotent upsert of (content, vector) pairs in ONE transaction.

    Idempotency is what makes retry safe: if a commit fails transiently and we
    re-run, ON CONFLICT means we overwrite rather than duplicate — no
    half-populated table, no double rows.
    """
    try:
        with conn.cursor() as cur:
            cur.executemany(
                "INSERT INTO doc_embeddings (content, embedding) VALUES (%s, %s) "
                "ON CONFLICT (content) DO UPDATE SET embedding = EXCLUDED.embedding",
                [(content, to_pgvector(vec)) for content, vec in rows],
            )
        conn.commit()
    except Exception:
        conn.rollback()   # leave the txn clean so a retry can start fresh
        raise


@with_retries(TRANSIENT_DB)
def search(conn, qvec, k=5):
    rows = conn.execute(
        "SELECT content, 1 - (embedding <=> %s) AS cosine_similarity "
        "FROM doc_embeddings ORDER BY embedding <=> %s LIMIT %s",
        (qvec, qvec, k),
    ).fetchall()
    return rows


@with_retries(TRANSIENT_DB)
def connect(dsn):
    """Open a connection, retrying if the server is briefly unreachable."""
    return psycopg.connect(dsn)


def main() -> None:
    model = load_model()
    assert model.get_embedding_dimension() == DIM

    documents = [
        "PostgreSQL is an open-source relational database.",
        "pgvector adds vector similarity search to Postgres.",
        "The cat sat on the mat.",
    ]
    # encode is local/CPU — no network, so no retry needed here
    embeddings = model.encode(documents, normalize_embeddings=True)

    conn = connect(DSN)
    try:
        setup_schema(conn)
        upsert_batch(conn, list(zip(documents, embeddings)))

        query = sys.argv[1] if len(sys.argv) > 1 else "database vector search"
        qvec = to_pgvector(model.encode(query, normalize_embeddings=True))
        rows = search(conn, qvec)

        print(f"\nquery: {query!r}")
        for content, sim in rows:
            print(f"  {sim:.4f}  {content}")
    finally:
        conn.close()


# --------------------------------------------------------------------------- #
# OPTIONAL: hosted-API variant (the book's scenario).
#
# If you embed via a hosted API instead of local MiniLM, the slow network call is
# where transient failures live — the same place the book hardens `api.openai_embed`.
# This mirrors that logic in Python: retry only on 429 / 5xx, honor `Retry-After`
# when present, exponential backoff + jitter otherwise. Not used by main(); shown
# so the pattern transfers directly if you switch to OpenAI/Cohere/etc.
# --------------------------------------------------------------------------- #
def embed_via_openai_with_retries(input_text: str):
    import json
    import ssl
    import urllib.request
    import urllib.error

    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        raise RuntimeError("Set OPENAI_API_KEY to use the hosted-API variant.")
    payload = {"model": "text-embedding-3-small", "input": input_text or ""}
    req = urllib.request.Request(
        "https://api.openai.com/v1/embeddings",
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}",
            "User-Agent": "aidb-postgres-python/1.0",
        },
    )
    ctx = ssl.create_default_context()
    attempts = MAX_ATTEMPTS
    for i in range(attempts):
        try:
            with urllib.request.urlopen(req, context=ctx, timeout=30) as resp:
                data = json.loads(resp.read().decode("utf-8"))
            if not data.get("data") or "embedding" not in data["data"][0]:
                raise RuntimeError(f"Unexpected response shape: keys={list(data.keys())}")
            return [float(x) for x in data["data"][0]["embedding"]]
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", errors="ignore")
            # retry only on transient HTTP status codes
            if e.code not in (429, 500, 502, 503, 504) or i == attempts - 1:
                raise RuntimeError(f"OpenAI HTTP {e.code} (attempt {i+1}/{attempts}): {body[:400]}")
            retry_after = e.headers.get("Retry-After")
            if retry_after:
                try:
                    sleep_s = float(retry_after)          # honor server's backoff hint
                except ValueError:
                    sleep_s = BASE_DELAY * (2 ** i) + random.uniform(0, 0.3)
            else:
                sleep_s = BASE_DELAY * (2 ** i) + random.uniform(0, 0.3)
            time.sleep(min(MAX_DELAY, sleep_s))
        except urllib.error.URLError:
            # transient network error (DNS, connection reset, timeout)
            if i == attempts - 1:
                raise
            time.sleep(min(MAX_DELAY, BASE_DELAY * (2 ** i) + random.uniform(0, 0.2)))


if __name__ == "__main__":
    main()
