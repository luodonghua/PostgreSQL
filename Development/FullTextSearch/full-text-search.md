# Full-Text Search in PostgreSQL

PostgreSQL has built-in full-text search: it turns documents into a normalized,
searchable form (`tsvector`), turns search phrases into a boolean query
(`tsquery`), and matches them with the `@@` operator. Unlike `LIKE '%word%'`,
full-text search is **language-aware** (stemming, stop words), **ranked**, and
**indexable**.

All examples below were run and verified on **PostgreSQL 18.6**. Source
references point at the PostgreSQL source tree (`src/backend/utils/adt/`,
`src/include/tsearch/`).

---

## 1. The two data types

| Type | Represents | Produced by |
|------|------------|-------------|
| `tsvector` | a **document** — a sorted set of lexemes with positions/weights | `to_tsvector(config, text)` |
| `tsquery` | a **query** — lexemes combined with boolean/phrase operators | `to_tsquery`, `plainto_tsquery`, `phraseto_tsquery`, `websearch_to_tsquery` |

They meet in one operator:

```sql
tsvector @@ tsquery   -- returns boolean: does the document match the query?
```

**Does operand order matter?** No. `@@` is defined as a **commutator pair** in
`pg_operator`, so `tsquery @@ tsvector` returns the same result and the planner
freely swaps the operands — you never lose index usage by writing it the other
way:

```
 oprname | left_type | right_type | commutator
---------+-----------+------------+------------
 @@      | tsvector  | tsquery    | @@          -- each points at the other
 @@      | tsquery   | tsvector   | @@
```

**Convention: put the `tsvector` first** (`tsvector @@ tsquery`). It reads as
"does this *document* match this *query*?", and since the indexed column is the
`tsvector`, leading with it makes the indexable predicate obvious. (There are
also `text @@ tsquery` and `text @@ text` overloads that implicitly call
`to_tsvector`/`plainto_tsquery` using `default_text_search_config` — handy in
ad-hoc queries, but not immutable, so don't use them in index definitions.)

---

## 2. `to_tsvector`: how a document is normalized

```sql
SELECT to_tsvector('english', 'The quick brown foxes are jumping over the lazy dogs');
```
```
 'brown':3 'dog':10 'fox':4 'jump':6 'lazi':9 'quick':2
```

Several things happened in that one call:

1. **Tokenization** — the parser split the text into tokens and classified each
   (word, number, email, URL, …).
2. **Dictionary processing** — each token is passed through the dictionaries
   mapped to its token type for the chosen configuration (`english`):
   - *Stemming*: `foxes → fox`, `jumping → jump`, `dogs → dog`, `lazy → lazi`.
     The lexeme is the **stem**, not the original word, so `jumping` and `jumps`
     both match a search for `jump`.
   - *Stop words removed*: `the`, `are`, `over` are gone. The `english_stem`
     dictionary knows a stop-word list and emits nothing for them — note the
     positions jump from `fox:4` to `jump:6` (position 5 = `are`, dropped).
3. **Positions recorded** — the number after each lexeme (`quick:2`) is its word
   position in the original text. Positions drive **phrase search** and
   **ranking**.

### Which dictionary handles which token?

A text search configuration maps each token *type* to an ordered list of
dictionaries. `ts_debug` shows the mapping:

```sql
SELECT alias, dictionaries
FROM ts_debug('english', 'The running foxes 3.14 user@example.com');
```
```
   alias   |  dictionaries
-----------+----------------
 asciiword | {english_stem}     -- "The", "running", "foxes" → stemmed
 float     | {simple}           -- 3.14 kept as-is
 email     | {simple}           -- user@example.com kept as-is
```

So word tokens go to `english_stem` (Snowball stemmer + stop words), while
numbers/emails/URLs go to the `simple` dictionary (lowercase, no stemming, no
stop words). You can add **custom dictionaries** — synonym dictionaries,
thesaurus dictionaries, `unaccent`, specialized `dict_int`/`dict_xsyn` — and
insert them ahead of the stemmer so domain terms and abbreviations map to the
same lexeme. Processing stops at the first dictionary that returns a result (or
returns "this is a stop word").

> Internals: a `tsvector` is stored as a varlena with a sorted `WordEntry[]`
> array followed by the lexeme strings; entries are sorted by lexeme so matching
> is a binary search. Each lexeme optionally carries a position list, and each
> position packs a 2-bit weight + 14-bit position
> (`src/include/tsearch/ts_type.h`, `WordEntryPos`, `WEP_GETWEIGHT`/`WEP_GETPOS`).

---

## 3. Weights: A / B / C / D

A lexeme position can be tagged with a weight `A`, `B`, `C`, or `D` (D is the
default). Weights let you say "a hit in the title counts more than a hit in the
body" without storing separate vectors.

```sql
SELECT setweight(to_tsvector('english','PostgreSQL full text search'), 'A');
```
```
 'full':2A 'postgresql':1A 'search':4A 'text':3A
```

The idiomatic pattern is to weight each field, then concatenate with `||`:

```sql
setweight(to_tsvector('english', title),   'A') ||
setweight(to_tsvector('english', summary), 'B') ||
setweight(to_tsvector('english', body),    'C')
```

A single lexeme appearing in several fields keeps **all** its weighted
positions, e.g. `'account':10B,24C` means "account" occurs at position 10 (a
summary word, weight B) and position 24 (a body word, weight C).

> Internals: weight is a 2-bit field — `A = 1<<3, B = 1<<2, C = 1<<1, D = 1<<0`
> as a bitmask in `tsquery` operands (`src/include/tsearch/ts_type.h`). Ranking
> functions map A/B/C/D to the four numbers in the optional `weights` array.

### How much more? Weight factors and hit saturation

"A hit in the title counts more than a hit in the body" — but *how much* more,
and does one A hit beat 100 B hits? The weights are **fixed multipliers, not a
priority tier**. The default array is `{D,C,B,A} = {0.1, 0.2, 0.4, 1.0}`
(`src/backend/utils/adt/tsrank.c`, `default_weights`):

| Weight | Factor | Ratio to D |
|--------|--------|------------|
| A | 1.0 | 10× |
| B | 0.4 | 4× |
| C | 0.2 | 2× |
| D (default) | 0.1 | 1× |

So per occurrence, an **A hit is worth 2.5× a B hit** (1.0 / 0.4) — a tilt, not
a veto. There is no rule that "A outranks any number of Bs"; `ts_rank` computes
a weighted combination.

The second, less obvious factor: **repeated hits of the same lexeme saturate**.
`ts_rank` does *not* compute `count × weight`. Each extra occurrence adds less
(the combine step is `1 - (1-res)*(1-curw)`, and `word_distance()` hard-caps at
`w > 100`), so the score asymptotes. Measured on PostgreSQL 18.6 (single lexeme,
default normalization):

```sql
SELECT ts_rank(setweight(to_tsvector('simple','term'),'A'), to_tsquery('simple','term'));                 -- 1× A
SELECT ts_rank(setweight(to_tsvector('simple', repeat('term ',N)),'B'), to_tsquery('simple','term'));     -- N× B
```

| Document | ts_rank |
|----------|---------|
| 1× A | **0.6079** |
| 1× B | 0.2432 |
| 3× B | 0.3310 |
| 10× B | 0.3769 |
| 100× B | **0.3976** |

Reading this:

- **With default weights, 1 A hit (0.608) does beat even 100 B hits (0.398)** —
  because B saturates near ~0.40 while A starts at ~0.61. That is a consequence
  of the specific numbers, **not** a built-in "A wins" rule.
- `1× B = 0.2432 ≈ 0.4 × (1× A)` confirms the 0.4 factor directly.
- Going from 10 to 100 B hits moves the rank only 0.377 → 0.398: spamming a term
  barely helps. Beyond ~100 occurrences, extra hits contribute essentially
  nothing.

Change the weights and the outcome flips. With a lowered A
(`ts_rank('{0.1,0.2,0.3,0.45}', …)`), a single A hit no longer wins:

| Document (custom weights `{0.1,0.2,0.3,0.45}`) | ts_rank |
|-----------------------------------------------|---------|
| 1× A (factor 0.45) | 0.2736 |
| 100× B (factor 0.30) | **0.2982** |

So "how much more" is entirely set by the weight array versus the saturation
ceiling. Pass a custom `weights` array as the first argument to `ts_rank` /
`ts_rank_cd` to retune (values are clamped to ≤ 1.0). Note `ts_rank_cd` uses the
**inverse** weights (`1.0/w`) plus proximity, so its absolute numbers differ, but
the "A > B > C > D with diminishing returns per hit" principle is the same.

---

## 4. `tsquery`: the four ways to build one

`tsquery` has exactly four operators (`src/include/tsearch/ts_type.h`):
`OP_NOT (!)`, `OP_AND (&)`, `OP_OR (|)`, `OP_PHRASE (<->/<N>)`.

```sql
SELECT to_tsquery('english', 'jumping & dogs');
--  'jump' & 'dog'                      -- &, |, !, <-> ; you control operators, input must be lexable

SELECT plainto_tsquery('english', 'jumping dogs');
--  'jump' & 'dog'                      -- plain words → AND of all terms

SELECT phraseto_tsquery('english', 'quick brown fox');
--  'quick' <-> 'brown' <-> 'fox'       -- adjacency: words must be consecutive

SELECT websearch_to_tsquery('english', '"quick brown" -lazy');
--  'quick' <-> 'brown' & !'lazi'       -- web syntax: quotes = phrase, - = NOT, or
```

Pick by input source:

- **`to_tsquery`** — you build the operator expression yourself. Most powerful,
  but input must already be valid (never feed raw user text to it).
- **`plainto_tsquery`** — safe for raw user text; ANDs the terms.
- **`phraseto_tsquery`** — safe for raw user text; requires the terms in order.
- **`websearch_to_tsquery`** — safe for raw user text; supports a Google-like
  mini-syntax (`"…"`, `-term`, `or`). Best default for a search box.

### Operators in detail

- `&` (AND), `|` (OR), `!` (NOT) — boolean combination.
- `<->` (FOLLOWED BY) — lexemes must be adjacent. `<N>` means "exactly N
  positions apart"; `a <2> b` = b is two positions after a.
- **Prefix match** with `:*`:

```sql
SELECT to_tsvector('english','jumping jumper') @@ to_tsquery('english','jump:*') AS prefix_match;
--  t     -- jump:* matches any lexeme starting with "jump"
```

Weights can also be restricted on the query side: `account:A` only matches
"account" positions tagged weight A.

### Matching

```sql
SELECT to_tsvector('english','the quick brown fox') @@ to_tsquery('english','quick & fox');
--  t
```

Matching is implemented by `TS_execute` over the `tsquery` tree against the
sorted `tsvector` (`src/backend/utils/adt/tsvector_op.c`); phrase operators
additionally compare position lists.

---

## 5. Indexing — three strategies

A `tsvector` match can be indexed. The question is *where the tsvector comes
from*. There are three common designs.

### 5a. Expression index (no extra column)

Index the `to_tsvector(...)` **expression** directly:

```sql
CREATE TABLE note (id int primary key, body text);
CREATE INDEX idx_note_fts ON note USING gin (to_tsvector('english', body));
```

The query must use the **same expression** for the planner to use the index:

```sql
EXPLAIN (COSTS OFF)
SELECT id FROM note
WHERE to_tsvector('english', body) @@ to_tsquery('english','hello');
```
```
 Bitmap Heap Scan on note
   Recheck Cond: (to_tsvector('english'::regconfig, body) @@ '''hello'''::tsquery)
   ->  Bitmap Index Scan on idx_note_fts
```

Pros: no schema change, no extra storage for a column (the index still stores
the vector). Cons: every query must repeat the exact expression; the vector is
recomputed on each insert/update anyway, and you can't `SELECT` the vector
cheaply or add weights from multiple columns as easily.

### 5b. Stored generated column (recommended for multi-field search)

Materialize the vector in a `GENERATED ALWAYS AS (...) STORED` column so it is
always in sync and can be indexed and selected directly. Example table (a small
knowledge-base article, combining three weighted fields):

```sql
CREATE TABLE kb_article (
    id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    title      text NOT NULL,
    summary    text,
    body       text,
    search_tsv tsvector GENERATED ALWAYS AS (
        setweight(to_tsvector('english', coalesce(title,'')),   'A') ||
        setweight(to_tsvector('english', coalesce(summary,'')), 'B') ||
        setweight(to_tsvector('english', coalesce(body,'')),    'C')
    ) STORED
);

CREATE INDEX idx_kb_search ON kb_article USING gin (search_tsv);
```

The stored vector for one row:

```
id | title                                 | search_tsv
 2 | Configuring two-factor authentication | '2fa':7B 'account':10B,24C 'app':17C 'authent':5A,16C
                                             'configur':1A 'secur':11B,21C 'two-factor':2A ...
```

And the index is used (seqscan disabled to force the point; the planner picks it
on its own once the table is large enough):

```
 Bitmap Heap Scan on kb_article
   Recheck Cond: (search_tsv @@ '''account'' & ''secur'''::tsquery)
   ->  Bitmap Index Scan on idx_kb_search
```

**Why `coalesce` and not `format`?** A generated column's expression must be
`IMMUTABLE`. `to_tsvector(regconfig, text)` is immutable, and `coalesce` +
`||` are immutable, but `format()` is only `STABLE` (its behavior can depend on
type-output functions). Trying it fails:

```sql
CREATE TABLE bad (t text,
  v tsvector GENERATED ALWAYS AS (to_tsvector('english', format('%s', t))) STORED);
-- ERROR:  generation expression is not immutable
```

That is why the concatenation idiom uses `coalesce(col,'') || ' ' || …` instead
of `format(...)`.

> Note: passing the config as a **literal** (`'english'`) resolves to a specific
> `regconfig` OID and is immutable. Using the *default* config
> (`to_tsvector(body)` with no config argument) depends on the
> `default_text_search_config` GUC and is **not** immutable — so it can't be used
> in a generated column or expression index. Always name the configuration.

### 5c. Trigger-maintained column (legacy / pre-12)

Before generated columns (PostgreSQL 12+), the same effect was achieved with a
`BEFORE INSERT OR UPDATE` trigger (often `tsvector_update_trigger`). Generated
columns are now preferred — declarative, can't be bypassed, and need no trigger
code. Reach for a trigger only if you need logic a generated column can't
express (e.g. pulling text from another table).

---

## 6. GIN vs GiST for the index

Both index types support `tsvector @@ tsquery`. The choice is a
read-vs-write / exact-vs-lossy trade-off.

| | **GIN** | **GiST** |
|---|---------|----------|
| Structure | Inverted index: `lexeme → posting list of row TIDs` | Signature tree: each row's lexemes hashed into a fixed-length **bit signature** |
| Lookups | Fast and **exact** — look up the lexeme, get its row list | Slower; signatures are **lossy** (hash collisions) so every candidate needs a **recheck** against the heap |
| Updates | Slower to update (must maintain posting lists); softened by the `fastupdate` **pending list** | Faster to update |
| Size | Larger, but compresses posting lists (varbyte) | Smaller, fixed-size signatures |
| Best for | Mostly-read data, large document sets (the usual FTS case) | Write-heavy / fast-changing data where write latency matters more than read |

**Rule of thumb:** use **GIN** for full-text search unless writes dominate.
GIN is the inverted index that maps each lexeme to the documents containing it,
which is exactly what a search workload wants. See
[Indexes/gin.md](../Indexes/gin.md) and [Indexes/gist.md](../Indexes/gist.md)
for the internals of each.

> GIN's `fastupdate` buffers new entries in an unsorted *pending list* and folds
> them into the main index in bulk (at vacuum or when the list exceeds
> `gin_pending_list_limit`), which hides most of the per-row update cost that
> makes GIN "slow to update."

---

## 7. Ranking results

A boolean match tells you *whether* a row matches, not *how well*. `ts_rank`
(frequency-based) and `ts_rank_cd` (cover-density, uses proximity) score the
match; combine with `ORDER BY ... DESC LIMIT n`.

```sql
SELECT id, title,
       round(ts_rank(search_tsv, websearch_to_tsquery('english','account'))::numeric, 4) AS rank
FROM kb_article
WHERE search_tsv @@ websearch_to_tsquery('english','account')
ORDER BY rank DESC;
```
```
 id | title                                 |  rank
  2 | Configuring two-factor authentication | 0.2736
  1 | Resetting your password               | 0.2432
```

Row 2 ranks higher because "account" appears there twice (and in a
higher-weighted field). `ts_rank` takes an optional `weights` array
`'{D,C,B,A}'` so you can tune how much A/B/C/D positions contribute.

For display, `ts_headline` returns the matching snippet with the hits marked:

```sql
SELECT ts_headline('english', body, websearch_to_tsquery('english','password'))
FROM kb_article WHERE id = 1;
```

> Ranking runs **after** the index narrows candidates — the GIN/GiST index finds
> matching rows, then `ts_rank*` is computed on those rows only. Ranking itself
> is not indexed.

---

## 8. Putting it together — a search-box query

```sql
SELECT id, title,
       ts_rank_cd(search_tsv, q) AS rank,
       ts_headline('english', body, q) AS snippet
FROM kb_article,
     websearch_to_tsquery('english', $1) AS q   -- $1 = raw user input
WHERE search_tsv @@ q
ORDER BY rank DESC
LIMIT 20;
```

- `websearch_to_tsquery` safely parses untrusted user input.
- `search_tsv @@ q` is answered by the GIN index.
- `ts_rank_cd` orders by relevance; `ts_headline` builds the preview.

---

## 9. Combining FTS with conventional SQL predicates — which index wins?

The real strength of FTS shows when you mix it with ordinary SQL conditions,
e.g. a text match **and** `price < 50`. A natural question: does PostgreSQL use
the GIN (full-text) index *and* the B-tree (price) index together — intersecting
them with a **BitmapAnd** — or just one?

**Answer: it can do either. It is a cost-based decision, not automatic.** The
enabling mechanism is the **bitmap scan**: both GIN and B-tree can emit a bitmap
of matching tuples, and the executor can `BitmapAnd` two bitmaps before touching
the heap. (GIN *only* produces bitmaps — it has no plain ordered index-scan
mode.) But two indexes are only combined when both columns live on the **same
table and same scan**.

All three plans below are real `EXPLAIN (ANALYZE)` output on PostgreSQL 18.6.
Full runnable script: [combine-fts-with-scalar.sql](combine-fts-with-scalar.sql).

### Setup (abridged — see the SQL file for the full script)

```sql
CREATE TABLE product (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    label        text NOT NULL,
    description  text,
    price        numeric(10,2),
    infotext_tsv tsvector GENERATED ALWAYS AS (
        setweight(to_tsvector('english', coalesce(label,'')),      'A') ||
        setweight(to_tsvector('english', coalesce(description,'')),'B')
    ) STORED
);
-- 200,000 rows inserted (see script), then:
CREATE INDEX idx_prod_fts   ON product USING gin  (infotext_tsv);
CREATE INDEX idx_prod_price ON product USING btree(price);
ANALYZE product;
```

### Case 1 — FTS predicate much more selective → single GIN index, price as Filter

```sql
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF)
SELECT id, label FROM product
WHERE infotext_tsv @@ websearch_to_tsquery('english','edgy and cool shirt or t-shirt')
  AND price < 50;
```
```
 Bitmap Heap Scan on product (actual rows=1000.00 loops=1)
   Recheck Cond: (infotext_tsv @@ '''edgi'' & ''cool'' & ''shirt'' | ''t-shirt'' <2> ''shirt''')
   Filter: (price < '50'::numeric)          <- applied AFTER the heap fetch
   Rows Removed by Filter: 3000
   Heap Blocks: exact=4000
   ->  Bitmap Index Scan on idx_prod_fts (actual rows=4000.00 loops=1)
         Index Cond: (infotext_tsv @@ '''edgi'' & ''cool'' & ''shirt'' | ''t-shirt'' <2> ''shirt''')
```

The FTS match returned 4000 of 200,000 rows. Scanning the price B-tree too
(which matches ~25% of the table) and intersecting would cost **more** than just
filtering 4000 already-fetched rows in memory. So only the GIN index is used and
`price < 50` is a cheap recheck `Filter`. **This is the most likely plan for the
book's query**, because a good FTS predicate is usually far more selective than
`price < 50`.

### Case 2 — both predicates selective on the same table → BitmapAnd

```sql
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF)
SELECT id, label FROM product
WHERE infotext_tsv @@ websearch_to_tsquery('english','shirt')
  AND price < 3;
```
```
 Bitmap Heap Scan on product (actual rows=1000.00 loops=1)
   Recheck Cond: ((price < '3'::numeric) AND (infotext_tsv @@ '''shirt'''))
   ->  BitmapAnd (actual rows=0.00 loops=1)
         ->  Bitmap Index Scan on idx_prod_price (actual rows=3000.00 loops=1)   -- B-tree
               Index Cond: (price < '3'::numeric)
         ->  Bitmap Index Scan on idx_prod_fts (actual rows=9333.00 loops=1)     -- GIN
               Index Cond: (infotext_tsv @@ '''shirt''')
```

Now each predicate is individually non-trivial but jointly very selective. The
planner builds a bitmap from **each** index and `BitmapAnd`s them, fetching only
the intersection from the heap. This is the "best of both worlds" — the GIN FTS
index and the B-tree price index used **together in one scan**.

### Case 3 — predicates on different tables (the book's actual shape) → join, no BitmapAnd

`BitmapAnd` only combines indexes on the **same** table. The book query has the
text match on `product` and the price on `product_variant_price`, so they cannot
be bitmap-ANDed; each table is scanned on its own and the results are joined.

```sql
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF)
SELECT p.id, p.label,
       FORMAT('%s-%s', MIN(pvp.price), MAX(pvp.price)) AS price_range
FROM product p
JOIN product_variant pv        ON p.id  = pv.product_id
JOIN product_variant_price pvp ON pv.id = pvp.product_variant_id
WHERE p.infotext_tsv @@ websearch_to_tsquery('english','edgy and cool shirt or t-shirt')
  AND pvp.price < 50
GROUP BY p.id, p.label
ORDER BY MAX(pvp.price) DESC;
```
```
 Sort  (Sort Key: max(pvp.price) DESC)
   ->  GroupAggregate
         ->  Nested Loop
               ->  Nested Loop
                     ->  Bitmap Heap Scan on product p
                           Recheck Cond: (infotext_tsv @@ '...')
                           ->  Bitmap Index Scan on idx_prod_fts        -- GIN drives the FTS table
                     ->  Index Scan using idx_pv_product on product_variant pv
                           Index Cond: (product_id = p.id)
               ->  Index Scan using idx_pvp_variant on product_variant_price pvp
                     Index Cond: (product_variant_id = pv.id)
                     Filter: (price < '50'::numeric)                    -- price filtered per-row here
```

The GIN index scans `product`; the price condition is applied inside the index
scan on `product_variant_price` after the join. There is **no** BitmapAnd of the
FTS and price indexes, because they are on different tables.

### How the planner decides

For same-table predicates it estimates, per candidate plan:
- selectivity of the FTS predicate (from `tsvector` stats) vs. the scalar predicate,
- cost of a second bitmap index scan + the `BitmapAnd`, versus
- cost of fetching the larger single-index bitmap and filtering the rest.

It picks the cheapest. Rules of thumb:

| Situation | Typical plan |
|-----------|--------------|
| One predicate far more selective than the other | single index + `Filter` (Case 1) |
| Both predicates independently selective, same table | `BitmapAnd` of both indexes (Case 2) |
| `OR` of conditions across indexes, same table | `BitmapOr` of both indexes |
| Predicates on different tables | separate scans + join (Case 3) |

To see what *your* query actually does, always check:

```sql
EXPLAIN (ANALYZE, BUFFERS) <your query>;
```

and look for `BitmapAnd`/`BitmapOr` (indexes combined), a `Filter:` line (one
index + post-filter), or join nodes (predicates on different tables).

---

## 10. Speeding up `tsvector` queries

The single biggest speedup is a **GIN index** on the `tsvector`; most other
tuning is secondary. Measured on PostgreSQL 18.6, 200,000 rows, a selective
query (`to_tsquery('english','rareword')` matching ~20 rows):

| | Plan | Time | Buffers |
|---|------|------|---------|
| No index | Parallel Seq Scan | 19.2 ms | 3742 |
| GIN index | Bitmap Index Scan | **0.054 ms** | **24** |

```sql
CREATE INDEX idx_doc_tsv ON doc USING gin (tsv);
```
```
 Aggregate
   ->  Bitmap Heap Scan on doc
         Recheck Cond: (tsv @@ '''rareword''')
         ->  Bitmap Index Scan on idx_doc_tsv   (actual rows=20)
 Execution Time: 0.054 ms
```

A ~350× improvement on the selective case. Beyond simply having the index, the
techniques that matter:

### 10a. Materialize the vector in a stored generated column

Don't recompute `to_tsvector(...)` on every query. A `GENERATED ALWAYS AS (...)
STORED` column computes it once at write time and lets you index it directly (see
§5). This avoids per-query CPU for parsing/stemming and keeps the query a pure
index lookup.

### 10b. Tune GIN's pending list (`fastupdate`)

GIN buffers new entries in an unsorted **pending list** and merges them in bulk,
which speeds up inserts but means reads must also scan the pending list until it
is flushed. The relevant knobs:

```sql
-- per-index:
CREATE INDEX idx_doc_tsv ON doc USING gin (tsv)
  WITH (fastupdate = on, gin_pending_list_limit = 4096);  -- limit in kB

-- cluster default (kB):
SHOW gin_pending_list_limit;   -- default 4MB
```

- Keep `fastupdate = on` (default) for write-heavy tables; the pending list
  absorbs insert cost.
- If **read** latency matters and the pending list grows large, lower
  `gin_pending_list_limit` (flush sooner) or `VACUUM` the table to flush it, so
  searches don't pay to scan unmerged entries.
- For bulk loads, a common pattern is to drop/disable the index, load, then
  rebuild.

### 10c. Limit candidate work on huge result sets

`gin_fuzzy_search_limit` (default `0` = unlimited) caps how many results a single
GIN scan returns, trading completeness for bounded latency on queries that would
otherwise match enormous numbers of rows. Leave it `0` unless you have such a
pathological query.

### 10d. Combine with scalar predicates efficiently

If you frequently filter FTS results by a scalar column (`WHERE tsv @@ q AND
category = 'news'`), the planner can `BitmapAnd` a GIN index with a B-tree (§9).
When the scalar is *always* present and selective, a **`btree_gin`** composite
index lets one index serve both:

```sql
CREATE EXTENSION IF NOT EXISTS btree_gin;
CREATE INDEX idx_doc_cat_tsv ON doc USING gin (category, tsv);
```

### 10e. Keep ranking off the hot path

`ts_rank`/`ts_rank_cd` are **not** indexed — they run on the rows the index
returns (§7). For large candidate sets, apply a selective `@@` first, then
`ORDER BY ts_rank(...) LIMIT n`, so ranking only touches the narrowed set. Avoid
ranking before filtering.

> Not covered here: third-party indexes such as RUM (which can store positions
> for faster ranking and phrase search) are an option for ranking-heavy
> workloads, but they are extensions outside the core distribution and are not
> installed in this environment.

---

## 11. Multi-language full-text search

A `tsvector` is only meaningful for **one** language, because stemming and
stop-word removal are language-specific (`to_tsvector('english','running')` →
`run`, but `to_tsvector('french','running')` leaves it unstemmed). So every
searchable text value must be paired with the configuration used to build it.
The design question for a product catalog in N languages is *where the language
lives*.

Runnable script: [multi-language-fts.sql](multi-language-fts.sql). All numbers
below were measured on PostgreSQL 18.6 with **100,000 products × 3 languages =
300,000 rows**.

### The three options

| Option | Shape | Adding a language |
|--------|-------|-------------------|
| **A** — table per language | `pt_en`, `pt_fr`, `pt_de`, … | **DDL** + new table + new code path |
| **B** — one wide row | `(…, body_en, body_fr, tsv_en, tsv_fr, …)` | **DDL** `ADD COLUMN`; sparse NULLs |
| **C** — row per (product, language) | one table, `lang`/`ts_config` column | just an `INSERT` |

**Recommended: Option C.** The language is *data*, not schema.

```sql
CREATE TABLE product_translation (
    product_id bigint    NOT NULL REFERENCES product(id),
    lang       text      NOT NULL,          -- 'en','fr','de'
    ts_config  regconfig NOT NULL,          -- 'english','french','german'
    label      text,
    body       text,
    search_tsv tsvector GENERATED ALWAYS AS (
        setweight(to_tsvector(ts_config, coalesce(label,'')),'A') ||
        setweight(to_tsvector(ts_config, coalesce(body ,'')),'B')
    ) STORED,
    PRIMARY KEY (product_id, lang)
);
CREATE INDEX idx_pt_fts ON product_translation USING gin (search_tsv);
```

The subtle enabler: **`to_tsvector(regconfig, text)` is `IMMUTABLE` even when the
config comes from a *column*** (`provolatile = 'i'`), so each row can be stemmed
with its own language inside a `STORED` generated column. Verified — one product
in three languages, each stemmed by its own config:

```
 lang |                      search_tsv
------+-------------------------------------------------------
 de   | 'laufschuh':1A,3B 'leicht':2B 'sportl':5B
 en   | 'athlet':7B 'lightweight':3B 'run':1A,4B 'shoe':2A,5B
 fr   | 'athlet':9B 'chaussur':1A,4B 'cours':3A,6B 'léger':7B
```

**Where is the language in that output? It isn't — `lang` is a separate
column.** The `tsvector` stores **only** `lexeme:position+weight` triples and
records *nothing* about which configuration produced it. Dissecting
`'cours':3A,6B`:

```
'cours'   :   3     A   ,   6     B
└lexeme┘      └pos┘ └wt┘    └pos┘ └wt┘
```

That is the entire content of a `tsvector` entry (`WordEntry` = lexeme + a list
of positions, each packing a 2-bit weight + 14-bit position,
`src/include/tsearch/ts_type.h`). There is **no language/config field** anywhere
in the structure. You can *tell* the rows apart only because each was stemmed by
a different config — `de` → `laufschuh/leicht/sportl`, `fr` →
`chaussur/cours/léger`, `en` → `run/shoe/athlet` — but once stemming is done the
vector is just a bag of lexemes. The stemmer already consumed the language and
discarded it.

The consequence is exactly why this design needs an explicit `lang`/`ts_config`
column: a `tsquery` carries no language either (`to_tsquery('french','coureurs')`
is just the lexeme `'coureur'`), and `@@` is a pure lexeme comparison with no
language check. If two languages produce the same stem (a model number, or
`athlet`, which appears in both the `fr` and `en` rows above), their vectors are
indistinguishable and will cross-match. Only your `WHERE lang = 'fr'` prevents
that — see the leakage demo below.

Query one language — filter by `lang`, build the `tsquery` with the matching
config:

```sql
SELECT product_id, ts_rank(search_tsv, q) AS rank
FROM product_translation, websearch_to_tsquery('french', $1) AS q
WHERE lang = 'fr' AND search_tsv @@ q
ORDER BY rank DESC;
```

### Large-scale: performance & storage (measured, 300k rows)

**Storage — Option C vs Option A are essentially the same, and C's single GIN
index is actually smaller than three separate ones:**

| | Option C (1 table) | Option A (3 tables) |
|---|---|---|
| Total size | 91 MB | 89 MB |
| GIN index | **9.3 MB** (one index) | **18 MB** (3 indexes summed) |
| Extra | 2 MB `lang` btree | — |

A single GIN over 300k rows packs lexemes more densely than three GINs of 100k
each (shared posting-list overhead amortizes better), so consolidating does
**not** cost you index space — it saves it here.

**Query latency — identical for a selective single-language search.** Both use a
GIN bitmap scan; the `lang` predicate in Option C is a cheap recheck filter:

```
-- Option C: WHERE lang='fr' AND search_tsv @@ to_tsquery('french','coureurs & 12345')
 Bitmap Heap Scan on pt_single (actual rows=1)
   Filter: (lang = 'fr')
   ->  Bitmap Index Scan on idx_pts_fts
 Execution Time: 0.258 ms

-- Option A: same query on the dedicated pt_fr table
 Bitmap Heap Scan on pt_fr (actual rows=1)
   ->  Bitmap Index Scan on idx_ptfr_fts
 Execution Time: 0.157 ms
```

Both sub-millisecond. The GIN index already narrows to a handful of rows before
the `lang` filter runs, so the single-table design has no meaningful penalty at
this scale.

### The real risk with Option C: forgetting the `lang` filter

Because `@@` is a pure lexeme comparison and **neither the `tsvector` nor the
`tsquery` carries a language**, omitting `lang = 'fr'` silently returns rows from
*other* languages whenever lexemes collide. This is a correctness bug, not just a
performance issue. Measured before/after on the canonical query:

```sql
-- CORRECT: French search for model 12345, with the lang filter
SELECT product_id, lang, ts_rank(search_tsv, q) AS rank
FROM product_translation, websearch_to_tsquery('french','12345') AS q
WHERE lang='fr' AND search_tsv @@ q
ORDER BY rank DESC;
--  product_id | lang | rank
--           1 | fr   | 0.0608      <- one row, correct
```

```sql
-- BUG: same query, lang filter FORGOTTEN
SELECT product_id, lang, ts_rank(search_tsv, q) AS rank
FROM product_translation, websearch_to_tsquery('french','12345') AS q
WHERE search_tsv @@ q
ORDER BY rank DESC;
--  product_id | lang | rank
--           1 | en   | 0.0608      <- WRONG: English row matched a French query
--           1 | fr   | 0.0608
--           1 | de   | 0.0608      <- WRONG: German row matched a French query
```

The `french` config only affected how `q` was *built*; the lexeme `'12345'`
exists in all three rows, so all three match. It is not limited to numbers — a
real word like `cool` that stems identically in English/French/German leaks the
same way.

**The danger is that it fails silently** — no error, plausible rows,
correct-looking ranks. You get duplicate products (same `product_id`, multiple
`lang`), inflated counts, and broken pagination. How often it bites scales with
cross-language lexeme overlap:

| Query term | Leaks across languages? |
|------------|-------------------------|
| Numbers, SKUs, model codes (`12345`) | **Always** — identical in every language |
| Brands / proper nouns (`Nike`, `iPhone`) | Almost always |
| Words with the same stem across languages (`cool`, `sport`, `hotel`) | Yes |
| Words that stem differently per language (`running`→`run`) | Usually not — which is why the bug often hides in dev and surfaces in prod |

Always filter by `lang` (or `ts_config`). To make this structural rather than a
discipline problem, **partition by language** — one logical table, but the
planner prunes to the relevant partition and each has its own smaller GIN:

```sql
CREATE TABLE product_translation (...) PARTITION BY LIST (lang);
CREATE TABLE pt_en PARTITION OF product_translation FOR VALUES IN ('en');
CREATE TABLE pt_fr PARTITION OF product_translation FOR VALUES IN ('fr');
CREATE TABLE pt_de PARTITION OF product_translation FOR VALUES IN ('de');
```

### What the ranked query's plan actually looks like

For the canonical query (note `q` written in the FROM clause):

```sql
SELECT product_id, ts_rank(search_tsv, q) AS rank
FROM product_translation, websearch_to_tsquery('french', $1) AS q
WHERE lang = 'fr' AND search_tsv @@ q
ORDER BY rank DESC;
```

the non-partitioned plan (selective term) is:

```
 Sort                                                  <- ORDER BY rank DESC
   Sort Key: ts_rank(search_tsv, '''coureur'' & ''12345''') DESC
   ->  Bitmap Heap Scan on pt_single
         Recheck Cond: (search_tsv @@ '''coureur'' & ''12345''')
         Filter: (lang = 'fr')                         <- lang applied after the index
         ->  Bitmap Index Scan on idx_pts_fts          <- GIN does the work
 Execution Time: 0.120 ms
```

Two structural notes: (1) the `q` subquery **disappears** — `websearch_to_tsquery`
is constant-folded to a literal `tsquery` and inlined, so putting `q` in the FROM
clause adds no join; (2) `ts_rank` runs **after** the scan, feeding the `Sort` —
ranking is never indexed.

The partitioned plan is identical except it scans only the `fr` partition:

```
 Sort
   ->  Bitmap Heap Scan on pt_part_fr pt_part          <- pruned to fr partition
         ->  Bitmap Index Scan on pt_part_fr_search_tsv_idx
 Execution Time: 0.076 ms
```

### Where partitioning does NOT help: broad (non-selective) terms

Pruning sounds like a clear win, but measure before assuming. For a **common**
term that matches every row in a language, partitioning can actually switch the
plan to a sequential scan and lands at the *same* latency:

| Query | Non-partitioned | Partitioned |
|-------|-----------------|-------------|
| Selective (`coureurs & 12345`, 1 row) | 0.120 ms (GIN bitmap) | 0.076 ms (GIN bitmap, pruned) |
| Broad (`coureurs`, 100k rows) | 25.3 ms (**parallel GIN bitmap scan**) | 23.9 ms (**parallel seq scan** of fr partition) |

In the broad case the partitioned planner saw that the term matched *all* rows in
the one partition it was left with, decided the GIN index wasn't worth it, and
did a plain `Parallel Seq Scan` — essentially the same cost as the non-partitioned
GIN scan. **Partitioning did not improve query latency here.**

### Recommendation for a large-scale, 3-language deployment

- **Use Option C (row per product+language) with a `regconfig` column as the
  default.** New languages are inserts; one code path; storage and latency are
  as good as or better than table-per-language, and its single GIN is *smaller*
  than three separate ones (9.3 MB vs 18 MB measured).
- **Partition by `lang` for operations and safety, not for this query's
  latency.** The measurements show pruning gives only a marginal win on
  selective searches and *no* win on broad ones. Partition when you want:
  - independent `VACUUM`/`REINDEX`/bulk-reload per language, or the ability to
    drop/add a whole language cheaply;
  - **structural** protection against the cross-language leakage shown above —
    pruning requires the `lang` predicate, so a forgotten filter can't silently
    match other languages;
  - smaller, per-language GIN indexes once data is very large or skewed.
- Keep a composite PK `(product_id, lang)`; index `lang` only if you query it
  without a selective `tsvector` predicate (partitioning makes a separate `lang`
  index unnecessary).
- Reserve Option A (hand-rolled separate tables) for cases where languages have
  genuinely different columns; avoid Option B (wide row) entirely.

> Caveat for all FTS generated columns: `to_tsvector` is *declared* immutable but
> its output depends on the configuration's dictionaries. If you
> `ALTER TEXT SEARCH CONFIGURATION`, existing stored vectors are **not**
> recomputed — rebuild affected rows (e.g. a no-op `UPDATE`). This is why the
> config must be a named `regconfig`, never the mutable `default_text_search_config`.

---

## Summary

1. `to_tsvector(config, text)` normalizes a document: tokenize → run per-token
   dictionaries (stem, drop stop words, apply custom synonym/thesaurus dicts) →
   store sorted lexemes with positions and optional A/B/C/D weights.
2. `tsquery` is a boolean/phrase expression over lexemes; use
   `websearch_to_tsquery`/`plainto_tsquery` for untrusted input, `to_tsquery`
   when you build the expression yourself. Supports `& | ! <-> :*`.
3. `@@` matches document against query and is indexable.
4. Index via an **expression index**, or materialize a **stored generated
   column** (preferred for multi-field weighted search) — the expression must be
   `IMMUTABLE`, which is why you use `coalesce + ||` with a **named** config, not
   `format()` or the default config.
5. Use **GIN** (fast, exact, read-optimized) in almost all cases; use **GiST**
   only when write throughput outweighs read performance.
6. Rank with `ts_rank`/`ts_rank_cd` and present with `ts_headline`.
7. Combining FTS with scalar predicates is cost-based: same-table predicates may
   be intersected with a **BitmapAnd** (GIN + B-tree together), or one index may
   be used with the other predicate as a `Filter`; predicates on **different
   tables** are scanned separately and joined (no BitmapAnd). Verify with
   `EXPLAIN (ANALYZE, BUFFERS)`. See
   [combine-fts-with-scalar.sql](combine-fts-with-scalar.sql).
8. For **multi-language** catalogs, use one table with a row per
   (product, language) and a `regconfig` column driving the generated
   `tsvector` (`to_tsvector(regconfig,…)` is immutable even with a column
   config; language is **not** stored in the vector — `lang` is a separate
   column you must filter on). Always filter by `lang`. **Partition by `lang`
   for operations and leakage safety, not for this query's latency** — measured
   pruning gives only a marginal win on selective searches and none on broad
   ones. Storage/latency match table-per-language. See
   [multi-language-fts.sql](multi-language-fts.sql).
