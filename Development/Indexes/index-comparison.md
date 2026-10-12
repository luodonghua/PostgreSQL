# PostgreSQL index types — comparison

PostgreSQL's built-in index access methods. **B-tree** is the default,
general-purpose index for scalar, orderable values. **Hash** is equality-only.
**BRIN** is a tiny summary index for huge, physically-ordered tables. **GIN**,
**GiST**, and **SP-GiST** are *frameworks* for complex / non-scalar data: the
machinery is generic and the behavior comes from a data-type opclass. This doc
summarizes how they differ and which to pick.

Detailed docs: [btree.md](btree.md) · [hash.md](hash.md) · [brin.md](brin.md) ·
[gin.md](gin.md) · [gist.md](gist.md) · [spgist.md](spgist.md)

## Do the others replace B-tree, or complement it?

**They complement it.** B-tree is not going anywhere — the rest are specialized
tools for cases B-tree handles poorly or cannot handle, not replacements.

- **B-tree** answers questions about a **single orderable scalar**: equality
  (`=`), ranges (`<`, `<=`, `>`, `>=`, `BETWEEN`), `ORDER BY`, `MIN`/`MAX`, and
  prefix `LIKE 'abc%'`. It is the right choice for the vast majority of columns
  (IDs, timestamps, names, foreign keys) and is almost always the default.
- The others exist for cases a single-value ordered key serves poorly: **Hash**
  for pure equality on large keys; **BRIN** for huge append-only tables; and
  GIN/GiST/SP-GiST for composite values, spatial overlap, nearest-neighbor, and
  hierarchical data.

```
Pick an index:
  single orderable scalar, need =, <, >, ORDER BY, MIN/MAX ?  → B-tree (default)
  pure equality only, on a LARGE key ?                        → Hash
  huge table, column CORRELATED with physical row order ?     → BRIN
  composite value (array / JSONB / tsvector) ?                → GIN
  geometry / ranges / overlap / nearest-neighbor ?            → GiST
  points / tries / prefixes / hierarchy ?                     → SP-GiST
```

A single table routinely mixes them: a B-tree on `id`, a BRIN on an append-only
`created_at`, a GIN index on a `tags text[]` or `profile jsonb` column, a GiST
index on a `geom` column — each serving queries the others can't.

## One-paragraph summary

- **B-tree** — a *balanced, ordered tree of single scalar keys*. The default for
  equality, range, and ordered scans on comparable values.
- **Hash** — maps a value's *hash code* to a bucket for O(1)-ish **equality
  only**; stores just the hash code, so it's compact for large keys.
- **BRIN** — stores one tiny *(min,max) summary per block range*; a lossy,
  minuscule index for **huge tables correlated with physical order**.
- **GIN** — an *inverted index*: breaks each value into keys and maps every key
  to the rows containing it. Best for **composite** values (JSONB, arrays,
  full-text).
- **GiST** — a *balanced tree of bounding predicates* that may **overlap**. A
  general R-tree-like structure for geometry, ranges, text, nearest-neighbor, and
  exclusion constraints.
- **SP-GiST** — a *non-balanced tree of non-overlapping partitions* (quadtree,
  k-d tree, radix trie). Best for **point data** and **hierarchical / prefix**
  data where GiST's overlapping boxes hurt.

## Structural comparison

```
B-tree — balanced ordered tree          Hash — value hashed to a bucket
      [ 50 | 100 ]  (separators)         hash(v) mod N ─► bucket
       /     |     \                       bucket0 bucket1 bucket2 …
   [..50] [50..100] [100..]                 └ (hashcode, ctid) entries,
   sorted leaf pages, linked L→R              overflow pages when full
   one scalar key per entry → TID           equality ONLY; stores hashcode

BRIN — one summary per page range        GIN  — inverted index
  heap: [r0][r1][r2][r3] (by order)      key ─┬─► {r1, r3, r9}  (posting)
  BRIN: [1,3][3,6][6,9][9,12] (min,max)  key ─┼─► {r2, r7}
  tiny; skip ranges that can't match     key ─┴─► posting tree (many rows)
  lossy -> bitmap scan + recheck          each key stored ONCE

GiST — overlapping bounding tree         SP-GiST — non-overlapping partitions
   [ box covering all ]                        centroid / prefix
      /            \                           ┌────┬────┬────┐
 [box A..D]      [box M..Z]  ← may overlap     │ q1 │ q2 │ q3 │ …  one partition
   /   \           /   \                       └─┬──┴─┬──┴─┬──┘    per value
 leaf  leaf      leaf  leaf → TIDs             inner / leaf chains  (NOT balanced)
```

## Decision table

| Dimension | B-tree | Hash | BRIN | GIN | GiST | SP-GiST |
|-----------|--------|------|------|-----|------|---------|
| Data model | balanced ordered tree | value→bucket | per-range min/max | inverted key→rows | overlapping predicate tree | disjoint partition tree |
| Balanced? | yes | n/a (buckets) | n/a (flat summaries) | yes | yes | **no** |
| Best for | scalar `=`,`<`,`>`,`ORDER BY` | pure `=` on large keys | huge correlated tables | composite values | geometry/ranges/overlap/KNN | points/tries/prefixes |
| Equality on a scalar | **yes** | **yes** | yes (lossy) | no | no | no |
| Range (`<`,`BETWEEN`) | **yes** | **no** | yes (lossy) | no | ranges opclass | yes |
| Sorted output (`ORDER BY`) | **yes** | no | no | no | no | no |
| Prefix `LIKE 'abc%'` | **yes** | no | no | no | via `pg_trgm` | yes (radix) |
| JSONB / arrays | no | no | no | **yes** | limited | no |
| Full-text `tsvector` | no | no | no | **yes** | yes | no |
| Geometry / spatial | no | no | bounding (incl. opclass) | no | **yes** | yes (points) |
| Range types | no | no | no | no | **yes** | yes |
| Nearest-neighbor (`<->`) | no | no | no | no | **yes** | **yes** |
| Exclusion constraints | `=` only | no | no | no | **yes** | no |
| Unique constraints | **yes** | no | no | no | no | no |
| Lossy (heap recheck)? | no | yes (hash collisions) | **always** | often | yes | depends |
| Index size | compact | small (hashcode only) | **tiny** | compact | moderate | compact |

## Performance characteristics

| Aspect | B-tree | Hash | BRIN | GIN | GiST | SP-GiST |
|--------|--------|------|------|-----|------|---------|
| Read speed | fast `=`/range | fast `=` | fast on correlated ranges | fast containment | depends on overlap | fast points/prefixes |
| Update cost | low | low | **very low** | **high** (eased by `fastupdate`) | moderate | moderate |
| Index size | compact | small | **minuscule** | compact | moderate | compact |
| Build speed | very fast | fast | **very fast** | fast bulk | sorted/buffering | one-by-one |
| Degrades when | — | ranges/order needed | column not correlated | pending list large | overlapping boxes | skewed data |

## How each handles the same JSONB/text problem

- **JSONB containment** (`profile @> '{"a":1}'`): use **GIN**. It extracts keys
  from the document and intersects posting lists. `jsonb_path_ops` is smaller and
  faster for `@>` but always rechecks; `jsonb_ops` also supports key-existence
  (`?`, `?|`, `?&`).
- **Full-text search**: **GIN** is the default (fast search, slower updates);
  **GiST** is an option when the document set changes rapidly and search latency
  matters less (GiST uses a lossy signature so it rechecks more).
- **Trigram `LIKE '%foo%'`**: both **GIN** and **GiST** via `pg_trgm`; GIN for
  read-heavy, GiST when you also want KNN similarity ordering (`<->`).
- **Prefix matching on text** (`col ~<~ 'abc'`): **SP-GiST** radix tree is a
  natural fit.
- **"5 nearest points"** (`ORDER BY geom <-> p LIMIT 5`): **GiST** or **SP-GiST**
  (both support distance-ordered scans); GIN cannot.

## Three ways to index a scalar column: B-tree vs Hash vs BRIN

All three apply to an ordinary scalar column, but they trade very differently:

```
B-tree : full-featured. =, <, >, BETWEEN, ORDER BY, MIN/MAX, unique.
         Compact and robust. The default — pick it unless you have a reason not to.

Hash   : equality ONLY (no ranges, no ordering). Stores just the 4-byte hash
         code, so it can be smaller than a B-tree when the key is large (long
         text, big values). Needs a heap recheck for collisions.

BRIN   : NOT per-row. Stores one (min,max) per block range -> a minuscule index.
         Only effective when the column's values track physical row order
         (append-only timestamps, serial ids). Lossy: bitmap scan + recheck.
         Perfect for huge tables where a B-tree would be large and costly.
```

Rule of thumb for a scalar column: **default to B-tree**; choose **Hash** only
for pure-equality lookups on a large key; choose **BRIN** for a very large table
whose indexed column is strongly correlated with insert order.

## Why GiST and SP-GiST both exist

Both index spatial/complex data, but with opposite philosophies:

```
GiST:     children may OVERLAP; a search may need to descend SEVERAL subtrees.
          Flexible, balanced, handles ranges/boxes/overlap and exclusion
          constraints. Overlap can blur selectivity.

SP-GiST:  partitions are DISJOINT; a search usually descends ONE path.
          Sharper pruning for points and tries, but the tree is unbalanced,
          so skewed data can produce deep branches.
```

Rule of thumb: **boxes/ranges that overlap → GiST; points or prefixes that
partition cleanly → SP-GiST.**

## Shared mechanics (GIN / GiST / SP-GiST)

The three framework methods (not B-tree, which has fixed comparison semantics)
share:

- All are opclass-driven frameworks (no hard-coded operators).
- All are WAL-logged and crash-safe, with their own `*xlog.c` replay code.
- All support multicolumn indexes and (GiST/SP-GiST) `INCLUDE` columns.
- All can be **lossy** and rely on an executor recheck of the heap tuple.
- All three were originally authored by Teodor Sigaev and Oleg Bartunov.

(B-tree is also WAL-logged, crash-safe, multicolumn- and `INCLUDE`-capable, but
it is not opclass-generalized the same way and is never lossy.)

## Quick picker

```
Scalar =, <, >, BETWEEN, ORDER BY, MIN/MAX, LIKE 'abc%'?  → B-tree (default)
Pure equality on a large key, no ranges/order?           → Hash
Huge table, column correlated with physical order?       → BRIN
Indexing JSONB / arrays / full-text, read-heavy?         → GIN
Need containment + key-existence on JSONB?               → GIN (jsonb_ops)
Smallest/fastest JSONB @> only?                          → GIN (jsonb_path_ops)
Geometry, ranges, overlap, OR exclusion constraints?     → GiST
Nearest-neighbor on boxes/ranges?                        → GiST
Point data, or want disjoint partitions?                 → SP-GiST
Text prefix / radix / IP hierarchy?                      → SP-GiST
Nearest-neighbor on points?                              → GiST or SP-GiST
```

## Measured index sizes

A quick sanity check of the size differences, on a 50,000-row table
(PostgreSQL 18.6), index on a timestamp/id column:

| Index | Size |
|-------|------|
| BRIN (on correlated timestamp) | **24 kB** |
| B-tree (on id) | 1112 kB |
| Hash (on id) | 2064 kB |

BRIN is ~45× smaller than the B-tree here, and the gap grows with table size —
the trade-off being BRIN's lossy, correlation-dependent scans versus B-tree's
exact, fully-featured lookups.
