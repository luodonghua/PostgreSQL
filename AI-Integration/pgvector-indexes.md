# pgvector Indexes: Overview, Comparison & Data Modeling

pgvector offers two approximate-nearest-neighbor (ANN) indexes to make
`ORDER BY embedding <=> :q LIMIT k` fast at scale: **HNSW** and **IVFFlat**.
Without an index this query is *exact* but scans every row — fine for thousands,
far too slow for millions.

This is the **general** doc: how to choose between the two, and the
engineering around them — **data modeling** (where the vector column lives) and
**keeping vectors updated transactionally without slowing OLTP**. The mechanics
of each index live in their own deep dives:

- **[pgvector-hnsw.md](pgvector-hnsw.md)** — graph index, the recommended default.
- **[pgvector-ivfflat.md](pgvector-ivfflat.md)** — cluster index, cheaper to build.

"ANN" = Approximate Nearest Neighbor — the *category*; HNSW and IVFFlat are the
two ANN indexes pgvector ships, not a third type. All behavior verified on
PostgreSQL 18.6 + pgvector 0.8.7.

---

## 1. First, what does "closest" mean? Distance metrics as rulers

To find the nearest vectors the database needs a **distance metric** — think of
each as a different kind of **ruler**:

- **L2 / Euclidean (`<->`)** — the "as the crow flies" straight-line distance
  (generalized Pythagoras). Includes magnitude: where the points actually sit.
- **Cosine (`<=>`)** — ignores length, measures only the **angle** between
  vectors. The most popular ruler for **text/topic** similarity, since meaning is
  in direction, not length.
- **Inner product (`<#>`)** — blends angle and magnitude. pgvector returns the
  **negative** inner product so ascending sort still puts the most similar first.

Rarely used (and for specific data):

- **L1 / Manhattan (`<+>`)** — sum of per-dimension distances (city-block).
- **Hamming (`<~>`)** — binary (`bit`) vectors: number of differing bits.
- **Jaccard (`<%>`)** — binary (`bit`) vectors: dissimilarity of the two bit sets.

The index's **operator class must match the metric** you query with:

| Operator | Metric | `vector` opclass |
|----------|--------|------------------|
| `<->` | L2 | `vector_l2_ops` |
| `<=>` | cosine | `vector_cosine_ops` |
| `<#>` | inner product | `vector_ip_ops` |
| `<+>` | L1 | `vector_l1_ops` |

(For `halfvec`/`sparsevec` use `halfvec_*_ops`/`sparsevec_*_ops`; for `bit`,
`bit_hamming_ops` / `bit_jaccard_ops`.) An index built for one metric does **not**
serve queries using another. See
[embeddings-explained.md](embeddings-explained.md) for the metric math.

---

## 2. HNSW vs IVFFlat

| | **HNSW** (graph) | **IVFFlat** (clusters) |
|---|---|---|
| Structure | multilayer neighbor graph | k-means lists + centroids |
| Build speed | slow | **fast** |
| Build memory | high | **low** |
| Index size | larger | **smaller** |
| Recall at a given latency | **better** | good (needs tuning) |
| Needs data before building | no (works on empty) | **yes** (k-means) |
| Dynamic / frequent updates | **robust**, fewer rebuilds | recall drifts, rebuild to recluster |
| Build params | `m`, `ef_construction` | `lists` |
| Query knob | `ef_search` (default 40) | `probes` (default 1) |

### Measured: build time, memory sensitivity & index size

Benchmark on **100,000 rows of `vector(384)`** (PostgreSQL 18.6, pgvector 0.8.7;
heap ≈ 156 MB). Your absolute numbers will differ with hardware/dimensions, but
the **relationships** are the point:

| Metric | HNSW | IVFFlat |
|--------|------|---------|
| Build time @ default `maintenance_work_mem` (64 MB) | **16.1 s** | **8.3 s** |
| Build time @ `maintenance_work_mem = 2 GB` | 11.0 s | 6.0 s |
| Index size | 146–194 MB | ~159 MB |
| Build-memory sensitivity | **spilled at ~28k tuples** on 64 MB → slower build | none |

Reading the numbers:

- **Build speed:** IVFFlat built ~**2× faster** than HNSW at the default memory
  setting (8.3 s vs 16.1 s), and stayed faster even with ample memory (6.0 s vs
  11.0 s). This is IVFFlat's headline advantage.
- **Build memory:** HNSW emitted
  `hnsw graph no longer fits into maintenance_work_mem after 28358 tuples` at the
  default 64 MB and slowed down; raising `maintenance_work_mem` to 2 GB cut its
  build from 16.1 s → 11.0 s. IVFFlat showed no such sensitivity. At scale, **HNSW
  build time is gated by `maintenance_work_mem`** — size it to fit the graph.
- **Index size:** comparable here (both roughly the heap size at 384 dims); HNSW
  grows with `m`, IVFFlat is driven by row count. The "HNSW larger" gap widens
  with higher `m` and higher dimensions.

Reproduce with the demo scripts ([demo-hnsw.sql](demo-hnsw.sql),
[demo-ivfflat.sql](demo-ivfflat.sql)) scaled up, or `\timing on` around a
`CREATE INDEX` on your own data.

### Estimating index size from rows & dimensions

Both indexes scale **linearly in `rows × dimensions`** — the stored vector
dominates. A `vector(d)` occupies `4·d + 8` bytes (4 bytes/float + varlena
header). Calibrated against measured sizes (pgvector 0.8.7):

```
IVFFlat ≈ rows × (4·d + 8) × 1.10                 -- ~just the vectors + ~10% overhead
HNSW    ≈ rows × (4·d + 8 + 12·m) × 1.10           -- vectors + graph links (~12·m B/row)
```

(`m` = HNSW links/node, default 16 → the graph adds ≈192 B/row before overhead.)

Calibration — formula vs actual:

| rows × dim | IVFFlat est / actual | HNSW est / actual |
|------------|----------------------|-------------------|
| 50k × 128 | 27.3 / **28 MB** | 39.2 / **39 MB** |
| 50k × 384 | 84.9 / **80 MB** | 95.5 / **97 MB** |
| 1M × 384 (m=16) | ~1.7 GB | ~1.9 GB |

Rules of thumb:

- **IVFFlat ≈ the raw vectors** (`rows × 4·d`, +~10%). `lists` adds only a handful
  of centroid rows — negligible.
- **HNSW ≈ IVFFlat + `rows × 12·m`** — roughly **15–25% larger** at 128–384 dims
  with the default `m=16`. The relative gap **shrinks** as dimensions grow (the
  `4·d` payload dominates) and **grows** if you raise `m`.
- **`halfvec`** (2-byte floats) ≈ halves both: replace `4·d` with `2·d`.
- These estimate the **index**; the table/heap also stores the vectors
  (~`rows × (4·d + 8)`) unless you only keep them in the index's table.

Quick mental math (d=384, m=16): per *million* rows, budget ≈ **1.7 GB IVFFlat /
1.9 GB HNSW** of index, plus a similar amount for the heap.

### Sizing from text: chunks × dimensions → rows × bytes

The formulas above need **rows** and **dimensions**. For a text/RAG workload those
come from two *independent* decisions:

**Row count = how you chunk the text.** Long text is split into chunks before
embedding. Chunk size is measured in **tokens** (1 token ≈ 4 characters ≈ ¾ of an
English word):

| Chunk size | Tokens | ~Chars | Use |
|-----------|--------|--------|-----|
| Small | 128–256 | 500–1,000 | precise QA/FAQ retrieval |
| **Medium (common default)** | **256–512** | **1,000–2,000** | general RAG |
| Large | 512–1,024 | 2,000–4,000 | long-form, context-heavy |

A typical default is **~500 tokens/chunk with ~10–15% overlap** (chunks share a
little boundary text so ideas aren't split). Rough rule: **1 page of prose ≈ 500
tokens ≈ 1 chunk**. Smaller chunks → more precise hits but *more rows*; larger
chunks → fewer rows but fuzzier (the embedding averages more ideas).

```
rows ≈ total_tokens / (chunk_tokens × (1 − overlap))
```

**Vector size = the model, NOT the chunk.** An embedding model emits a **fixed**
dimension regardless of how much text the chunk contains — a 100-token and a
500-token chunk both produce, e.g., a 1536-dim vector. So chunking sets the *row
count*; the model sets the *bytes per vector*:

| Model | Dim | Bytes/vector (`4·d + 8`) |
|-------|-----|--------------------------|
| MiniLM `all-MiniLM-L6-v2` | 384 | ~1.5 KB |
| OpenAI `text-embedding-3-small` | 1536 | ~6 KB |
| OpenAI `text-embedding-3-large` | 3072 | ~12 KB |
| BGE / E5 / Cohere (common) | 768–1024 | ~3–4 KB |

**Worked example — 1 GB of text (~250M tokens):**

1. Chunk at 500 tokens → `250M / 500` ≈ **500,000 chunks (rows)** (+~15% with overlap).
2. Embed with `text-embedding-3-small` (1536-dim, ~6 KB/vector).
3. Index size (from the formulas): IVFFlat ≈ `500k × 6152 × 1.1` ≈ **~3.4 GB**;
   HNSW ≈ **~3.5 GB**; plus a similar amount of heap.

Note the embeddings are often **larger than the source text** (1 GB text →
~3 GB of 1536-dim vectors). Control it by choosing a **smaller dimension** (384–768
is plenty for many apps), truncating a Matryoshka model, or using **`halfvec`** —
the dimension is the biggest lever on storage *and* memory, and (per
[embeddings-explained.md](embeddings-explained.md)) hard to change later, so pick
it deliberately.

### Recall vs speed (the correctness balance)

Both are **approximate** — they may miss true neighbors. Quality is **recall**
(fraction of the true top-k returned), tuned per query: `ef_search` for HNSW,
`probes` for IVFFlat. Higher = more recall, slower.

Measured on 20k clustered vectors, recall@10 vs exact:

| | recall@10 |
|---|---|
| HNSW `ef_search = 10` / 40 / 100 | 10/10 |
| **IVFFlat `probes = 1` (default)** | **4/10** |
| IVFFlat `probes = 5` / 20 | 10/10 |

Two lessons: HNSW reaches high recall at low settings (its strength), and the
**IVFFlat default `probes = 1` is often too low** — tune it. To measure recall
yourself, build a ground-truth top-k with the index disabled
(`SET enable_indexscan = off`) and intersect it with the indexed result.

### Use-case guidance

| Your situation | Index |
|----------------|-------|
| Real-time search / chatbot / recommendations (users waiting) | **HNSW** |
| Frequently updated corpus (docs, events, IoT) | **HNSW** (robust to churn) |
| Just starting / want a safe default | **HNSW** (mainly tune `ef_search`) |
| Very large, mostly static; periodic batch/analytics | **IVFFlat** (small, fast build) |
| Resource-constrained; care most about build time/size | **IVFFlat** |
| Need guaranteed 100% recall, small table | no index (exact scan) |

**Rule of thumb: start with HNSW.** It covers most cases well; drop to IVFFlat
when build cost, size, or memory force it. Full mechanics:
[pgvector-hnsw.md](pgvector-hnsw.md) · [pgvector-ivfflat.md](pgvector-ivfflat.md).

---

## 3. Data modeling: where does the vector column live?

Two designs, with a clear default.

### Option A — add a vector column to the existing table

```sql
ALTER TABLE documents ADD COLUMN embedding vector(384);
CREATE INDEX ON documents USING hnsw (embedding vector_cosine_ops);
```

- **Pros:** simplest; no join; the embedding travels with the row.
- **Cons:** widens a hot OLTP table with a large, frequently-rewritten column;
  every `UPDATE` of the row interacts with the vector/index; the ANN index sits on
  your primary table. Fine for modest tables where the row *is* the thing you
  search.

### Option B — separate vector table, 1:1 by primary key (recommended at scale)

Keep embeddings in their own table keyed by (and FK to) the base row, and **join
when you need both**:

```sql
CREATE TABLE doc_embeddings (
    document_id bigint PRIMARY KEY REFERENCES documents(id) ON DELETE CASCADE,
    embedding   vector(384),
    model       text NOT NULL,          -- which model+version produced it
    embedded_at timestamptz DEFAULT now()
);
CREATE INDEX ON doc_embeddings USING hnsw (embedding vector_cosine_ops);
```

Query by joining on the PK and ordering by distance (verified plan):

```sql
SELECT d.id, d.title
FROM documents d
JOIN doc_embeddings e ON e.document_id = d.id
ORDER BY e.embedding <=> :q
LIMIT 5;
```

Why this is the better default at scale:

- **Isolates the churny vector + ANN index from the OLTP table** — base-row
  updates don't touch the vector or its index, and vice-versa.
- **Independent lifecycle:** rebuild/REINDEX the vector table, or re-embed with a
  new model, without disturbing the primary table (`ON DELETE CASCADE` keeps it
  tidy). The `model` column makes a model migration detectable and scoped.
- **Optional sparsity:** rows that aren't embedded yet simply have no vector row.
- The PK=FK makes the join cheap (1:1 on an indexed key).

> Multiple models or dimensions? Give each its own table/column keyed by the same
> PK — never mix models in one `vector(N)` column (see
> [embeddings-explained.md](embeddings-explained.md) on cross-model
> compatibility).

---

## 4. Keeping vectors updated — transactionally, without slowing OLTP

An embedding is produced by an **external model**, so — unlike a `tsvector` — it
**cannot be a `GENERATED` column** (a generated column must be a pure, immutable
SQL expression; calling a model is neither). The vector must be **written by your
application or a worker.** The design question is *when*.

### The tension

- You want the vector to stay **consistent** with the source text.
- You do **not** want to block an OLTP `INSERT`/`UPDATE` on a slow embedding call
  (a model/API round-trip of tens to hundreds of ms would wreck OLTP latency and
  hold row locks).

### Anti-pattern: embed inline in the OLTP transaction

Calling the model inside the same transaction that updates the row ties OLTP
commit latency to model latency and lengthens lock hold times. Avoid for
high-throughput OLTP.

### Recommended: write a tiny marker in-transaction, embed asynchronously

Keep the OLTP transaction fast by having it record only that the row **needs**
(re)embedding; a background worker does the expensive model call and writes the
vector afterward. A trigger makes the marker automatic and transactional:

```sql
-- a small queue of rows needing (re)embedding
CREATE TABLE embedding_queue (
    document_id bigint PRIMARY KEY,
    enqueued_at timestamptz DEFAULT now()
);

CREATE FUNCTION enqueue_embedding() RETURNS trigger AS $$
BEGIN
  INSERT INTO embedding_queue (document_id) VALUES (NEW.id)
  ON CONFLICT (document_id) DO UPDATE SET enqueued_at = now();
  RETURN NEW;
END $$ LANGUAGE plpgsql;

-- fire only when the embedded text actually changes
CREATE TRIGGER trg_enqueue
  AFTER INSERT OR UPDATE OF body ON documents
  FOR EACH ROW EXECUTE FUNCTION enqueue_embedding();
```

Now an OLTP update stays fast — it only writes a tiny queue row in the same
transaction, no model call inline (verified):

```sql
UPDATE documents SET body = 'new text' WHERE id = 1;
-- embedding_queue now has (1, now()); OLTP latency unaffected
```

A worker then, out of band. **For multiple concurrent workers, the claim must use
`FOR UPDATE SKIP LOCKED`** so workers grab *different* rows instead of blocking on
each other (a plain `DELETE … RETURNING` with the same `ORDER BY ... LIMIT` makes
every worker target the same rows — they serialize on row locks, and all but one
wake up to find the rows already gone). The robust pattern combines the two:
select-with-skip-locked inside, delete-returning outside:

```sql
-- claim a BATCH of up to N rows, skipping rows other workers hold
DELETE FROM embedding_queue
WHERE document_id IN (
    SELECT document_id FROM embedding_queue
    ORDER BY enqueued_at
    FOR UPDATE SKIP LOCKED
    LIMIT 100                      -- batch size (see below)
)
RETURNING document_id;
```

```text
loop:
  claim a batch   (the DELETE ... SKIP LOCKED above, in its own short txn)
  fetch the current body for those document_ids
  call the embedding model ONCE for the whole batch (the slow part — outside any OLTP txn)
  UPSERT the vectors into doc_embeddings (with model + embedded_at)
  commit
```

The `delete`, the model call, and the `upsert` are **one transaction** that
commits at the end. This is what makes the worker crash-safe: if it dies before
`commit`, the `DELETE` rolls back and the queue row **reappears** for another
worker — no work is lost. The only cost of a crash is that the model call may have
already run, so the document gets embedded **again** on retry; that's wasted
compute, not lost data, and it's harmless because the `UPSERT` is keyed by
`document_id` (idempotent). ("Outside any OLTP txn" means the slow call is not
inside the *OLTP writer's* transaction from the trigger/enqueue path above — it's
in the worker's own transaction, which holds no OLTP row locks.)

**Transactional guarantees you keep:** the enqueue is part of the OLTP
transaction, so if that transaction rolls back, the row is *not* queued — the
queue never references uncommitted work. The embedding is **eventually
consistent**: there's a short window where the row is updated but its vector is
stale/absent, which is virtually always acceptable for semantic search.

> This is just one use of a PostgreSQL **queue table**. For the general pattern —
> `FOR UPDATE SKIP LOCKED` internals, **DELETE-on-claim vs UPDATE-to-processing**
> (reaper, retries, dead-lettering), the pros/cons of each, and when to choose
> which — see
> [**Performance/postgresql-as-queue-table.md**](../Performance/postgresql-as-queue-table.md).
> (The `DELETE`-on-claim shown here is the right fit for *this* queue: the whole
> claim→embed→upsert is one transaction, so a crashed worker's rows simply reappear
> — and a re-embed is harmless because the `UPSERT` is keyed by `document_id`.)

### Lower-latency signal: `LISTEN`/`NOTIFY`

Instead of (or with) polling the queue, the trigger can notify a listening worker
so it reacts within milliseconds:

```sql
CREATE FUNCTION notify_embedding() RETURNS trigger AS $$
BEGIN
  PERFORM pg_notify('embedding_jobs', NEW.id::text);
  RETURN NEW;
END $$ LANGUAGE plpgsql;
-- worker runs: LISTEN embedding_jobs;  and re-embeds on each notification
```

Keep the durable **queue table** as the source of truth (NOTIFY is best-effort and
not delivered to workers that aren't connected); use NOTIFY only to wake the
worker promptly. `SKIP LOCKED` lets you run several workers in parallel safely.

### Batch the embeddings — don't embed one row at a time

Embed in **batches**, not per row — it matters for both cost and throughput:

- **Cost:** hosted embedding APIs accept many texts per request and often enforce
  **request-count** limits separate from token limits. One request of 100 texts
  instead of 100 requests means ~100× fewer round-trips and far less chance of
  hitting rate caps (token cost is similar either way).
- **Throughput:** models (local or API) process a batch far more efficiently than
  N separate calls — accelerators favor batched math, and you amortize fixed
  per-call overhead (network, tokenizer, model warmup). On the DB side, one
  multi-row `UPSERT` and one queue-claim per batch means fewer transactions, less
  lock churn, and less WAL.

So the worker claims a batch (via the `SKIP LOCKED` delete), calls the model
**once** for all texts in the batch, and does **one** multi-row `UPSERT`.

Batch-size tradeoffs: bigger batches = better throughput/cost but more memory,
slower time-to-first-result, and a larger retry blast radius; smaller batches =
fresher vectors sooner and smoother retries but more overhead. **Start around 100
rows/batch with a few parallel `SKIP LOCKED` workers**, and respect the provider's
max inputs/tokens per request. Per-row embedding is only reasonable for real-time
single-item needs (e.g. embedding a user's search query) or very low volume.

### "Batch processing" ≠ "batch embedding" — a common trap

These two are different axes, and only one of them saves API round-trips. It's
easy to think you're batching when you aren't:

| Axis | What it controls | Batched here? |
|------|------------------|---------------|
| **Batch *processing*** — e.g. `SELECT … LIMIT N` claimed/processed per run | *how many rows* you attempt per invocation | often **no** API batching |
| **Batch *embedding*** — one model/API call carrying many texts | *how many texts* ride in a single call | **yes** — this is the win |

A very common pattern (seen in many tutorials) looks like bulk work but isn't:

```sql
-- "bulk" INSERT … SELECT: ONE SQL statement, but openai_embed() is a SCALAR
-- function invoked ONCE PER ROW → 100 rows = 100 separate API requests.
INSERT INTO product_embedding (product_id, embedding)
SELECT c.id, api.openai_embed(c.label || ' ' || c.description)::vector(1536)
FROM product.category c
ON CONFLICT (product_id) DO UPDATE SET embedding = EXCLUDED.embedding;
```

…and the same is true of a `FOR r IN SELECT … LIMIT batch_size LOOP … 
api.openai_embed(r.text) … END LOOP`: the `LIMIT` bounds *rows per run* (batch
*processing*), but `openai_embed` is still called once per row inside the loop —
`batch_size` API calls, made sequentially. That's **bulk DML / chunked work, not a
batched embedding call.** It's resumable and simple, but on the expensive axis
(number of API round-trips) it's identical to embedding one row at a time.

**True batch embedding** gathers the N texts into an array, makes **one** call,
gets N vectors back, then does one multi-row write:

```sql
-- requires an ARRAY-accepting embed function: text[] -> vector[]  (ONE request)
WITH batch AS (
  SELECT array_agg(c.id ORDER BY c.id)                                   AS ids,
         array_agg(c.label || ' ' || c.description ORDER BY c.id)        AS texts
  FROM product.category c
  LEFT JOIN product_embedding e ON e.product_id = c.id
  WHERE e.product_id IS NULL
), embedded AS (
  SELECT unnest(b.ids) AS product_id,
         unnest(api.openai_embed_many(b.texts)) AS embedding   -- 1 API call for all texts
  FROM batch b
)
INSERT INTO product_embedding (product_id, embedding)
SELECT product_id, embedding FROM embedded
ON CONFLICT (product_id) DO UPDATE SET embedding = EXCLUDED.embedding;
```

The difference is one HTTP request vs. N. For a local model it's the same idea —
`model.encode([t1..tN])` runs one batched forward pass instead of N.

> `openai_embed_many(text[])` must return a **`vector[]`** (an array whose
> *elements* are each a `vector(1536)`), so `unnest(...)` yields one `vector` per
> input row, paired with `unnest(ids)` by position. Keep the two `array_agg`s under
> the **same `ORDER BY`** so ids and texts (and thus the returned vectors) stay
> aligned. Real APIs cap inputs/tokens per request (OpenAI allows up to 2048
> inputs with a per-request token ceiling), so size the batch within that limit —
> or split a large claim into a few array-calls.

**Measured locally** (MiniLM, CPU, 200 rows) — per-row loop vs. one batched
`encode`, producing *identical* vectors:

```
rows                : 200
per-row (200 calls) : 1.734s   (115 rows/s)
batched (1 call)    : 0.381s   (524 rows/s)
speedup             : 4.5x
identical vectors   : True
```

Runnable demo:
[`generate_embeddings_batched.py`](../AI-Integration/generate_embeddings_batched.py)
times both paths and stores the batched result in one multi-row `UPSERT`. (Speedup
varies ~4–6× on CPU by machine; against a hosted API the win is even larger because
you collapse N network round-trips into one.)

### Provider specifics: how many texts per call? (OpenAI vs. Amazon Bedrock Titan)

The "put N texts in one request" advice assumes the API **accepts an array** — and
not every one does. This directly changes how you pick a batch size.

- **OpenAI** (`text-embedding-3-*`): `input` accepts an **array** (up to **2,048**
  elements, subject to a per-request token ceiling). So a real batch call carries
  many texts → fewer requests. Pick `batch_size` as the largest array that stays
  under both the 2,048-input and token limits.

- **Amazon Bedrock Titan** (`amazon.titan-embed-text-v2:0`): real-time
  `InvokeModel` takes a **single** `inputText` string (up to **8,192 tokens /
  50,000 characters**), **not an array** — one call embeds **one** document (output
  1,024 dims; v1 is 1,536). Crucially, Bedrock embedding models are throttled by
  **Requests Per Minute (RPM), not tokens.** So you **cannot** array-batch Titan
  real-time the way you batch OpenAI, and the lever that matters is **request
  count**, which maps to **concurrency**, not array size.

**What "batching" means for Titan, then:**

1. **Real-time + bounded concurrency (online indexing).** Since one call = one
   text, run a **pool of W concurrent `InvokeModel` calls** and size `W` to your
   RPM quota, not to an array length. Rough mental model:

   ```
   sustainable rows/min ≈ account RPM quota for the model
   workers W           ≈ RPM_quota / 60 × avg_call_seconds      (Little's law)
   ```

   e.g. a 2,000 RPM quota and ~0.3 s/call → keep ≈ `2000/60 × 0.3 ≈ 10` calls in
   flight to saturate the quota without throttling. Your DB-side "batch" (the
   `SKIP LOCKED` claim of N rows) still applies — claim N, fan those N out across
   the W workers, collect the vectors, do **one** multi-row `UPSERT`. The array
   step is on the *database* side; the *model* side is still one-text-per-call,
   parallelized.

2. **Bedrock batch inference (bulk one-time indexing).** For embedding a whole
   corpus, use **asynchronous batch inference jobs**: upload inputs to S3, Bedrock
   writes vectors back to S3, then you bulk-load them. This is the true "bulk" path
   for Titan — far higher throughput and cheaper per record, but **asynchronous**
   (minutes–hours), so it's for backfills, not the live queue.

**Picking a default more wisely:**

| Provider | Per-call input | Throttle | Batch lever | Sensible default |
|----------|----------------|----------|-------------|------------------|
| OpenAI `text-embedding-3-*` | array, ≤2,048 texts | tokens + requests | **array size** | ~100–512 texts/request under the token cap |
| Bedrock Titan v2 (real-time) | **1 text**, ≤8,192 tok | **RPM** | **concurrency W** | claim ~100 rows, fan out across `W ≈ RPM/60 × call_sec` workers |
| Bedrock Titan (batch job) | S3 file of many | job-level | whole-file | thousands+, async backfill |

So a single "`batch_size = 100`" default is right for *claiming rows* on both, but
for the *model call* it means "100 texts in one request" on OpenAI and "100 texts
spread across a concurrency pool of one-text calls" on Titan. Setting Titan's
batch size as if it array-batches (or cranking it to reduce "requests") won't
help — each text is still its own request; only concurrency moves the needle, and
only up to your RPM quota.

> Not verified against a live Bedrock endpoint here — limits (8,192 tokens /
> 50,000 chars, 1,024-dim v2, RPM throttling, single `inputText`, no array input)
> are from the [Titan Text Embeddings docs](https://docs.aws.amazon.com/bedrock/latest/userguide/titan-embedding-models.html);
> confirm your account's current RPM quota in the Bedrock console before sizing a
> worker pool.

### If you truly need read-after-write consistency

Options, in order of preference: embed in a `BEFORE` trigger only if the model is
local and fast enough (rare); or compute the embedding in the app **before**
`COMMIT` and write it in the same statement — accepting the added latency on that
path. For most systems the async queue is the right trade-off.

---

## Summary

1. Pick the metric (ruler) first; the index **operator class must match** it.
2. **HNSW** = graph, high recall, robust to updates, the **default**; **IVFFlat** =
   clusters, cheap/small build, needs data first, for large static/batch data.
   Tune recall (`ef_search` / `probes`) and **measure** — IVFFlat's default
   `probes = 1` is often too low.
3. **Data model:** prefer a **separate vector table keyed 1:1 by PK** (join on
   demand) to isolate the churny vector + ANN index from the OLTP table; a column
   on the base table is fine for small/simple cases.
4. **Updates:** embeddings can't be a `GENERATED` column — write them from an
   app/worker. Keep OLTP fast by enqueuing a **tiny marker in-transaction** (trigger)
   and embedding **asynchronously** (queue + optional `LISTEN/NOTIFY`,
   `SKIP LOCKED` for parallel workers); accept eventual consistency.
5. Deep dives: [pgvector-hnsw.md](pgvector-hnsw.md) ·
   [pgvector-ivfflat.md](pgvector-ivfflat.md); hybrid filtering:
   [hybrid-search.md](hybrid-search.md).
