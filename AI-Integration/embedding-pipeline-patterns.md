# Production-Grade Embedding Pipeline Patterns

Generating one embedding is easy. Running embedding generation as a **system** —
that stays fresh, survives API failures, doesn't hold OLTP hostage, controls cost,
and survives a model upgrade — is the real work. This doc is a learning walkthrough
of that production shape, building on two foundations already in this repo:

- the **generic queue mechanics** (`FOR UPDATE SKIP LOCKED`, DELETE-vs-UPDATE
  claim, reaper, dead-letter) in
  [Performance/postgresql-as-queue-table.md](../Performance/postgresql-as-queue-table.md);
- the **transactional-enqueue / async-embed** principle and batching in
  [pgvector-indexes.md](pgvector-indexes.md) §4.

Here we assemble those into a full pipeline and add the pieces that only matter in
production: **multi-entity jobs, pipeline-level retry with scheduled backoff,
change detection (hashing), cascade re-embedding, a query-embedding cache, and
model versioning.**

All SQL verified on **PostgreSQL 18.6** (+ `pgcrypto`). The embedding call itself
(`api.openai_embed(...)`) is shown as a placeholder — substitute your provider or a
local model (see [local-embeddings-minilm.md](local-embeddings-minilm.md)).

---

## 1. Two speeds of truth

The mental model the whole design rests on. A production system has two layers that
update at different speeds:

| Layer | Example data | Correctness requirement |
|-------|--------------|-------------------------|
| **Operational truth** (fast, exact) | product, price, inventory, category | must be correct **immediately** — if it lies, money breaks |
| **Semantic truth** (meaningful, eventual) | product/brand/category vectors, query vectors | must be correct **eventually** (ideally soon) — may lag without blocking OLTP |

Force semantic truth to behave like operational truth and you pay with **latency
and fragility** (an API call in the write path). Treat it as an afterthought and
you pay with **drift** — nothing crashes, but search quality quietly rots. The
pipeline balances the two: operational writes stay fast and deterministic; semantic
updates follow quickly, reliably, and recoverably.

---

## 2. Three patterns (pick a gear)

| Gear | Pattern | When | Risk |
|------|---------|------|------|
| 1 | **Synchronous** (embed at write time) | low volume, strict freshness, *local* low-latency model | API latency slows/blocks writes; an embedding failure fails the write |
| 2 | **Asynchronous** (enqueue + background worker) | **default for production**, high write volume | eventual consistency (brief "no vector yet" window) |
| 3 | **Near-real-time** (async + event-driven wakeups) | user-facing search where new content must appear fast | `LISTEN/NOTIFY` adds operational fragility |

Synchronous is for demos. **Asynchronous is the recommended production default**;
converting it to near-real-time later is a small change (§8). Everything below
builds the async pipeline.

---

## 3. Principle 1 — triggers enqueue, never embed

Embedding inside a trigger is a self-inflicted outage: the trigger runs **inside
the writing transaction**, which can't commit until the trigger returns — so a slow
or failing model call stalls (or aborts) the OLTP write and holds its locks. (This
is the inline anti-pattern from [pgvector-indexes.md](pgvector-indexes.md) §4,
stated as a hard rule.)

**Rule:** a trigger records *intent* ("this row needs an embedding"); an async
worker does the expensive work. Record intent as a **job in a queue** (not just a
`needs_embedding` flag) — the queue gives you backlog visibility, retry/failure
counts, and throttle control.

---

## 4. Principle 2 — a multi-entity job queue

One queue serves all embeddable entity types (here: category, brand, product,
variant), each identified by `(entity_type, entity_id)`:

```sql
CREATE TABLE IF NOT EXISTS embeddings.embedding_job (
    id           bigserial PRIMARY KEY,
    entity_type  text NOT NULL CHECK (entity_type IN ('category','brand','product','variant')),
    entity_id    integer NOT NULL,
    status       text NOT NULL DEFAULT 'pending'
                 CHECK (status IN ('pending','running','done','failed')),
    attempts     int  NOT NULL DEFAULT 0,
    last_error   text,
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now()
);
-- claim ordering
CREATE INDEX IF NOT EXISTS embedding_job_pending_idx
    ON embeddings.embedding_job (status, created_at);
-- one job per entity — the dedup backbone
CREATE UNIQUE INDEX IF NOT EXISTS embedding_job_entity_idx
    ON embeddings.embedding_job (entity_type, entity_id);
```

The unique `(entity_type, entity_id)` index is load-bearing: it lets enqueue be
**idempotent** (collapse rapid repeated updates of the same row into one pending
job).

**Enqueue helper** — one function all triggers call:

```sql
CREATE OR REPLACE FUNCTION embeddings.sf_enqueue_embedding_job(
    p_entity_type text, p_entity_id int
) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO embeddings.embedding_job (entity_type, entity_id)
    VALUES (p_entity_type, p_entity_id)
    ON CONFLICT (entity_type, entity_id) DO UPDATE      -- already queued? refresh, don't duplicate
      SET status = CASE WHEN embeddings.embedding_job.status = 'done'
                        THEN 'pending' ELSE embeddings.embedding_job.status END,
          updated_at = now();
END $$;
```

**Trigger** (one per source table) — fast, deterministic, writes a single queue
row; fire only when embedded columns change:

```sql
CREATE OR REPLACE FUNCTION embeddings.trg_enqueue_category_embedding()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    PERFORM embeddings.sf_enqueue_embedding_job('category', NEW.id);
    RETURN NEW;
END $$;

CREATE TRIGGER enqueue_category_embedding
    AFTER INSERT OR UPDATE OF label, description ON product.category
    FOR EACH ROW EXECUTE FUNCTION embeddings.trg_enqueue_category_embedding();
-- repeat for brand / product / variant
```

> Note the `UPDATE OF label, description` — the trigger fires only when a
> *meaning-bearing* column changes, not on every row update. (Change detection in
> §7 catches the rest.)

---

## 5. Principle 3 — the worker (batched, concurrent, safe)

A background function claims pending jobs with `FOR UPDATE SKIP LOCKED`, builds the
per-entity "meaning string," embeds, and **idempotently upserts** the vector —
isolating failures to one job:

```sql
CREATE OR REPLACE FUNCTION embeddings.sf_process_embedding_jobs(p_batch_size int DEFAULT 50)
RETURNS integer LANGUAGE plpgsql
SECURITY DEFINER SET search_path = pg_catalog, embeddings, product, api AS $fn$
DECLARE
    v_job   embeddings.embedding_job%ROWTYPE;
    v_text  text;
    v_vec   public.vector(1536);
    v_done  int := 0;
BEGIN
    FOR v_job IN
        SELECT ej.* FROM embeddings.embedding_job ej
        WHERE ej.status = 'pending'
        ORDER BY ej.created_at
        LIMIT p_batch_size
        FOR UPDATE SKIP LOCKED          -- multiple workers won't double-process
    LOOP
        BEGIN
            UPDATE embeddings.embedding_job
               SET status='running', attempts=attempts+1, last_error=NULL, updated_at=now()
             WHERE id = v_job.id;

            -- build the meaning string per entity type (coalesce guards NULLs)
            IF v_job.entity_type = 'product' THEN
                SELECT coalesce(p.label,'')||' '||coalesce(b.label,'')||' '||coalesce(c.label,'')
                       ||' '||coalesce(p.shortdescription,'')||' '||coalesce(p.longdescription,'')
                  INTO v_text
                  FROM product.product p
                  JOIN product.brand b    ON b.id = p.brand_id
                  JOIN product.category c ON c.id = p.category_id
                 WHERE p.id = v_job.entity_id;

                v_vec := api.openai_embed(v_text)::public.vector(1536);
                INSERT INTO embeddings.product_embedding (product_id, embedding)
                VALUES (v_job.entity_id, v_vec)
                ON CONFLICT (product_id) DO UPDATE SET embedding = EXCLUDED.embedding;
            -- ELSIF category / brand / variant ... (same shape)
            END IF;

            UPDATE embeddings.embedding_job SET status='done', updated_at=now()
             WHERE id = v_job.id;
            v_done := v_done + 1;
        EXCEPTION WHEN OTHERS THEN
            -- one bad job doesn't kill the batch; keep it for retry/inspection
            UPDATE embeddings.embedding_job
               SET status='failed', last_error=SQLERRM, updated_at=now()
             WHERE id = v_job.id;
        END;
    END LOOP;
    RETURN v_done;
END $fn$;
```

Run it from `pg_cron`, an OS cron, or an app worker: `SELECT
embeddings.sf_process_embedding_jobs(50);` — repeatedly until it returns 0. Why it's
production-shaped:

- **`FOR UPDATE SKIP LOCKED`** → run many workers concurrently, no double-processing
  (same mechanics as
  [postgresql-as-queue-table.md](../Performance/postgresql-as-queue-table.md) §1).
- **`ON CONFLICT DO UPDATE`** → re-running a job overwrites, never duplicates
  (idempotent).
- **per-job `EXCEPTION`** → failures are isolated and recorded (`last_error`), not
  fatal to the batch.
- **`running` status + `attempts`** → live observability of in-flight work and
  retries.

> **Richer context embeds better.** The product meaning string folds in brand and
> category labels and both descriptions — more signal generally yields more useful
> vectors than embedding a bare title.

---

## 6. Principle 4a — pipeline-level retry (scheduled backoff)

The per-*call* retry inside `api.openai_embed` (see
[generate_embeddings_with_retries.py](generate_embeddings_with_retries.py)) handles
a hiccup *within* one call. The **pipeline** needs its own retry for whole-job
failures (rate limits, timeouts, a worker crash). Add scheduling + a cap:

```sql
ALTER TABLE embeddings.embedding_job
    ADD COLUMN IF NOT EXISTS next_run_at  timestamptz NOT NULL DEFAULT now(),
    ADD COLUMN IF NOT EXISTS max_attempts int        NOT NULL DEFAULT 10;
CREATE INDEX IF NOT EXISTS embedding_job_runnable_idx
    ON embeddings.embedding_job (status, next_run_at, created_at);
```

Claim only **runnable** jobs — pending *or* failed-but-due, under the attempt cap:

```sql
SELECT ej.* FROM embeddings.embedding_job ej
WHERE ej.status IN ('pending','failed')
  AND ej.next_run_at <= now()
  AND ej.attempts < ej.max_attempts
ORDER BY ej.created_at
LIMIT p_batch_size
FOR UPDATE SKIP LOCKED;
```

On failure, push `next_run_at` out with **exponential backoff + jitter**, capped so
a job never stalls forever and a worker fleet never stampedes:

```sql
UPDATE embeddings.embedding_job
   SET status='failed', last_error=SQLERRM, updated_at=now(),
       next_run_at = now() + make_interval(secs =>
           LEAST(300, (2 ^ LEAST(attempts, 10))::int + random() * 1.0))
 WHERE id = v_job.id;
```

Verified backoff curve (`delay = min(300, 2^attempts + jitter)`) on PG 18.6:

```
attempts | delay_secs
       0 |   ~1        -- 1s
       3 |   ~8        -- 8s
       6 |  ~64
       8 | ~256
       9+| 300.000     -- capped at 5 min
```

Jobs that exhaust `max_attempts` drop out of the runnable set automatically — that's
your **dead-letter** condition (inspect `status='failed' AND attempts>=max_attempts`;
see the dead-letter section of
[postgresql-as-queue-table.md](../Performance/postgresql-as-queue-table.md) §6 for
routing them to a side table).

---

## 7. Principle 4b — change detection (don't re-embed unchanged meaning)

A row `UPDATE` can fire the trigger even when no meaning-bearing content actually
changed — each needless re-embed is wasted latency **and** API cost. Fix: hash the
meaning string and only call the model when the hash differs.

```sql
CREATE EXTENSION IF NOT EXISTS pgcrypto;
ALTER TABLE embeddings.product_embedding
    ADD COLUMN IF NOT EXISTS content_hash text;   -- repeat per embedding table
```

In the worker, before embedding:

```sql
-- 1. hash the freshly built meaning string
SELECT encode(digest(v_text, 'sha256'), 'hex') INTO v_new_hash;

-- 2. compare with the stored hash; if unchanged, mark done and skip the API call
SELECT content_hash INTO v_old_hash
  FROM embeddings.product_embedding WHERE product_id = v_job.entity_id;

IF v_old_hash IS NOT NULL AND v_old_hash = v_new_hash THEN
    UPDATE embeddings.embedding_job SET status='done', updated_at=now() WHERE id=v_job.id;
    v_done := v_done + 1;
    CONTINUE;                      -- no embedding generated
END IF;

-- 3. changed → embed and store the new hash alongside the vector
v_vec := api.openai_embed(v_text)::public.vector(1536);
INSERT INTO embeddings.product_embedding (product_id, embedding, content_hash)
VALUES (v_job.entity_id, v_vec, v_new_hash)
ON CONFLICT (product_id) DO UPDATE
    SET embedding = EXCLUDED.embedding, content_hash = EXCLUDED.content_hash;
```

This improves **cost** (fewer calls), **throughput** (less work/batch), and keeps
**correctness** (a genuine meaning change always re-embeds). `sha256` via `digest()`
verified on PG 18.6.

### Indirect changes — cascade enqueue

The product meaning string embeds **brand and category labels**, so a category or
brand edit makes its products' vectors stale even though `product.product` didn't
change. Fix: when a parent changes, enqueue the parent **and** its children:

```sql
CREATE OR REPLACE FUNCTION embeddings.trg_enqueue_category_embedding()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    PERFORM embeddings.sf_enqueue_embedding_job('category', NEW.id);   -- the category
    INSERT INTO embeddings.embedding_job (entity_type, entity_id)      -- its products
    SELECT 'product', p.id FROM product.product p WHERE p.category_id = NEW.id
    ON CONFLICT (entity_type, entity_id) DO NOTHING;
    RETURN NEW;
END $$;
```

Change detection (§7) then short-circuits any product whose meaning didn't actually
move, so cascade enqueue is cheap even when it fans out widely. Verified: editing a
category enqueues exactly its own job plus one per child product, with no
duplicates.

---

## 8. Making it near-real-time

Async with a poll interval has an inherent lag (up to one poll period). Two ways to
cut it:

**Option A — `LISTEN`/`NOTIFY` (fast wakeups).** The enqueue trigger also rings a
doorbell; a listening worker runs the processor immediately:

```sql
-- in the trigger, after enqueuing:
PERFORM pg_notify('embedding_jobs', NEW.entity_type || ':' || NEW.id);
-- worker: LISTEN embedding_jobs;  then call sf_process_embedding_jobs() on each signal
```

**`NOTIFY` is a doorbell, not the source of truth** — it's best-effort and lost if
no worker is connected. The **durable queue remains the truth**; NOTIFY only reduces
latency (same guidance as [pgvector-indexes.md](pgvector-indexes.md) §4).

**Option B — scheduler-driven micro-batching.** Just run the worker often (every few
seconds) in small batches. No long-lived listener to babysit; smooths API usage and
reduces rate-limit spikes. Often the simpler, more robust choice for "real-time
enough."

---

## 9. Query embeddings: on-demand vs cached

Data embeddings (products, etc.) are stored, indexed, and refreshed. **Query
embeddings** are a second, different beast: high-volume, high-entropy, mostly
one-off. Embedding every query on-demand is correct but puts an API call **in the
search critical path** (latency) and repeats work for popular queries (cost).

A disciplined cache keyed by `(query_text, model_id)` with a "last used" timestamp
for eviction:

```sql
CREATE TABLE IF NOT EXISTS embeddings.query_embedding_cache (
    query_text   text NOT NULL,
    embedding    vector(1536) NOT NULL,
    model_id     text NOT NULL,
    created_at   timestamptz NOT NULL DEFAULT now(),
    last_used_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (query_text, model_id)
);
CREATE INDEX IF NOT EXISTS query_embedding_cache_last_used_idx
    ON embeddings.query_embedding_cache (last_used_at);

CREATE OR REPLACE FUNCTION embeddings.sf_get_query_embedding(
    p_query text, p_model_id text DEFAULT 'text-embedding-3-small'
) RETURNS vector(1536) LANGUAGE plpgsql
SECURITY DEFINER SET search_path = pg_catalog, embeddings, api, public AS $fn$
DECLARE v_embedding vector(1536);
BEGIN
    SELECT embedding INTO v_embedding            -- fast path: cache hit
      FROM embeddings.query_embedding_cache
     WHERE query_text = p_query AND model_id = p_model_id;
    IF v_embedding IS NOT NULL THEN
        UPDATE embeddings.query_embedding_cache SET last_used_at = now()
         WHERE query_text = p_query AND model_id = p_model_id;
        RETURN v_embedding;
    END IF;

    v_embedding := api.openai_embed(p_query)::vector(1536);   -- miss: compute + store
    INSERT INTO embeddings.query_embedding_cache (query_text, embedding, model_id, last_used_at)
    VALUES (p_query, v_embedding, p_model_id, now())
    ON CONFLICT (query_text, model_id)
        DO UPDATE SET embedding = EXCLUDED.embedding, last_used_at = now();
    RETURN v_embedding;
END $fn$;
```

Search then calls `sf_get_query_embedding('…')` instead of embedding inline — popular
queries become a single index lookup. **A cache without eviction is a landfill**;
TTL on `last_used_at` keeps it bounded:

```sql
DELETE FROM embeddings.query_embedding_cache
WHERE last_used_at < now() - interval '7 days';     -- run periodically
```

Cache only when queries repeat and you want lower latency/cost; TTL (optionally plus
a size cap) is the first and usually sufficient eviction policy.

---

## 10. Model changes = semantic drift (version from day one)

Embeddings are shaped by the model, its tokenizer, training data, and dimensionality.
If the model changes:

1. **Cross-model distances are meaningless** — never compare vectors from different
   models (dimensions and geometry differ). See
   [embeddings-explained.md](embeddings-explained.md) on cross-model incompatibility.
2. Even at matching dimensions, **ranking drifts**.

So treat the embedding model like an **API version**, and build that in on day one
by tagging every stored vector:

```sql
ALTER TABLE embeddings.product_embedding
    ADD COLUMN IF NOT EXISTS model_id text NOT NULL DEFAULT 'text-embedding-3-small';
-- and filter searches by it: ... AND pe.model_id = 'text-embedding-3-small'
```

Two upgrade strategies:

| Strategy | How | Trade-off |
|----------|-----|-----------|
| **Hard cutover** | pick new model → re-embed all → rebuild ANN indexes → switch | simplest mentally; most expensive, needs a cutover window |
| **Parallel run** | keep old vectors serving; build new (tagged) set alongside; validate relevance; then switch | safe, no trust break; needs `model_id` tagging and more storage during migration |

**What forces a full re-embed:** a model change, a change to the **meaning-string
recipe** (e.g. now folding brand into the text), a big data-distribution shift (new
language), or normalization-rule changes. When the *fingerprint recipe* changes, the
fingerprints must be regenerated — which is exactly why the embedding pipeline is
**data infrastructure, not a one-off script.**

---

## Summary

1. **Two speeds of truth** — operational (fast/exact) vs semantic (eventual);
   the pipeline keeps OLTP fast while vectors follow reliably.
2. **Triggers enqueue, never embed** — a slow model call must never sit in the write
   transaction.
3. **A multi-entity job queue** keyed by `(entity_type, entity_id)` with a unique
   index for dedup; a **batched, concurrent worker** (`SKIP LOCKED` +
   `ON CONFLICT` + per-job `EXCEPTION`).
4. **Pipeline-level retry** with `next_run_at` + `max_attempts` + SQL-computed
   exponential backoff/jitter (capped); exhausted jobs are the dead-letter signal.
5. **Change detection** (sha256 of the meaning string) skips needless re-embeds;
   **cascade enqueue** refreshes children when a parent's label/description changes.
6. **Near-real-time** via `LISTEN/NOTIFY` doorbell (queue stays the truth) or
   micro-batching.
7. **Query-embedding cache** keyed by `(query_text, model_id)` with TTL eviction —
   keeps the API out of the search hot path.
8. **Version the model** (`model_id` on every vector); hard-cutover vs parallel-run
   upgrades; never compare across models.

Foundations: generic queue mechanics —
[Performance/postgresql-as-queue-table.md](../Performance/postgresql-as-queue-table.md);
transactional enqueue, batching, data modeling —
[pgvector-indexes.md](pgvector-indexes.md).

---

*Pattern inspiration: "Production-Ready AI Embedding Pipeline Patterns," Vibhor
Kumar, *AI-Ready PostgreSQL 18*. SQL adapted to this repo's conventions and verified
on PostgreSQL 18.6.*
