# pgvector Indexes: HNSW & IVFFlat

A nearest-neighbor query —
`ORDER BY embedding <=> :q LIMIT k` — is **exact** without an index: pgvector
compares the query to *every* row. That is correct but O(rows); at millions of
vectors it is far too slow. pgvector therefore provides two indexes that find the
nearest vectors *approximately* but fast — its **ANN indexes (HNSW and
IVFFlat)**:

- **HNSW** — a multilayer proximity graph.
- **IVFFlat** — inverted lists built by k-means clustering.

**"ANN" = Approximate Nearest Neighbor** — the *category* of algorithm, not a
third index type. HNSW and IVFFlat are the two ANN indexes pgvector ships;
whenever this doc says "ANN index," it means "one of HNSW or IVFFlat." (Note: ANN
here is *not* an artificial neural network — it is purely the search technique of
finding approximately-closest vectors by skipping most of the data.)

This doc explains how each works (with animations), the **correctness vs speed**
balance they expose, how to operate them **at large scale**, and when to choose
which. Internals verified against the pgvector 0.8.7 source (`../pgvector/src`)
and behavior on PostgreSQL 18.6.

Prerequisite reading: [embeddings-explained.md](embeddings-explained.md).

---

## Operator classes (pick to match your distance)

Both index types need an operator class matching the distance you query with:

| Distance operator | Operator class |
|-------------------|----------------|
| `<->` L2 | `vector_l2_ops` |
| `<=>` cosine | `vector_cosine_ops` |
| `<#>` inner product | `vector_ip_ops` |

```sql
CREATE INDEX ON items USING hnsw    (embedding vector_cosine_ops);
CREATE INDEX ON items USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);
```

An index built for one distance does **not** serve queries using another.

---

## IVFFlat — partition, then probe

![IVFFlat](animations/ivfflat.gif)

**Build:** k-means clusters all stored vectors into `lists` cells; each list
stores a **center** (centroid) and the vectors assigned to it.

**Query:** compare the query to the `lists` **centers** only, then scan the
`probes` nearest lists and skip the rest.

```sql
CREATE INDEX ON items USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);
SET ivfflat.probes = 10;   -- query-time; default 1
```

Key facts (from `src/ivfflat.h`):

- Defaults: **`lists = 100`**, **`probes = 1`**.
- **IVFFlat needs data before you build it** — k-means has to learn the cluster
  centers from existing rows. Building on an empty/tiny table gives poor lists;
  pgvector will even warn. Load data first, then create the index.
- List-count heuristic: **`rows / 1000`** for up to 1M rows, **`sqrt(rows)`** for
  more than 1M rows.
- Probe heuristic: start around **`sqrt(lists)`**.

---

## HNSW — navigate a graph

![HNSW](animations/hnsw.gif)

**Build:** every vector is linked to its nearest neighbors, in a hierarchy of
layers. Upper layers are sparse (few nodes, long-range links) for coarse
navigation; the bottom layer holds all nodes with short links.

**Query:** greedy descent — start at the top entry point, repeatedly hop to the
neighbor closest to the query, drop a layer, repeat, until the bottom layer
yields the top-k.

```sql
CREATE INDEX ON items USING hnsw (embedding vector_cosine_ops)
  WITH (m = 16, ef_construction = 64);
SET hnsw.ef_search = 40;   -- query-time; default 40
```

Key facts (from `src/hnsw.h`):

- Defaults: **`m = 16`** (links per node), **`ef_construction = 64`** (build-time
  candidate list), **`ef_search = 40`** (query-time candidate list).
- **No training step** — unlike IVFFlat, an HNSW index can be created on an empty
  table and grows as you insert.
- Higher `m` / `ef_construction` → better recall, bigger index, slower build.

---

## The correctness vs speed balance (recall)

Both indexes are **approximate**: they may miss some true nearest neighbors. The
quality metric is **recall** — the fraction of the true top-k that the index
actually returns. Each index has a knob that trades recall for speed:

| Index | Recall knob | Effect |
|-------|-------------|--------|
| HNSW | `hnsw.ef_search` (default 40) | larger = explore more of the graph = higher recall, slower |
| IVFFlat | `ivfflat.probes` (default 1) | larger = scan more lists = higher recall, slower |

Measured on 20,000 clustered 8-dim vectors, comparing each index's top-10 against
the exact top-10 (verified on pgvector 0.8.7):

| Setting | recall@10 |
|---------|-----------|
| HNSW `ef_search = 10` | 10/10 |
| HNSW `ef_search = 40` (default) | 10/10 |
| HNSW `ef_search = 100` | 10/10 |
| **IVFFlat `probes = 1` (default)** | **4/10** |
| IVFFlat `probes = 5` | 10/10 |
| IVFFlat `probes = 20` | 10/10 |

The takeaways:

- **The defaults are not automatically "correct."** IVFFlat at the default
  `probes = 1` returned only **4 of the 10** true neighbors here — it scanned one
  list and the rest sat in neighboring lists. Raising `probes` to 5 fixed it.
  Always tune `probes` (start near `sqrt(lists)`) and measure recall.
- **HNSW reaches high recall at low settings** on this data, which is the general
  pattern: HNSW gives a better speed/recall tradeoff than IVFFlat, at the cost of
  build time and memory.
- **Exact search is still available** — just don't use the index (or set
  `ivfflat.probes = lists`), when you need guaranteed-correct results and can
  afford the scan.

### How to measure recall yourself

```sql
-- 1. ground truth: exact top-k with the index disabled
SET enable_indexscan = off;
CREATE TABLE truth AS
SELECT id FROM items ORDER BY embedding <=> :q LIMIT 10;
RESET enable_indexscan;

-- 2. approximate top-k with the index, intersect with truth
SET hnsw.ef_search = 40;   -- or ivfflat.probes = N
SELECT count(*)   -- recall@10
FROM (SELECT id FROM items ORDER BY embedding <=> :q LIMIT 10) r
JOIN truth USING (id);
```

Tune the knob up until recall meets your target, then stop (higher = slower).

> **Approximate also affects filtering.** With an ANN index, a `WHERE` filter is
> applied **after** the index returns its candidates. If the filter is selective,
> you can get fewer rows than `LIMIT`. pgvector 0.8.0+ offers **iterative index
> scans** (`hnsw.iterative_scan`, `ivfflat.iterative_scan`, bounded by
> `hnsw.max_scan_tuples` / `ivfflat.max_probes`) that keep scanning until enough
> rows pass the filter. See [hybrid-search.md](hybrid-search.md).

---

## Operating at large scale

The two indexes behave very differently once you reach millions of vectors with
hundreds of dimensions. Plan for these:

### Build time & memory

- **HNSW builds are slow and memory-hungry.** The graph should fit in
  `maintenance_work_mem` during build; if it doesn't, pgvector falls back to a
  much slower on-disk build. For large tables raise it substantially for the
  session:
  ```sql
  SET maintenance_work_mem = '8GB';   -- size to your data / RAM
  ```
- **Parallel builds.** Both support parallel index builds; more workers shorten
  wall-clock build time:
  ```sql
  SET max_parallel_maintenance_workers = 7;   -- + planner/worker settings
  ```
- **IVFFlat builds much faster** and uses less memory, but recall depends on
  good `lists` and enough data for k-means. At >1M rows use `lists ≈ sqrt(rows)`.
- **Load-then-index** for IVFFlat (needs the data); for HNSW, bulk-loading data
  first and building the index afterward is still far faster than inserting into
  an existing HNSW index row by row.

### Memory at query time

- HNSW query speed assumes the index is in RAM/cache. If the index is much larger
  than `shared_buffers` + OS cache, latency degrades as it reads from disk. Size
  memory to keep the hot index resident, or shard.
- Consider **`halfvec`** (2-byte floats) to roughly halve index size/memory at a
  small recall cost — valuable at scale and for dimensions up to the type limits
  (`vector`/`halfvec` max 2000 dims).

### Maintenance

- **HNSW vacuum can be slow;** reindexing is often faster than vacuuming a heavily
  updated HNSW index. Schedule accordingly.
- Heavy update/delete churn degrades recall over time (dead tuples, graph
  disconnection); periodic `REINDEX` restores it.
- IVFFlat lists drift as data distribution changes; if the corpus grows or shifts
  a lot after the initial k-means, **rebuild** to recluster.

### Choosing parameters at scale (starting points)

| | HNSW | IVFFlat |
|---|------|---------|
| Build cost | high (time + memory) | low |
| Query speed/recall | best tradeoff | good, needs tuning |
| Memory | high | lower |
| Key build params | `m=16`, `ef_construction=64` (↑ for recall) | `lists ≈ rows/1000`, then `sqrt(rows)` >1M |
| Key query param | `ef_search` (↑ for recall) | `probes ≈ sqrt(lists)` (↑ for recall) |
| Rebuild trigger | heavy churn | distribution shift / big growth |

---

## When to use which

**Default to HNSW** for most production vector search: it gives the best
speed/recall tradeoff, needs no training step, and handles incremental inserts
well. Accept its slower, memory-heavier build.

**Choose IVFFlat** when:

- build time / memory are constrained and you can afford to tune `probes`,
- you can (re)build after the data is loaded and relatively stable,
- the dataset is large and you want a smaller, cheaper-to-build index.

**Use no index (exact)** for small tables (a few thousand rows) or when 100%
recall is mandatory and latency allows — the planner will scan, which is correct
by definition.

Whatever you pick: **match the operator class to your distance, tune the recall
knob and measure recall, and size memory for build and query.**

---

## Summary

1. ANN indexes trade exactness for speed; quality is measured as **recall**.
2. **IVFFlat** = k-means lists + `probes`; needs data before build; default
   `probes = 1` is often too low (measured 4/10 recall) — tune toward
   `sqrt(lists)`.
3. **HNSW** = multilayer graph + `ef_search`; no training step; best speed/recall
   but slower, heavier builds.
4. At **large scale**: raise `maintenance_work_mem`, use parallel builds,
   load-then-index, consider `halfvec`, keep the index in memory, and
   `REINDEX`/rebuild to recover recall after churn.
5. Match the **operator class** to the distance; measure recall; prefer **HNSW**
   unless build cost/memory push you to **IVFFlat**.
