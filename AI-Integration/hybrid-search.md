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

There are three strategies to handle this. The planner chooses among them by
cost; you can also force the outcome.

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
> indexed), so pre-narrow with a filter or a two-stage query first.

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
4. **At scale:** prefer partitioning by common filter columns, use iterative scans
   with bounds, raise `ef_search`/`probes` under filtering, and keep indexes in
   memory. Always `EXPLAIN (ANALYZE)` and watch **`Rows Removed by Filter`**.
