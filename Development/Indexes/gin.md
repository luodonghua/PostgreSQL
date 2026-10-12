# GIN — Generalized Inverted Index

GIN (Generalized Inverted Index) indexes **composite values that contain many
keys** — JSONB documents, arrays, and `tsvector` full-text documents. Instead of
indexing a row by a single value, GIN extracts every key from the value and maps
each key to the list of rows that contain it. This is the classic *inverted
index* used by search engines, generalized so any data type can plug in its own
key-extraction logic.

"Generalized" means the index does not hard-code any operator. A data type
supplies an opclass (extract-keys, compare, consistent-check functions) and GIN
provides the shared machinery. Source: `src/backend/access/gin/`.

## When to use it

- `jsonb` containment / existence: `@>`, `?`, `?|`, `?&` (opclass `jsonb_ops` or `jsonb_path_ops`)
- Arrays: `@>`, `<@`, `&&` (contains, is-contained-by, overlaps)
- Full-text search: `tsvector @@ tsquery`
- Trigram text search with `pg_trgm` (`LIKE`/`ILIKE`/`%` similarity)

```sql
CREATE INDEX idx_profile ON accounts USING gin (profile);
CREATE INDEX idx_profile_path ON accounts USING gin (profile jsonb_path_ops);
CREATE INDEX idx_doc_fts ON docs USING gin (to_tsvector('english', body));
```

## Core idea: one key stored once, many rows attached

A GIN index stores `(key, posting list)` pairs. The *posting list* is the set of
heap row pointers (TIDs) in which that key occurs. A key value is stored **once**
no matter how many rows contain it — this is why GIN handles duplicate keys so
efficiently and why it is compact for data where the same key appears in many
rows.

```
Item (row value)         Keys extracted        Inverted mapping GIN stores
----------------         --------------        ---------------------------
row 1: ['red','blue']    red, blue             red   -> {row1, row3}
row 2: ['green']         green                 blue  -> {row1}
row 3: ['red','green']   red, green            green -> {row2, row3}
```

A search for `@> ['red']` just looks up the key `red` and returns its posting
list `{row1, row3}` — no scan of non-matching rows.

### "Inverted" vs. a B-tree — the real difference

First, the thing that is **not** different: both are keyed by value and point to
rows by ctid. For a plain **scalar** column they are essentially the same shape —
and for scalars you should just use a B-tree (it's cheaper and ordered):

```
Scalar column `color text`  — B-tree and GIN look the SAME here:
  'blue'  → ctid(0,4)
  'green' → ctid(0,2)
  'red'   → [ctid(0,1), ctid(0,3)]     (both use a posting list for duplicates)
```

The inversion only *means* something when one column value decomposes into
**many** keys. Consider a single `text[]` array column:

```
Table (ONE array column `tags`):
  row1.tags = ['red','blue','green']
  row2.tags = ['green']
  row3.tags = ['red','green']

B-tree on `tags`                      GIN on `tags`
────────────────                      ─────────────
ONE entry per row; the whole array    ONE entry per extracted element;
is an opaque key:                     each element points back to its rows:
  ['green']              → r2            'blue'  → {r1}
  ['red','blue','green'] → r1            'green' → {r1, r2, r3}
  ['red','green']        → r3            'red'   → {r1, r3}

Query: "which rows contain 'red' as an element?"  (tags @> '{red}')
  B-tree: CAN'T — 'red' alone is not a key it stored; it only has
          whole-array keys, so it would scan every row.
  GIN:    one probe of key 'red' → {r1, r3}.
```

So the difference is **how many index entries one row produces**:

- **B-tree — one entry per row.** The key is the column's *whole* value, so it
  only helps when that value is a single comparable scalar (or you query the
  whole array/value exactly). (For duplicate scalars, modern B-trees
  *deduplicate* into one entry with a posting list of ctids — which is why the
  scalar example above looks identical to GIN.)
- **GIN — one entry per extracted key.** The opclass decomposes each value into
  its constituent keys, so a composite value fans out into many entries, all
  pointing back to the same row. That fan-out is exactly what lets you query the
  *contents* of a composite value.

The name comes from search engines: a document (row) contains many words (keys),
and the inverted index maps each word directly to the documents that contain it —
a one-row-to-many-keys mapping, versus a B-tree's one-row-to-one-key.

## Physical structure

A GIN index is made of four kinds of pages:

```
                         ┌───────────┐
                         │  METAPAGE │  (stats + pending-list head)
                         └─────┬─────┘
                               │
        ENTRY TREE (B-tree of distinct keys, sorted)
                         ┌─────┴─────┐
                         │  internal │
                         └─────┬─────┘
                 ┌─────────────┼─────────────┐
            ┌────┴───┐    ┌────┴───┐     ┌────┴───┐
            │ leaf   │    │ leaf   │ ... │ leaf   │   each leaf tuple = one key
            │ key=A  │    │ key=M  │     │ key=Z  │
            └───┬────┘    └───┬────┘     └────────┘
                │             │
   small list?  │             │  large list?
     inline     │             │   separate POSTING TREE
  ┌─────────────┴┐       ┌────┴──────────────────┐
  │ posting list │       │   posting tree (B-tree │
  │ TIDs inline  │       │   keyed by TID)        │
  │ (compressed) │       │  ┌──────┐  ┌──────┐    │
  └──────────────┘       │  │ leaf │  │ leaf │ …  │  compressed TID segments
                         │  └──────┘  └──────┘    │
                         └────────────────────────┘
```

1. **Metapage** — index-wide metadata and the head of the pending list.
2. **Entry tree** — a B-tree over the **distinct key values**, kept sorted. Each
   leaf tuple represents one key.
3. **Posting list (inline)** — if a key's TID set is small, the TIDs are stored
   directly inside the key's leaf tuple, in compressed form.
4. **Posting tree** — if a key occurs in too many rows to fit inline, the TIDs
   spill into a separate B-tree *keyed by TID*. The leaf tuple then holds a
   pointer to the posting-tree root instead of an inline list.

The code decides between the two cases with `GinIsPostingTree(itup)`; the leaf
tuple header is overloaded to store either the inline posting offset/count or the
posting-tree root block number (`GinGetPostingTree` / `GinSetPostingTree`).

> Note from the source README: **there is no delete operation in the entry
> tree.** The set of distinct keys in a large corpus changes very slowly, so GIN
> never removes key entries — this simplifies the concurrency and recovery code.
> VACUUM only removes dead TIDs from posting lists/trees, never keys.

## Posting-list compression (varbyte delta encoding)

TIDs in a posting list are sorted, so GIN stores **deltas** between successive
TIDs rather than absolute values, then applies **varbyte encoding** so small
deltas take fewer bytes.

```
TIDs (block,offset):     (10,2) (10,5) (10,9) (11,1)
combined into integers:  20482  20485  20489  22529    (block<<11 | offset)
stored as deltas:        20482  3      4      2040
varbyte encoded:         [bytes] [1B]  [1B]   [2B]      smaller deltas = fewer bytes
```

Each byte's high bit says "another byte follows," so a value is read until a byte
with the high bit clear. Block number + offset are packed into one integer: the
offset uses the low 11 bits (`MaxHeapTuplesPerPageBits`), the block number the
higher bits — 43 bits total, at most 6 bytes.

Posting-tree leaf pages store the TIDs as **multiple independent compressed
segments** rather than one big list. This lets a scan skip to the segment that
contains the target TID instead of decoding from the very start, and lets an
update re-encode only the affected segment.

## The pending list (`fastupdate`)

Retail insertion into an inverted index is expensive: one new row with many keys
means many separate entry-tree searches and posting-list updates. GIN's
`fastupdate` feature (on by default) buffers new entries first.

```
INSERT path with fastupdate = on
---------------------------------
new row ──► PENDING LIST (unordered "list pages", appended fast)
                 │
                 │  flushed when list is large enough, or by autovacuum,
                 │  or by gin_clean_pending_list()
                 ▼
            ENTRY TREE  (keys merged in bulk — one pass per key, not per row)
```

- Writes are cheap: entries are just appended to list pages.
- The win comes from merging: when the same key appears in many pending rows,
  it is inserted into the main tree once, not once per row.
- **Cost:** every search must linearly scan the pending list *in addition to* the
  main tree, so a large pending list slows reads. It is flushed when it exceeds
  `gin_pending_list_limit`, during autovacuum, or via `gin_clean_pending_list()`.

A pending entry always carries exactly one heap TID (stored in the normal
`t_tid`), with no posting list. The `GIN_LIST_FULLROW` page flag records whether
a page holds complete rows or a partial spill of one row's entries.

## Search algorithm (consistent check)

For a query, the opclass extracts the **query keys** and GIN looks each up in the
entry tree, retrieving a posting list per key. It then combines them according to
the operator's logic via the opclass **`consistent`** function:

```
query: profile @> '{"a":1,"b":2}'   (jsonb_ops extracts keys a=1, b=2)

   lookup a=1 -> posting {r1, r3, r9}
   lookup b=2 -> posting {r3, r7, r9}
                      │
   consistent(AND)    ▼
   candidate TIDs = {r3, r9}         (intersection, since @> needs both)
                      │
                      ▼
   recheck each candidate row against the real operator (lossy opclasses)
```

GIN matches only by **equality** on keys (plus a limited "partial match" range
feature). Anything finer — e.g. verifying exact JSONB structure — is done by a
**recheck** against the heap row, because some opclasses are lossy
(`jsonb_path_ops` hashes paths, so it is more compact but always rechecks).

`gin_fuzzy_search_limit` (default 0 = off) puts a soft random cap on result-set
size for queries dominated by very frequent keys.

## Concurrency (how reads and writes coexist)

Both the entry tree and each posting tree are **Lehman & Yao B-trees** with
right-links between siblings; GIN does not support backward scans, so no
left-links are needed.

- **Search** descends root→leaf taking a pin + shared lock on **one page at a
  time**, releasing the previous page before locking the next.
- **Stepping right:** a concurrent split can move the target key to the right
  sibling. The scan follows right-links, always locking the right sibling
  *before* releasing the current page, which guarantees it can never step onto a
  concurrently-deleted page.
- **Insert** descends keeping pins on root/internal pages, then re-locks the leaf
  in exclusive mode. If a split occurs, the parent is locked exclusively before
  the left child is unlocked (child-before-parent ordering avoids deadlock).
- **Page deletion** (VACUUM only, posting trees only) takes a full cleanup lock on
  the posting-tree root, then descends depth-first holding exclusive locks on the
  left siblings of the current path, so both downlink and right-link can be
  removed without a right-to-left lock order.

**Predicate locking** (for `SERIALIZABLE`): GIN locks logical key ranges, not
physical pages, at the finest level possible — a posting-tree root for an
equality key, or an entry-leaf page for the "gap" where a missing key would be.
With `fastupdate=on` every scan must also lock the metapage (the pending list
could hold a matching entry anywhere), which effectively becomes a full-index
predicate lock and causes more false conflicts.

## Trade-offs

| Strength | Weakness |
|----------|----------|
| Very compact when the same keys repeat across many rows (key stored once) | Slower, heavier updates than GiST (mitigated by `fastupdate`) |
| Fast lookups for "which rows contain this key" | No ordering / nearest-neighbor support |
| Excellent for JSONB, arrays, full-text, trigrams | Lossy opclasses need a heap recheck |
| Posting-list compression keeps indexes small | Large pending list slows reads until flushed |

## Key source files

| File | Responsibility |
|------|----------------|
| `gininsert.c` | building the index, inserting entries |
| `ginfast.c` | pending list / `fastupdate` |
| `ginget.c` | scan / search |
| `ginentrypage.c`, `gindatapage.c` | entry-tree and posting-tree page layout |
| `ginpostinglist.c` | varbyte posting-list compression |
| `ginbtree.c` | shared B-tree descent/split logic |
| `ginvacuum.c` | removing dead TIDs, posting-tree page deletion |

See also: [btree.md](btree.md), [hash.md](hash.md), [brin.md](brin.md),
[gist.md](gist.md), [spgist.md](spgist.md),
[index-comparison.md](index-comparison.md).
