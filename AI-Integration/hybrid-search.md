# Hybrid Search: combining pgvector with scalar filters & full-text

Pure vector search answers "what is semantically closest?" Real applications
usually also need "...**and** matches these conditions" — in stock, under a
price, in a category, or containing a keyword. **Hybrid search** combines a
pgvector similarity `ORDER BY` with ordinary SQL predicates.

This doc covers two patterns, with plans verified on PostgreSQL 18.6 +
pgvector 0.8.7:

1. **Scalar filter (B-tree) + vector KNN** — e.g. `price < 100 AND category = …`
2. **Full-text filter (GIN) + vector KNN** — e.g. description must match a keyword

The central issue in both is **where the filter runs relative to the approximate
index scan** — get this wrong and you silently get too few (or zero) results.

Prerequisites: [embeddings-explained.md](embeddings-explained.md),
[pgvector-indexes.md](pgvector-indexes.md).

> Throughout, **"ANN index" means one of pgvector's two approximate-nearest-
> neighbor indexes — HNSW or IVFFlat** (see
> [pgvector-indexes.md](pgvector-indexes.md)). It is not a separate index type.

---

## The core problem: filtering happens AFTER the ANN scan

With an approximate index (HNSW/IVFFlat), pgvector first fetches its nearest-
neighbor candidates (bounded by `hnsw.ef_search` / `ivfflat.probes`), **then**
applies your `WHERE` filter to those candidates. If the matching rows aren't
among the candidates, they're gone — the filter can't pull in rows the index
never returned.

Verified — the same shape, two outcomes on identical data (20k rows, HNSW,
`ef_search = 40`):

```sql
-- query vector sits in the 'sports' cluster
SELECT id FROM products WHERE category = 'electronics'
ORDER BY embedding <=> :q LIMIT 5;
```
```
 Limit (actual rows=0)                         <- ZERO results!
   ->  Index Scan using idx_prod_hnsw on products
         Order By: (embedding <=> :q)
         Filter: (category = 'electronics')
         Rows Removed by Filter: 40            <- all 40 candidates were filtered out
```

The 40 nearest vectors to the query were all *sports* items; none were
electronics, so after filtering, **nothing** remained — even though the table has
4,000 electronics rows. The vector index had no reason to return far-away
electronics vectors.

The same query filtered to `category = 'sports'` (the cluster the query is in)
returns a full 5/5. So post-filtering works great **when the filter correlates
with the query region** and fails badly when it doesn't.

### Principle: filter early, rank later

Vector similarity is **expensive** — it computes a distance across up to
thousands of dimensions for every candidate row. A SQL filter (especially an
indexed one) is **cheap** by comparison. So the goal is to shrink the candidate
set with the cheap filter *before* doing the heavy distance math — "only compare
against people in this neighborhood," not the whole city.

The good news: **PostgreSQL's cost model already does this automatically when the
filter is selective enough.** Verified on 50k rows — the plan flips based on
selectivity:

```sql
-- SELECTIVE filter (~0.1%): planner filters EARLY via the scalar index,
-- then ranks the few survivors by exact distance (100% recall)
EXPLAIN SELECT id FROM items WHERE tenant < 50 ORDER BY embedding <=> :q LIMIT 5;
--  Sort  (Sort Key: embedding <=> :q)
--    ->  Index Scan using items_tenant_idx   (Index Cond: tenant < 50)   <- filter first

-- NON-selective filter (~20%): planner uses the HNSW index first and applies
-- the filter AFTER (filtering early wouldn't pay off on 10k rows)
EXPLAIN SELECT id FROM items WHERE category = 'a' ORDER BY embedding <=> :q LIMIT 5;
--  Index Scan using items_embedding_idx   (Order By: embedding <=> :q)
--    Filter: (category = 'a')                                            <- rank first
```

So the actionable part is not to *force* a filter-first plan, but to **make
filtering early possible and cheap**:

- **Index the filter columns** (B-tree for scalars, GIN for `tsvector`) so the
  planner has a cheap early-filter option.
- **Keep filters selective** — the more a filter narrows the set, the more likely
  (and more beneficial) the filter-early plan.
- When the filter is selective, you also get **exact** results for free (the
  survivors are distance-sorted directly, no ANN approximation).

The three strategies below are the concrete forms this takes; the planner chooses
among them by cost, and you can also force the outcome.

---

## Pattern 1: scalar filter (B-tree) + vector KNN

```sql
CREATE INDEX ON products USING hnsw (embedding vector_cosine_ops);
CREATE INDEX ON products (category);
CREATE INDEX ON products (price);
```

### Strategy A — post-filter (vector index first)

The default when the filter is **not** very selective. Fast, but can under-return
(above). Mitigate with **iterative scans** (pgvector 0.8.0+), which keep scanning
the index until `LIMIT` rows pass the filter:

```sql
SET hnsw.iterative_scan = relaxed_order;   -- or strict_order; off by default
-- bounded by hnsw.max_scan_tuples (HNSW) / ivfflat.max_probes (IVFFlat)
SELECT id FROM products WHERE category = 'sports'
ORDER BY embedding <=> :q LIMIT 10;
```

Verified: a selective filter that risks returning fewer than `LIMIT` rows is
backfilled to the full 10 once iterative scan is enabled.

### Strategy B — pre-filter (scalar index first, then exact rerank)

When the filter is **highly selective**, the planner skips the ANN index, uses
the B-tree to grab the few matching rows, and ranks them by exact distance.
Verified — `price < 6.0` (≈0.25% of rows):

```sql
EXPLAIN (ANALYZE) SELECT id, price FROM products
WHERE price < 6.0 ORDER BY embedding <=> :q LIMIT 5;
```
```
 Limit
   ->  Sort  (Sort Key: (embedding <=> :q))          <- exact distance sort
         ->  Bitmap Heap Scan on products
               Recheck Cond: (price < 6.0)
               ->  Bitmap Index Scan on idx_prod_price    <- B-tree picks the few rows
```

This is **exact** (100% recall) because it distance-sorts the full filtered set —
ideal when the filter leaves few rows.

### Strategy C — partial ANN index (per common filter value)

If one filter value is queried constantly, build an ANN index **scoped** to it, so
you get approximate-index speed *within* that subset:

```sql
CREATE INDEX idx_prod_hnsw_elec ON products USING hnsw (embedding vector_cosine_ops)
  WHERE category = 'electronics';
```

Verified — a `category = 'electronics'` query uses it directly:

```
 Limit
   ->  Index Scan using idx_prod_hnsw_elec on products
         Order By: (embedding <=> :q)
```

No post-filter loss, because the index *is* the electronics subset. Costs one
index per value, so reserve it for a few hot filters.

### Choosing

| Filter selectivity | Best strategy |
|--------------------|---------------|
| Low (matches many rows) | A: post-filter (optionally iterative scan) |
| High (matches few rows) | B: pre-filter + exact rerank (planner usually auto-picks) |
| One hot value, queried a lot | C: partial ANN index |

---

## Pattern 2: full-text (GIN) + vector KNN

Combine semantic ranking with a keyword requirement — "closest vectors **whose
text contains `leather`**." Use a `tsvector` + GIN index (see
[../Development/FullTextSearch/full-text-search.md](../Development/FullTextSearch/full-text-search.md))
alongside the vector index.

```sql
ALTER TABLE products ADD COLUMN description_tsv tsvector
  GENERATED ALWAYS AS (to_tsvector('english', coalesce(description,''))) STORED;
CREATE INDEX ON products USING gin (description_tsv);
```

Query — full-text predicate + vector order-by:

```sql
EXPLAIN (ANALYZE) SELECT id, description FROM products
WHERE description_tsv @@ to_tsquery('english','leather')
ORDER BY embedding <=> :q LIMIT 5;
```
```
 Limit (actual rows=5)
   ->  Index Scan using idx_prod_hnsw on products
         Order By: (embedding <=> :q)
         Filter: (description_tsv @@ 'leather'::tsquery)
         Rows Removed by Filter: 5
```

Same post-filter behavior: pgvector walks nearest vectors and keeps those whose
text matches. The strategies mirror Pattern 1:

- **Keyword matches many rows** → post-filter (this plan); enable iterative scan
  if you risk under-returning.
- **Keyword is rare** → let the planner pre-filter via the **GIN** index and
  exact-rank the survivors by distance (analogous to Strategy B — GIN replaces the
  B-tree).
- **Two-stage application query** — retrieve by full-text first, then re-rank the
  top candidates by vector distance (or vice-versa), when you want explicit
  control over how many candidates each stage produces.

> **Weighted hybrid scoring.** Beyond filtering, you can *blend* lexical and
> semantic relevance — e.g. `ORDER BY (0.5 * ts_rank(description_tsv, q_text)) +
> (0.5 * (1 - (embedding <=> q_vec)))`. This computes on the candidate set (not
> indexed), so pre-narrow with a filter or a two-stage query first. **But adding
> raw scores directly is usually wrong** — see *rank fusion* (RRF) below for
> blending two *searches*, and *Scoring is a business decision* for blending
> similarity with business signals.

---

## Pattern 3: true hybrid ranking with Reciprocal Rank Fusion (RRF)

Patterns 1–2 use one method to **filter** and the other to **order**. True hybrid
*ranking* instead runs **both** searches independently and **merges their ranked
result lists** — getting semantic recall (vector) *and* exact-token precision
(full-text / BM25) in one query, inside one database, with no external search
engine to sync.

### Why you can't just add the scores

Vector distance (`<=>`, ~0–2) and full-text score (`ts_rank_cd`, an unbounded
frequency-based number) live on **completely different scales**. Summing or
averaging them lets whichever metric happens to have larger numbers dominate, and
the weights are impossible to tune robustly.

**Reciprocal Rank Fusion (RRF)** sidesteps this: it ignores the raw scores and
fuses the **rank positions** instead. Each method contributes `1 / (k + rank)`
for a document (rank 1, 2, 3, …), and the contributions are summed. Because it
only uses ordinal rank, the scale mismatch disappears entirely. `k` is a damping
constant; **`k = 60` is the common default**.

```
rrf_score(doc) = Σ over methods of   1 / (k + rank_in_that_method)
```

A document ranked highly by *both* methods accumulates the most; a document found
by only one still scores (via `COALESCE(..., 0)` for the method that missed it).

### The query (verified on pgvector 0.8.7)

Setup — vector + a generated `tsvector`, each with its own index:

```sql
CREATE TABLE documents (
    id          serial PRIMARY KEY,
    title       text,
    content     text,
    embedding   vector(1536),                       -- e.g. text-embedding-3-small
    tsv_content tsvector GENERATED ALWAYS AS (to_tsvector('english', content)) STORED
);
CREATE INDEX ON documents USING hnsw (embedding vector_cosine_ops);  -- semantic
CREATE INDEX ON documents USING gin  (tsv_content);                  -- lexical
```

Fuse the two ranked lists with a `FULL OUTER JOIN` + RRF:

```sql
WITH vector_search AS (
    SELECT id, ROW_NUMBER() OVER (ORDER BY embedding <=> :q_vec) AS rank
    FROM documents
    ORDER BY embedding <=> :q_vec
    LIMIT 20
),
text_search AS (
    SELECT id, ROW_NUMBER() OVER (
             ORDER BY ts_rank_cd(tsv_content, to_tsquery('english', :q_text)) DESC) AS rank
    FROM documents
    WHERE tsv_content @@ to_tsquery('english', :q_text)
    ORDER BY ts_rank_cd(tsv_content, to_tsquery('english', :q_text)) DESC
    LIMIT 20
)
SELECT d.id, d.title,
       COALESCE(1.0/(60.0 + v.rank), 0.0)         -- vector contribution (k=60)
     + COALESCE(1.0/(60.0 + t.rank), 0.0) AS rrf_score   -- text contribution
FROM vector_search v
FULL OUTER JOIN text_search t ON v.id = t.id       -- keep docs found by either
JOIN documents d ON d.id = COALESCE(v.id, t.id)
ORDER BY rrf_score DESC
LIMIT 10;
```

Verified behaviour (small demo set): documents matched by **both** searches rose
to the top with the highest RRF scores, documents matched by only one ranked
below, and one-sided matches were handled correctly by the `FULL OUTER JOIN` +
`COALESCE` (a document the AND text query missed simply contributed 0 from the
text side). The scale mismatch never appears because only ranks are combined.

### Notes

- Each subquery is independently indexable: the vector CTE uses the **HNSW**
  index, the text CTE uses the **GIN** index. Keep each `LIMIT` (e.g. 20) small —
  RRF only needs each method's top-N.
- **Tune `k`:** larger `k` flattens the contribution of top ranks (more democratic
  across methods); smaller `k` rewards being #1 more sharply. 60 is a fine start.
- **Weight a method** by multiplying its term, e.g.
  `1.5 * COALESCE(1.0/(60+v.rank),0)` to favor semantic hits.
- This is the native, single-database alternative to running a separate lexical
  engine (Elasticsearch/OpenSearch) beside your vector store — no cross-system
  sync. For the full-text side details see
  [../Development/FullTextSearch/full-text-search.md](../Development/FullTextSearch/full-text-search.md).

### Does RRF use a `BitmapAnd` (like the §9 filter case)?

**No — and it structurally can't.** Unlike the scalar-filter case in §9 (where the
planner can `BitmapAnd` a GIN and a B-tree), the RRF query runs **two separate
index scans that are joined**, not intersected. The verified plan:

```
Sort (by rrf_score)
  Nested Loop                                    -- fetch titles by id
    Hash Full Join   (Hash Cond: v.id = t.id)    -- FUSION happens here
      ├─ vector CTE:  Index Scan using ..._embedding_idx   (HNSW, Order By <=>)
      └─ text CTE:    Bitmap Heap Scan
                        -> Bitmap Index Scan on ..._tsv_content_idx   (GIN @@)
```

Each branch uses its **own** index (HNSW for the vector CTE, GIN for the text CTE),
and the results are combined by a **`Hash Full Join`** on `id`. Three reasons a
`BitmapAnd` cannot apply:

1. **The vector side has no predicate — it's `ORDER BY … LIMIT`.** `embedding <=> q`
   *orders* rows and takes the top-N; it does not select a row set. HNSW yields a
   ranked top-N, not a bitmap to intersect. (KNN is an **ordering** operation;
   bitmaps are for **set membership** — the deep reason.)
2. **It's a `FULL OUTER JOIN` (union-like), not an AND.** RRF deliberately keeps
   documents found by *either* method (that's what `COALESCE(…,0)` is for).
   `BitmapAnd` computes an intersection — the opposite of what RRF needs.
3. **The scans carry *ranks*, not just row IDs.** Each branch computes
   `ROW_NUMBER()` over its own ordering; a bitmap holds no position info, so fusion
   must happen at the tuple level (the join), after each side has ranked.

`BitmapAnd` only shows up when both conditions are **predicates over the same
table scan** (§9: `@@ q AND price < 50`) — and even there the vector KNN part never
participates, only scalar/text predicates do. The RRF plan is nonetheless
efficient: each side is capped by a small `LIMIT` (e.g. 20), so the `Hash Full
Join` works on tiny inputs (~20+20 rows) — measured ~7.5 ms on 20k rows.

---

## Scoring is a business decision, not just arithmetic

"Most similar" is often **not** "best." Real applications blend vector similarity
with **business signals** stored as ordinary SQL columns — margin, popularity,
rating, freshness/recency, risk, compliance flags — into one ranking score:

```sql
SELECT name,
       0.6 * (1 - (embedding <=> :q))   -- semantic similarity (0..1)
     + 0.4 * margin_score               -- business signal (SQL column)
       AS final_score
FROM products
WHERE category = 'Swimwear'
ORDER BY final_score DESC
LIMIT 10;
```

Verified behaviour: two items that were **equally similar** (similarity 1.000)
ranked *differently* once margin was folded in (final 0.960 vs 0.720) — and an
item with the best *rating* was buried because the weights didn't include rating.
That is the whole point: **the weights `(0.6, 0.4)` and which signals you include
encode a business policy, not a mathematical truth.**

So treat the scoring model as a product/business decision, not a formula to copy:

- **Which signals matter** differ by domain — retail may weight margin and stock;
  support may weight recency; fraud/insurance may weight *risk first* ("similar
  case **and** higher fraud risk"); maintenance may boost recent fixes
  (`0.7*similarity + 0.3*freshness`).
- **The weights are tunable knobs**, ideally driven by business goals and
  A/B-tested — not guessed once and frozen. A 70/30 vs 50/50 split can change the
  whole result order.
- **Normalize before combining.** Similarity (`1 - (… <=> …)`) is 0..1, but a raw
  `margin_score`, price, or rating may be on any scale — scale each signal to a
  comparable range first, or the biggest-magnitude term silently dominates. (When
  you only have *ranks* rather than scores, use RRF above instead.)
- **Make it explainable.** Return the component scores (similarity, margin, …)
  alongside `final_score` so the ranking can be justified, debugged, and tuned —
  important in regulated domains.

In short, PostgreSQL computes similarity, applies the SQL rules, blends the score,
and returns ranked results in one query — but *what* to blend and *how much* is a
business judgment the customer must own.

> **These signals usually live in other tables.** The blended/filtered columns
> (inventory, pricing, user profile, brand, compliance) don't have to sit in the
> same row as the embedding — join to them. A vector query joins to any related
> table just like normal SQL, e.g. gate by live stock
> (`JOIN inventory i ON i.product_id = p.id WHERE i.stock > 0`), or even compare an
> item embedding against a **different table's** vector — personalization ranks
> `product.embedding <-> user.preference_vec` by joining `products` to a `users`
> row's taste vector. One query, one plan, across all the tables.

---

## Large-scale deployment notes

At millions of rows the filter/scan interaction dominates performance:

- **Selective filters are the trap.** Post-filtering after an ANN scan returns
  too few rows when the filter is selective and uncorrelated with the query
  region (the zero-result case above). At scale, prefer **iterative scans**, a
  **partial index** per hot filter, or **pre-filtering** when the filter is
  selective.
- **Iterative scans cost more work** the more they re-scan; bound them with
  `hnsw.max_scan_tuples` / `ivfflat.max_probes` and monitor latency. They trade
  completeness for time.
- **Partition to turn filters into pruning.** If you always filter by a
  low-cardinality column (tenant, category, language), **partition by it** so each
  query hits one partition's smaller vector index — this converts a post-filter
  problem into partition pruning and keeps each HNSW graph smaller and in memory.
- **Raise `ef_search` / `probes` under filtering** so the candidate pool is large
  enough that filtered results still fill `LIMIT` — at the cost of latency. Tune
  and measure recall (see [pgvector-indexes.md](pgvector-indexes.md)).
- **Composite / covering indexes.** For scalar + vector, a B-tree on the filter
  column plus the HNSW index lets the planner choose pre- vs post-filter per
  query; keep both and let cost decide.
- **Memory still rules.** Keep the (possibly partial/partitioned) vector index in
  RAM; a filter doesn't help if the ANN graph is paging from disk.

---

## Summary

1. With ANN indexes, **filters are applied *after* the vector scan** — a selective,
   uncorrelated filter can return far fewer rows than `LIMIT` (even zero).
2. **Scalar + vector:** post-filter (low selectivity, add iterative scan),
   pre-filter + exact rerank (high selectivity — planner usually auto-picks), or a
   **partial HNSW index** for a hot filter value.
3. **Full-text + vector:** a `tsvector` GIN predicate with a vector `ORDER BY`;
   same strategies, with optional weighted lexical+semantic scoring on the
   candidate set.
4. **Rank fusion (RRF):** to truly *blend* semantic + lexical relevance, run both
   searches and merge their **ranks** with `1/(k+rank)` (k≈60) — never add the raw
   scores (different scales). Native single-DB alternative to a separate lexical
   engine.
5. **Scoring is a business decision:** blend similarity with SQL business signals
   (margin, rating, freshness, risk) via weighted `final_score` — but the signals
   and weights encode business policy (normalize scales, make it explainable,
   A/B-test), not fixed math. Signals can live in **other tables** — join to them
   (inventory/users/pricing), including comparing an item vector to a user's
   preference vector.
6. **At scale:** prefer partitioning by common filter columns, use iterative scans
   with bounds, raise `ef_search`/`probes` under filtering, and keep indexes in
   memory. Always `EXPLAIN (ANALYZE)` and watch **`Rows Removed by Filter`**.
