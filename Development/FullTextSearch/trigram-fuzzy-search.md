# Trigram Similarity Search & Fuzzy Matching (`pg_trgm`)

Full-text search (`tsvector`/`@@`) and `LIKE` both rely on **correct spelling** —
a single typo (`Uniclo` for `Uniqlo`) returns zero rows. **Trigram similarity**
solves this with *fuzzy* matching: it scores how alike two strings are by the
three-character fragments they share, so near-misses still match and can be
ranked by closeness.

The `pg_trgm` extension ships with PostgreSQL. All examples below were verified
on **PostgreSQL 18.6** with `pg_trgm` **1.6**. Source: `contrib/pg_trgm/`.

```sql
CREATE EXTENSION IF NOT EXISTS pg_trgm;
```

---

## 1. What a trigram is

`pg_trgm` breaks a string into overlapping groups of **three characters**. The
string is first lowercased, then **padded** — 2 leading spaces and 1 trailing
space (`LPADDING 2`, `RPADDING 1` in `contrib/pg_trgm/trgm.h`) — so the start and
end of the string, and word boundaries, produce their own trigrams.

```sql
SELECT show_trgm('Uniqlo'), show_trgm('Uniclo');
```
```
 show_trgm('Uniqlo') | {"  u"," un",iql,"lo ",niq,qlo,uni}
 show_trgm('Uniclo') | {"  u"," un",clo,icl,"lo ",nic,uni}
```

Note the padding artifacts: `"  u"` (two spaces + first char), `" un"`, and
`"lo "` (last chars + trailing space). The interior trigrams differ where the
spelling differs (`iql/niq/qlo` vs `icl/nic/clo`), while the shared prefix/suffix
trigrams (`"  u"`, `" un"`, `uni`, `"lo "`) stay the same — which is exactly why
a typo still scores as *similar*.

---

## 2. Similarity functions

`pg_trgm` measures similarity by counting shared trigrams.

```sql
SELECT similarity('Uniqlo','Uniclo')      AS sim,
       word_similarity('Uniqlo','Uniclo') AS word_sim;
```
```
 sim | 0.4
 word_sim | 0.42857143
```

- **`similarity(a, b)`** — `shared / union` of the two trigram sets, in `[0,1]`.
  `1` = identical, `0` = no shared trigrams. `Uniqlo`/`Uniclo` share 4 of 10
  distinct trigrams → `0.4`.
- **`word_similarity(a, b)`** — the best similarity between `a` and any
  *substring* (aligned to word boundaries) of `b`. Use it when the first string
  is a short search term that should match *part* of a longer value (e.g. a word
  inside a product title).
- **`strict_word_similarity(a, b)`** — like `word_similarity` but the extent must
  align to whole word boundaries, so it is stricter / less greedy.

> How the score is computed: both strings are decomposed, the trigram sets are
> intersected, and `similarity = |intersection| / |union|` (Jaccard-like). This
> is implemented in `contrib/pg_trgm/trgm_op.c`.

---

## 3. Operators (and their matching thresholds)

| Operator | Meaning | True when |
|----------|---------|-----------|
| `a % b` | similar | `similarity(a,b) >= pg_trgm.similarity_threshold` (default **0.3**) |
| `a <% b` | word-similar | `word_similarity(a,b) >= pg_trgm.word_similarity_threshold` (default **0.6**) |
| `a <<% b` | strict word-similar | uses `strict_word_similarity_threshold` (default **0.5**) |
| `a <-> b` | distance | `1 - similarity(a,b)` — for ordering (smaller = closer) |
| `a <<-> b` | word distance | `1 - word_similarity(a,b)` |

```sql
SELECT 'Uniqlo' %   'Uniclo' AS pct_similar,   -- t  (0.4 >= 0.3)
       'Uniqlo' <-> 'Uniclo' AS distance,      -- 0.6 (= 1 - 0.4)
       'shirt'  %   'shrt'   AS typo_match;     -- t
```
```
 pct_similar | distance | typo_match
 t           |      0.6 | t
```

The `%` operator is the workhorse for "did the user roughly mean this?", and
`<->` is what you `ORDER BY` to rank candidates by closeness. Tune
`pg_trgm.similarity_threshold` (session-settable) to make matching looser or
stricter.

### How the match decision actually works

There is no spell-checker and no notion of "intent." A trigram operator returns
`true` **iff the computed score meets a threshold** — that single comparison is
the *entire* match logic:

```
a % b   is true  ⇔  similarity(a, b) >= pg_trgm.similarity_threshold
```

So a misspelling matches for exactly one reason: a typo changes only a few
characters, most trigrams survive, and the score stays above the threshold. The
engine cannot tell an accidental typo from a deliberately partial/variant spelling
— both are just "score ≥ threshold." That is the strength (free typo tolerance)
and the limitation (unrelated-but-trigram-close strings can also match; you
control that only via the threshold).

Verified — the threshold is the only gate. `similarity('Uniqlo Down Jacket',
'Uniclo')` is `0.18`, so `%` is **false** at the default 0.3 and still false if
you raise it; a completely different string scores `0`:

```sql
SELECT similarity('Uniqlo Down Jacket','Uniclo')  AS sim,     -- 0.18
       'Uniqlo Down Jacket' % 'Uniclo'            AS matches; -- f (0.18 < 0.3)
SELECT 'Adidas Running Shoe' % 'Uniclo'           AS matches; -- f (similarity 0)
```

### `similarity` vs `word_similarity` — which to use for longer fields

The `0.18` above exposes a crucial point: **plain `similarity`/`%` compares the
*whole* strings**, so extra words dilute the score. Matching a short term against
a longer value (a brand inside a product title, a word inside an address) needs
`word_similarity` / the `<%` operator, which finds the best-matching *substring*:

```sql
SELECT similarity('Uniqlo Down Jacket','Uniclo')       AS plain_sim,  -- 0.18  (whole string)
       word_similarity('Uniclo','Uniqlo Down Jacket')  AS word_sim,   -- 0.43  (best substring)
       'Uniclo' <% 'Uniqlo Down Jacket'                AS word_match; -- see threshold note below
-- vs matching the brand column directly:
SELECT 'Uniqlo' % 'Uniclo'                              AS brand_match; -- t (similarity 0.4)
```

Rules of thumb:

- **`%` / `similarity`** — the two strings are *comparable wholes* (a brand column
  vs a brand query, deduping two name fields). Default threshold 0.3.
- **`<%` / `word_similarity`** — a short search term should match *part* of a
  longer field. Note its default threshold is **0.6** (higher than `%`'s 0.3), so
  `'Uniclo' <% 'Uniqlo Down Jacket'` at `word_sim = 0.43` is below 0.6 and does
  **not** match until you lower `pg_trgm.word_similarity_threshold`.
- **`<<%` / `strict_word_similarity`** — same idea but extents must align to whole
  word boundaries; stricter. Default threshold 0.5.

Practical takeaway: for fuzzy matching against a column that holds *just* the
value (brand, city, SKU), use `%`. For matching a term inside free-text/longer
fields, use `<%` and tune `word_similarity_threshold` — don't expect plain `%` on
a concatenated field to catch the typo.

### Are the thresholds adjustable? Yes — three scopes

The thresholds are GUC parameters with `context = user` (verified via
`pg_settings`), so they can be set at increasing scope. They are **query-time
only** — changing a threshold does *not* require rebuilding any index, because the
index returns trigram-overlap candidates and the threshold is applied as a
recheck.

```sql
-- 1. Per session / transaction (most common):
SET pg_trgm.similarity_threshold = 0.4;             -- stricter than default 0.3
SET LOCAL pg_trgm.word_similarity_threshold = 0.5;  -- this transaction only

-- 2. Persistent per role or per database:
ALTER ROLE app_user    SET pg_trgm.similarity_threshold = 0.4;
ALTER DATABASE catalog SET pg_trgm.similarity_threshold = 0.35;

-- 3. Cluster-wide: set pg_trgm.similarity_threshold in postgresql.conf, then reload.

-- Legacy equivalents (still supported) map to similarity_threshold:
SELECT set_limit(0.4);   -- same as SET pg_trgm.similarity_threshold = 0.4
SELECT show_limit();     -- current value
```

The three thresholds and their defaults:

| GUC | Default | Governs |
|-----|---------|---------|
| `pg_trgm.similarity_threshold` | 0.3 | `%` and `similarity()` |
| `pg_trgm.word_similarity_threshold` | 0.6 | `<%` and `word_similarity()` |
| `pg_trgm.strict_word_similarity_threshold` | 0.5 | `<<%` and `strict_word_similarity()` |

> Note: these are *custom* GUCs registered by the extension lazily — the first
> call to any `pg_trgm` function in a session registers them. `SHOW
> pg_trgm.similarity_threshold` before any trigram call in a fresh session errors
> with "unrecognized configuration parameter"; `SET` works regardless.
>
> Tuning guidance: **raise** the threshold for fewer, higher-confidence matches
> (fewer false positives, but more real typos missed); **lower** it to catch more
> misspellings at the cost of noise. There is no universally correct value — tune
> against your data and measure precision/recall.

---

## 4. Indexing trigram search — GIN vs GiST

Both the similarity operators (`%`, `<%`) **and** `LIKE`/`ILIKE`/regex can be
accelerated by a trigram index. You choose the opclass:

```sql
CREATE INDEX idx_brand_trgm ON brand USING gin  (name gin_trgm_ops);   -- fuzzy + LIKE
-- or
CREATE INDEX idx_brand_gist ON brand USING gist (name gist_trgm_ops);  -- fuzzy + LIKE + KNN
```

### 4a. Fuzzy match with a GIN trigram index

```sql
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF)
SELECT id, name, similarity(name,'Uniclo') AS sim
FROM brand
WHERE name % 'Uniclo'
ORDER BY sim DESC LIMIT 5;
```
```
 Limit
   ->  Sort  (Sort Key: similarity(name,'Uniclo') DESC)
         ->  Bitmap Heap Scan on brand
               Recheck Cond: (name % 'Uniclo')
               Rows Removed by Index Recheck: 6238
               ->  Bitmap Index Scan on idx_brand_trgm
                     Index Cond: (name % 'Uniclo')
```

The GIN index finds candidate rows that share enough trigrams (`%`), then
`similarity()` ranks them. Note `Rows Removed by Index Recheck` — the trigram
index is **lossy**: it narrows aggressively but the exact similarity is rechecked
on the heap.

### 4b. `LIKE`/`ILIKE` acceleration

A trigram index can also serve substring searches that would otherwise force a
sequential scan:

```sql
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF)
SELECT count(*) FROM brand WHERE name ILIKE '%atagoni%';
```
```
 Aggregate
   ->  Bitmap Heap Scan on brand
         Recheck Cond: (name ~~* '%atagoni%')
         ->  Bitmap Index Scan on idx_brand_gin
               Index Cond: (name ~~* '%atagoni%')
```

`%atagoni%` can't use a B-tree (leading wildcard), but the trigram index indexes
the fragments `ata`, `tag`, `ago`, `gon`, `oni`, so it finds matches directly.
This is a common reason to add a `gin_trgm_ops` index even if you never use the
`%` similarity operator.

### 4c. KNN "nearest matches" — GiST only

Only the **GiST** opclass supports the `<->` distance operator as an index
*ordering* (K-nearest-neighbor), letting you get the closest matches without a
full sort:

```sql
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF)
SELECT name, name <-> 'Patagona' AS dist
FROM brand ORDER BY name <-> 'Patagona' LIMIT 3;
```
```
 Limit
   ->  Index Scan using idx_brand_gist on brand
         Order By: (name <-> 'Patagona')
```

The `Index Scan ... Order By` returns rows already sorted by trigram distance —
ideal for "top-N closest" autocomplete/did-you-mean, and something a GIN index
cannot do.

### Choosing

| | **GIN** (`gin_trgm_ops`) | **GiST** (`gist_trgm_ops`) |
|---|---|---|
| `%`, `<%`, `LIKE`, `ILIKE`, regex | yes | yes |
| KNN `ORDER BY ... <->` | **no** | **yes** |
| Lookup speed | faster | slower |
| Build / update | slower to update | faster to update |
| Size | larger | smaller |

**Default to GIN** for fuzzy + `LIKE` lookups. Choose **GiST** when you need
`<->` KNN ordering (did-you-mean / top-N closest) or have write-heavy data.

---

## 5. `pg_trgm` vs full-text search — when to use which

| | Full-text search (`tsvector`/`@@`) | Trigram (`pg_trgm`) |
|---|---|---|
| Matches | whole words / lexemes (stemmed) | character fragments |
| Handles typos | no (needs correct spelling) | **yes** (fuzzy) |
| Language-aware | yes (stemming, stop words) | no |
| Phrase / boolean queries | yes (`& | ! <->`) | no |
| Ranking | relevance (`ts_rank`) | similarity (`similarity`, `<->`) |
| Best for | searching document *contents* | names, SKUs, short fields; typo-tolerant autocomplete |

They are complementary. A common pattern: use FTS for the main document search,
and fall back to a trigram similarity search when FTS returns nothing — that
"did you mean…?" path catches the misspellings FTS can't. See
[full-text-search.md](full-text-search.md) for the FTS side.

---

## Summary

1. `pg_trgm` decomposes lowercased, space-padded strings into overlapping
   3-character trigrams (`LPADDING 2`, `RPADDING 1`).
2. `similarity(a,b)` = shared / union of trigram sets, in `[0,1]`;
   `word_similarity` matches a short term against the best substring of a longer
   one.
3. Operators: `%` (similar, threshold 0.3), `<%` (word-similar, 0.6), `<->`
   (distance = 1 − similarity, for ordering).
4. Index with `gin_trgm_ops` (fuzzy + `LIKE`/`ILIKE`/regex, faster lookups) or
   `gist_trgm_ops` (adds KNN `ORDER BY ... <->`).
5. Trigram search is spelling-tolerant where FTS and `LIKE` are not — use it for
   fuzzy matching, typo-tolerant autocomplete, and leading-wildcard `LIKE`.
