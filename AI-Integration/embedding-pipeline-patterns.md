# Production-Grade Embedding Pipeline Patterns

Earlier docs in this repo built the pieces of an embedding system:

- [pgvector-indexes.md](pgvector-indexes.md) §4 — keep OLTP fast by having a trigger
  enqueue a marker and a worker embed asynchronously (our `documents` →
  `embedding_queue` → `doc_embeddings` flow), plus batching.
- [Performance/postgresql-as-queue-table.md](../Performance/postgresql-as-queue-table.md)
  — the queue mechanics: `FOR UPDATE SKIP LOCKED`, DELETE-on-claim vs
  UPDATE-to-processing, reaper, dead-letter.
- [generate_embeddings_with_retries.py](generate_embeddings_with_retries.py) /
  [generate_embeddings_batched.py](generate_embeddings_batched.py) — retry/backoff
  and true batch embedding, measured.

This doc joins those into one operational picture and adds the few things that only
bite once the system is live: **not re-embedding when meaning didn't change**,
**keeping derived embeddings fresh when a referenced row changes**, **caching query
embeddings**, and **surviving a model change**. We continue with the same schema we
used throughout — a `documents` table embedded into `doc_embeddings` via an
`embedding_queue` — rather than inventing new entities.

The pipeline *mechanics* below were verified on **PostgreSQL 18.6 + pgvector 0.8.7**
using the real `vector` type. The external model call is written as
`embed(text) → vector` and left as a placeholder: substitute a hosted API or a local
model ([local-embeddings-minilm.md](local-embeddings-minilm.md)). The hosted-API
request/response shapes referenced here come from each provider's public docs.

---

## 1. The core tension (recap) and why a pipeline

An embedding is produced by an external (often networked) model. Two facts collide:

- The source row must commit **fast** — users are waiting, locks are held.
- The model call is **slow and failure-prone** — tens-to-hundreds of ms, rate
  limits, 5xx, timeouts.

Putting the model call in the writing transaction (inline, or in a trigger) ties
commit latency to model latency and holds row locks across a network round-trip —
the anti-pattern established in [pgvector-indexes.md](pgvector-indexes.md) §4. The
fix is a **pipeline**: the write records *intent* durably and returns; a separate
worker does the slow work and can retry without touching OLTP.

A useful way to hold this in your head: the database has **two clocks**.

| Clock | Data | Must be correct… |
|-------|------|------------------|
| Transactional | the `documents` row, prices, inventory | **now** — if it's wrong, the business is wrong |
| Semantic | the vector in `doc_embeddings` | **soon** — a brief lag is fine; forcing it to be instant costs you latency and fragility |

The whole design keeps the transactional clock fast and lets the semantic clock
catch up reliably.

---

## 2. Where to put the embedding call — three options

| Option | Embed happens | Use when | Cost |
|--------|---------------|----------|------|
| **Inline / synchronous** | inside the write txn | tiny volume, a *local* fast model, you need read-after-write | slow writes; a model outage blocks writes |
| **Async (polled worker)** | later, worker polls the queue | **default** for real volume | eventual consistency (short "no vector yet" gap) |
| **Async + notify** | immediately on a `NOTIFY` nudge | user-facing freshness | one more moving part (`LISTEN/NOTIFY`) |

We built async in [pgvector-indexes.md](pgvector-indexes.md) §4 and make it
production-grade here; §6 shows the small step to notify-driven.

---

## 3. The queue, carrying operational state

Our starting `embedding_queue` ([pgvector-indexes.md](pgvector-indexes.md) §4) held
just `(document_id, enqueued_at)`. For production we let the queue row **carry its
own operational state** — attempts, last error, and a *scheduled* next attempt —
so retries and backlog are visible and controllable:

```sql
CREATE TABLE embedding_queue (
    document_id  bigint PRIMARY KEY,          -- one pending job per document (dedup)
    enqueued_at  timestamptz NOT NULL DEFAULT now(),
    attempts     int         NOT NULL DEFAULT 0,
    max_attempts int         NOT NULL DEFAULT 8,
    next_run_at  timestamptz NOT NULL DEFAULT now(),  -- not before this time
    last_error   text
);
-- claim index: cheap lookup of rows that are due, oldest first
CREATE INDEX embedding_queue_due_idx ON embedding_queue (next_run_at, enqueued_at);
```

The `document_id` primary key gives us idempotent enqueue for free — rapid repeated
edits of the same document collapse into one job (the trigger from
[pgvector-indexes.md](pgvector-indexes.md) §4 already uses
`ON CONFLICT (document_id) DO UPDATE SET enqueued_at = now()`).

> This keeps a *single* queue for one entity (`documents`). If you later embed more
> than one kind of row, the cleanest extension is **one queue table per entity**
> (each with its own trigger and worker), or a shared queue with an added
> `entity` discriminator column — but don't reach for that until you actually have
> a second entity. Start simple.

### How many queue rows if a document is updated many times?

**Exactly one — no matter how many updates, or how many concurrent sessions.** This
is the payoff of keying the queue by `document_id` (the primary key) rather than by
update *event*. Two things guarantee it, both verified on PG 18.6:

- **The PK + `ON CONFLICT (document_id) DO UPDATE`** means a second enqueue for the
  same document can't insert a new row — it just re-stamps `enqueued_at` on the
  existing one. Five rapid `UPDATE`s to one document → **1** queue row.
- **Concurrent sessions can't race in two rows.** A second session updating the
  same `documents` row **blocks** on PostgreSQL's row write-lock until the first
  commits, so the two trigger firings are *serialized*, not simultaneous — the
  second sees the row the first enqueued and coalesces into it. (Verified: session
  B's update waited on session A's open transaction, and afterward there was still
  one queue row.)

This directly avoids the two failure modes a naive **log-style** queue (a
`bigserial` PK, one row per update) would create:

| Concern | Log-style queue (one row per update) | Our coalesced queue (keyed by `document_id`) |
|---------|--------------------------------------|---------------------------------------------|
| Multiple workers grab the same document | possible (N rows for one doc) | impossible — 1 row, claimed by 1 worker via `SKIP LOCKED` |
| Intermediate versions wasted on embedding | yes — v2…v5 each get embedded | no — see below |

**Why intermediate versions aren't wasted:** the worker reads the body **fresh at
embed time** (`SELECT body INTO v_text FROM documents WHERE id = …`), so it always
embeds the document's *current* committed text, never the superseded v2…v5. The one
coalesced job means "embed whatever this document looks like now" — which is exactly
what you want. So a burst of edits costs **one** embedding, not one per edit.

> **Edge case: an update arrives while a worker is mid-embed.** This is safe, and
> the reason is lock ordering (verified on PG 18.6). The §4 worker claims the queue
> row with `SELECT … FOR UPDATE` and holds that lock across the slow `embed()` — it
> does **not** delete the row until the end. So when the new update's trigger runs
> `INSERT … ON CONFLICT (document_id) DO UPDATE`, it finds the row **locked** and
> **blocks**. When the worker commits (vector of the old text persisted, row
> deleted), the enqueue unblocks, re-evaluates, sees the row **gone**, and takes the
> plain-`INSERT` path — leaving a **fresh pending job**. Net: the vector is briefly
> one version behind, but a pending job for the new text always exists, so the next
> worker pass re-embeds it. **No intent is lost.**
>
> (What would lose intent is deleting the claimed row in a *separate committed
> transaction* before embedding, so a new enqueue could slip in and then be
> deleted — our single-transaction worker never does this. If you need the vector
> to never lag even briefly, use UPDATE-to-processing with a changed-during-run
> re-check, per
> [postgresql-as-queue-table.md](../Performance/postgresql-as-queue-table.md) §3.)

---

## 4. The worker: claim due jobs, embed, upsert — idempotently

The worker claims **due** jobs (`next_run_at <= now()`, still under the attempt
cap), embeds, and upserts into `doc_embeddings`. It's the UPDATE-to-processing idea
from [postgresql-as-queue-table.md](../Performance/postgresql-as-queue-table.md)
with the slow step kept outside any OLTP table's locks:

```sql
CREATE OR REPLACE FUNCTION process_embedding_batch(p_limit int DEFAULT 100)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE
    r        record;
    v_text   text;
    v_vec    vector(384);          -- match your model's dimension
    v_done   int := 0;
BEGIN
    FOR r IN
        SELECT q.document_id
        FROM embedding_queue q
        WHERE q.next_run_at <= now()
          AND q.attempts   <  q.max_attempts
        ORDER BY q.enqueued_at
        LIMIT p_limit
        FOR UPDATE SKIP LOCKED       -- concurrent workers take disjoint batches
    LOOP
        BEGIN
            SELECT body INTO v_text FROM documents WHERE id = r.document_id;

            v_vec := embed(v_text)::vector(384);   -- the slow external call (placeholder)

            INSERT INTO doc_embeddings (document_id, embedding)
            VALUES (r.document_id, v_vec)
            ON CONFLICT (document_id) DO UPDATE      -- idempotent: re-run overwrites
                SET embedding = EXCLUDED.embedding;

            DELETE FROM embedding_queue WHERE document_id = r.document_id;  -- success: job done
            v_done := v_done + 1;

        EXCEPTION WHEN OTHERS THEN
            -- isolate the failure; reschedule this one job with backoff (see §5)
            UPDATE embedding_queue
               SET attempts    = attempts + 1,
                   last_error  = SQLERRM,
                   next_run_at  = now() + make_interval(secs =>
                                    LEAST(300, (2 ^ LEAST(attempts, 8))::int) + random())
             WHERE document_id = r.document_id;
        END;
    END LOOP;
    RETURN v_done;
END $$;
```

Run it from `pg_cron`, OS cron, or an app loop: `SELECT process_embedding_batch();`
until it returns 0. The production-grade properties, all from our earlier docs:

- **`FOR UPDATE SKIP LOCKED`** — many workers, disjoint batches, no convoy
  ([postgresql-as-queue-table.md](../Performance/postgresql-as-queue-table.md) §1).
- **`ON CONFLICT DO UPDATE`** — re-running a job is safe (idempotent); pairs with
  at-least-once delivery.
- **per-job `EXCEPTION`** — one poison row fails alone and is rescheduled, not the
  whole batch.
- The slow `embed()` touches no `documents` lock — the queue is a disposable table,
  so holding its transaction is fine (the OLTP-vs-queue distinction in
  [postgresql-as-queue-table.md](../Performance/postgresql-as-queue-table.md) §2).

> **Claim style:** this deletes on success (DELETE-on-claim). Because the whole
> claim→embed→upsert is one transaction, a crashed worker rolls back and the row
> reappears — crash-safe, per
> [postgresql-as-queue-table.md](../Performance/postgresql-as-queue-table.md) §2.
> The `attempts`/`next_run_at` columns add *scheduled* retries on top.

---

## 5. Pipeline-level retry: scheduled backoff + a cap

`generate_embeddings_with_retries.py` retries *within* one call. The pipeline also
needs retry *across* runs for whole-job failures (rate limit, timeout, crash). Two
columns do it: `next_run_at` (when it's eligible again) and `max_attempts` (so it
doesn't loop forever). The `EXCEPTION` block in §4 already sets them — exponential
backoff with jitter, capped:

```
delay = min(300, 2^attempts) + random()   -- seconds; cap at 5 min; jitter de-syncs a worker fleet
```

Verified curve on PG 18.6 (`2^attempts`, capped at 300):

```
attempts:  0    1    2    3    4     5     6     7    8+
delay  ≈:  1s   2s   4s   8s   16s   32s   64s   128s 256s → 300s cap
```

A job that burns through `max_attempts` simply stops being claimed (the worker's
`attempts < max_attempts` filter excludes it). That stuck set **is** your
dead-letter list — inspect or drain it exactly as in
[postgresql-as-queue-table.md](../Performance/postgresql-as-queue-table.md) §6:

```sql
-- what's stuck / failing
SELECT document_id, attempts, last_error, next_run_at
FROM embedding_queue
WHERE attempts >= max_attempts
ORDER BY enqueued_at;
```

---

## 6. Lower latency: notify instead of poll

Polling has up to one interval of lag. To react in milliseconds, have the enqueue
trigger ring a doorbell (building on the trigger already in
[pgvector-indexes.md](pgvector-indexes.md) §4):

```sql
-- inside enqueue_embedding(), after the INSERT ... ON CONFLICT:
PERFORM pg_notify('embedding_jobs', NEW.id::text);
-- a worker: LISTEN embedding_jobs;  then run process_embedding_batch() on each signal
```

`NOTIFY` is a **nudge, not the record** — it's best-effort and missed if no worker
is listening. The durable `embedding_queue` stays the source of truth; the notify
only shortens latency. If a long-lived listener is operationally awkward, just poll
every few seconds in small batches — simpler, and usually "real-time enough."

---

## 7. Don't re-embed unchanged meaning (cost + throughput)

A `documents` UPDATE can fire the enqueue trigger even when the embedded text didn't
really change — and every needless re-embed is latency and (for hosted APIs) money.
There are **three** places to catch this, each cheaper and earlier than the last;
use them together.

**Layer 1 — fire the trigger only for relevant columns (`UPDATE OF`).** This is an
out-of-the-box trigger feature: restrict firing to the columns the embedding
depends on, so updates to unrelated columns (a `views` counter, `updated_at`) never
even invoke the trigger:

```sql
CREATE TRIGGER trg_enqueue
  AFTER INSERT OR UPDATE OF body, title ON documents   -- only these columns fire it
  FOR EACH ROW EXECUTE FUNCTION enqueue_embedding();
```

Caveat: `UPDATE OF` keys on *which columns were assigned*, not whether the value
changed — `UPDATE documents SET body = body` still fires it. That's what layer 2 is
for.

**Layer 2 — enqueue only if a value actually changed (`IS DISTINCT FROM`).** Inside
the trigger, compare old vs new. Use `IS DISTINCT FROM` (NULL-safe) rather than
`<>`:

```sql
CREATE OR REPLACE FUNCTION enqueue_embedding() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT'
       OR OLD.body  IS DISTINCT FROM NEW.body
       OR OLD.title IS DISTINCT FROM NEW.title
    THEN
        INSERT INTO embedding_queue (document_id) VALUES (NEW.id)
        ON CONFLICT (document_id) DO UPDATE SET enqueued_at = now();
    END IF;
    RETURN NEW;
END $$;
```

This catches the "assigned the same value" case layer 1 can't — no queue row is
written at all.

**Layer 3 — skip the model call if the *composed* text is unchanged (content
hash).** Layers 1–2 only see raw `documents` columns, but the embedded text is often
*composed* (e.g. `body || ' ' || title`, maybe plus a referenced label). Two
different edits can still yield the **same** final string (whitespace trimming, a
change that doesn't survive concatenation), and the referenced-row re-enqueue below
doesn't change `documents` at all. So the last and most accurate guard fingerprints
the exact text we're about to embed:

```sql
ALTER TABLE doc_embeddings ADD COLUMN IF NOT EXISTS content_hash text;
CREATE EXTENSION IF NOT EXISTS pgcrypto;   -- for digest()
```

In the worker, between fetching `v_text` and calling `embed()`:

```sql
-- fingerprint the text we're about to embed
v_hash := encode(digest(v_text, 'sha256'), 'hex');

-- already embedded this exact text? then just clear the job, no model call
SELECT content_hash INTO v_old FROM doc_embeddings WHERE document_id = r.document_id;
IF v_old IS NOT NULL AND v_old = v_hash THEN
    DELETE FROM embedding_queue WHERE document_id = r.document_id;
    v_done := v_done + 1;
    CONTINUE;
END IF;

-- changed (or new): embed and store the vector WITH its fingerprint
v_vec := embed(v_text)::vector(384);
INSERT INTO doc_embeddings (document_id, embedding, content_hash)
VALUES (r.document_id, v_vec, v_hash)
ON CONFLICT (document_id) DO UPDATE
    SET embedding = EXCLUDED.embedding, content_hash = EXCLUDED.content_hash;
```

Fewer calls, less work per batch, and correctness preserved — a genuine text change
always re-embeds because its hash differs.

The three layers act at different stages, each skipping cheaper work earlier
(verified on PG 18.6):

| Layer | Mechanism | Skips when… | Avoids |
|-------|-----------|-------------|--------|
| 1 | `UPDATE OF body, title` | the update didn't touch an embedded column | the trigger firing at all |
| 2 | `OLD.col IS DISTINCT FROM NEW.col` | an embedded column was assigned its same value | writing a queue row |
| 3 | `sha256` of the composed text | different edits produce the same embedded string | the model API call |

Keep all three: 1 and 2 are nearly free and shrink the queue; 3 is the only one that
also covers composed text and the referenced-row case below.

### When a *referenced* row changes

If the embedded text is composed from more than the row itself — say a document's
meaning string includes its author's name or a category label — then editing that
*referenced* row makes the document's vector stale even though `documents` didn't
change. Re-enqueue the affected documents when the referenced row changes:

```sql
-- trigger on the referenced table (e.g. authors): re-enqueue that author's documents
CREATE OR REPLACE FUNCTION enqueue_author_documents() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO embedding_queue (document_id)
    SELECT d.id FROM documents d WHERE d.author_id = NEW.id
    ON CONFLICT (document_id) DO UPDATE SET enqueued_at = now();
    RETURN NEW;
END $$;
```

The §7 hash check then short-circuits any document whose composed text didn't
actually move, so even a wide fan-out stays cheap.

---

## 8. Query embeddings: a separate, cached concern

Everything so far embeds **stored** rows. A semantic search also has to embed the
**user's query** — and that's a different shape: high volume, mostly one-off, and
sitting directly in the request's latency path. Two choices:

- **On-demand** — embed the query every search. Simple and always correct, but an
  API call is in the hot path and popular queries pay repeatedly.
- **Cached** — reuse the vector for a repeated query text.

A disciplined cache, keyed by the text *and* the model (so a model change doesn't
serve stale vectors — see §9), with a last-used stamp for eviction:

```sql
CREATE TABLE query_embedding_cache (
    query_text   text NOT NULL,
    model_id     text NOT NULL,
    embedding    vector(384) NOT NULL,
    last_used_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (query_text, model_id)
);
CREATE INDEX query_embedding_cache_lru_idx ON query_embedding_cache (last_used_at);
```

Look up, else compute-and-store:

```sql
CREATE OR REPLACE FUNCTION get_query_embedding(p_query text, p_model text)
RETURNS vector(384) LANGUAGE plpgsql AS $$
DECLARE v_vec vector(384);
BEGIN
    SELECT embedding INTO v_vec
    FROM query_embedding_cache WHERE query_text = p_query AND model_id = p_model;

    IF FOUND THEN
        UPDATE query_embedding_cache SET last_used_at = now()
        WHERE query_text = p_query AND model_id = p_model;
        RETURN v_vec;
    END IF;

    v_vec := embed(p_query)::vector(384);              -- miss: compute once
    INSERT INTO query_embedding_cache (query_text, model_id, embedding)
    VALUES (p_query, p_model, v_vec)
    ON CONFLICT (query_text, model_id) DO UPDATE
        SET embedding = EXCLUDED.embedding, last_used_at = now();
    RETURN v_vec;
END $$;
```

A cache with no eviction is a landfill — bound it with a last-used TTL run
periodically:

```sql
DELETE FROM query_embedding_cache WHERE last_used_at < now() - interval '7 days';
```

Cache only if queries actually repeat; TTL (optionally plus a row-count cap) is
enough to start.

---

## 9. Surviving a model change

Embeddings are only comparable **within one model** — dimensions and geometry
differ across models, so a vector from model A and a vector from model B can't be
distance-compared (see [embeddings-explained.md](embeddings-explained.md) on
cross-model incompatibility). So a model swap isn't a config change; it invalidates
every stored vector.

Build for it from the start by tagging each vector with the model that produced it:

```sql
ALTER TABLE doc_embeddings
    ADD COLUMN IF NOT EXISTS model_id text NOT NULL DEFAULT 'minilm-l6-v2';
-- and filter searches by the active model:  WHERE model_id = 'minilm-l6-v2'
```

Then upgrades have a safe path:

| Approach | How | Trade-off |
|----------|-----|-----------|
| **Cutover** | re-embed all, rebuild the ANN index, switch the active `model_id` | simplest; needs a backfill window, briefly double-stores vectors |
| **Parallel** | write new-model vectors alongside old, keep serving old, validate, then flip | no downtime / no quality surprise; more storage + query plumbing during migration |

**What forces a full re-embed:** a new model, **or** a change to how you *compose*
the embedded text (the hash in §7 catches per-row changes, but changing the recipe
for everyone is a deliberate full rebuild), or a normalization change (casing,
HTML-stripping). When the recipe changes, every fingerprint must be regenerated —
which is why this is data infrastructure, not a one-off script.

---

## Summary

1. **Two clocks** — transactional (fast/exact) and semantic (soon/eventual); the
   pipeline keeps the first fast and lets the second catch up.
2. **Enqueue, don't embed inline** — the write records intent; a worker does the
   slow call (our `documents` → `embedding_queue` → `doc_embeddings` flow).
3. **Operational queue state** — `attempts` / `max_attempts` / `next_run_at` /
   `last_error` on the queue row give scheduled retries and visible backlog.
4. **Worker** — `FOR UPDATE SKIP LOCKED` + per-job `EXCEPTION` + idempotent
   `ON CONFLICT` upsert; the whole job in one transaction is crash-safe.
5. **Backoff** — `min(300, 2^attempts) + jitter`; exhausted jobs are the
   dead-letter set.
6. **Notify** optionally shortens latency; the queue stays the source of truth.
7. **Three change-detection layers** — `UPDATE OF` (fire only for embedded
   columns), `IS DISTINCT FROM` (enqueue only on real value change), and a `sha256`
   content hash (skip the model call when the composed text is unchanged);
   re-enqueue documents when a *referenced* row changes. A document edited N times
   (even concurrently) coalesces into **one** queue row and costs **one** embed of
   the latest text.
8. **Query embeddings** are a separate, cacheable concern — key by
   `(query_text, model_id)`, evict by TTL.
9. **Tag vectors with `model_id`** and plan cutover vs parallel-run upgrades; never
   compare across models.

Builds on: [pgvector-indexes.md](pgvector-indexes.md) ·
[Performance/postgresql-as-queue-table.md](../Performance/postgresql-as-queue-table.md)
· [generate_embeddings_with_retries.py](generate_embeddings_with_retries.py) ·
[generate_embeddings_batched.py](generate_embeddings_batched.py).
