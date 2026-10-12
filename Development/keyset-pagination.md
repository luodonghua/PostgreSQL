# Keyset pagination with `(last_modified_ts, id) < (?, ?)`

Keyset pagination (a.k.a. **seek method** or **cursor pagination**) fetches the
next page by *seeking* to the last row of the previous page instead of counting
and discarding rows with `OFFSET`. In PostgreSQL the clean, correct way to
express it for a compound sort key is a **row-value comparison**:

```sql
SELECT id, last_modified_ts, payload
FROM   feed
WHERE  (last_modified_ts, id) < (:last_ts, :last_id)   -- the seek
ORDER  BY last_modified_ts DESC, id DESC
LIMIT  :page_size;
```

`:last_ts` / `:last_id` are the `last_modified_ts` and `id` of the **last row the
previous page returned**. The first page simply omits the `WHERE`:

```sql
SELECT id, last_modified_ts, payload
FROM   feed
ORDER  BY last_modified_ts DESC, id DESC
LIMIT  :page_size;
```

All numbers below were measured on a 1,000,000-row table (PostgreSQL 18.6) where
~50 rows share each `last_modified_ts` (so ties are common and matter).

## Why a row-value comparison, not `AND`/`OR`?

`(a, b) < (x, y)` is SQL's **row-value (lexicographic) comparison**. It means
exactly "order by `a`, then `b`", i.e.:

```
(last_modified_ts, id) < (:last_ts, :last_id)
   ≡  last_modified_ts < :last_ts
      OR (last_modified_ts = :last_ts AND id < :last_id)
```

This `≡` is a **logical / correctness** equivalence — both return the same rows.
It is **not** a performance equivalence: on PostgreSQL only the row-value form
reliably becomes an index *seek*. Use the row-value form.

The row-value form is preferred because:

1. **It is correct across ties.** The second line is what continues *within* a
   group of equal timestamps instead of skipping the rest of the group.
2. **The planner turns it into a single index range scan.** PostgreSQL
   understands `ROW(...) < ROW(...)` against a matching multicolumn B-tree and
   emits one `Index Cond`, seeking straight to the start position — see the plan
   below. The expanded `OR` form, although logically identical, is **not**
   recognized as one contiguous index range: the planner applies it as a
   post-scan `Filter`, so it reads from the top of the index and discards the
   leading rows (see the measured comparison below).

### Measured: row-value seek vs. the expanded `OR` filter

Same cursor, same table, same `LIMIT 10` — only the predicate shape differs:

```
(A) WHERE (last_modified_ts, id) < (:ts, :id)
    ->  Index Cond: (ROW(last_modified_ts, id) < ROW(:ts, :id))
        actual rows=10        Buffers: 4           ← true seek

(B) WHERE last_modified_ts < :ts
       OR (last_modified_ts = :ts AND id < :id)
    ->  Filter: ((last_modified_ts < :ts) OR (last_modified_ts = :ts AND id < :id))
        Rows Removed by Filter: 50001
        actual rows=10        Buffers: 562         ← scans + filters, not a seek
```

The `OR` form touched ~140× more buffers here and gets worse the deeper you page
(like `OFFSET`). Reordering the `OR` clauses does not help — it stays a `Filter`.

**When you must use the `OR` form:** mixed sort directions, e.g.
`ORDER BY last_modified_ts DESC, id ASC`. A single `(a, b) < (x, y)` can't
express "a descending, b ascending", so you fall back to
`a < ? OR (a = ? AND b > ?)` and accept the filter cost (or redesign the key).

### `id` is the tiebreaker — without it you lose or repeat rows

`last_modified_ts` is **not unique** (50 rows share each value here). If you page
on the timestamp alone, a page boundary that lands in the middle of a tie will
**skip** the rest of that second. Demonstrated on the live table — the previous
page ended at `id = 950010` inside the tie `ts = 05:16:40` (ids 950049…950000):

```sql
-- CORRECT: continue within the tie
WHERE (last_modified_ts, id) < ('…05:16:40', 950010)
--> next ids: 950009, 950008, 950007, …     (nothing lost)

-- WRONG: timestamp only
WHERE last_modified_ts < '…05:16:40'
--> next ids: 949999, 949998, …             (ids 950009 … 950000 SILENTLY SKIPPED)
```

The naive form jumped past 10 rows. Appending a unique column (`id`) makes the
sort key **total** (no ties), so every row has exactly one position and pages
tile the result perfectly.

## The index that makes it fast

The index must match the `ORDER BY` **columns and directions** so the scan reads
rows in order and the seek is a single descent:

```sql
CREATE INDEX idx_feed_page ON feed (last_modified_ts DESC, id DESC);
```

Here `DESC, DESC` matches `ORDER BY last_modified_ts DESC, id DESC`. (A plain
`(last_modified_ts, id)` index also works for this query because B-trees can be
scanned backwards, but matching directions is the clearest and also helps when
mixing directions.) Selecting only indexed columns additionally enables an
**Index Only Scan** (`Heap Fetches: 0`).

## EXPLAIN plans (measured, 1,000,000 rows)

### First page — direct index scan

```
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, last_modified_ts FROM feed
ORDER BY last_modified_ts DESC, id DESC
LIMIT 10;

Limit (actual rows=10 loops=1)
  Buffers: shared hit=1 read=3
  ->  Index Only Scan using idx_feed_page on feed (actual rows=10 loops=1)
        Heap Fetches: 0
        Buffers: shared hit=1 read=3
```

### Keyset next page — one seek, one `Index Cond`

```
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, last_modified_ts FROM feed
WHERE (last_modified_ts, id) < ('2024-01-01 05:16:40+08', 950000)
ORDER BY last_modified_ts DESC, id DESC
LIMIT 10;

Limit (actual rows=10 loops=1)
  Buffers: shared hit=3 read=1
  ->  Index Only Scan using idx_feed_page on feed (actual rows=10 loops=1)
        Index Cond: (ROW(last_modified_ts, id) < ROW('2024-01-01 05:16:40+08', 950000))
        Heap Fetches: 0
        Buffers: shared hit=3 read=1
```

Note the `Index Cond: ROW(...) < ROW(...)` — the row-value comparison became a
single index range bound. The scan **starts at the cursor** and reads 10 rows.
**~4 buffers**, constant regardless of how deep the page is.

### The OFFSET anti-pattern — scans and discards everything before the page

```
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, last_modified_ts FROM feed
ORDER BY last_modified_ts DESC, id DESC
OFFSET 500000 LIMIT 10;

Limit (actual rows=10 loops=1)
  Buffers: shared hit=5 read=1914
  ->  Index Only Scan using idx_feed_page on feed (actual rows=500010 loops=1)
        Heap Fetches: 0
        Buffers: shared hit=5 read=1914
```

`actual rows = 500010`: OFFSET still **reads and throws away all 500,000
preceding rows** to return 10. It touched **~1919 buffers** versus ~4 for keyset.

### Side by side

| Approach | Rows the executor touches | Buffers (page 50,001) | Scales with page depth? |
|----------|---------------------------|------------------------|-------------------------|
| `OFFSET 500000 LIMIT 10` | 500,010 | ~1919 | **Yes — O(offset), gets slower** |
| Keyset `(ts,id) < (…)` | 10 | ~4 | **No — O(page size), constant** |

OFFSET cost grows linearly with how far you page; keyset cost is flat because it
seeks directly to the cursor via the index.

## Why it's a best practice

- **Constant-time pages.** Page 1 and page 100,000 cost the same — ideal for
  infinite-scroll feeds, APIs, and exports over large tables.
- **Stable under concurrent writes.** OFFSET shifts when rows are inserted or
  deleted (you re-skip a moving target → duplicates or gaps). A keyset cursor is
  anchored to actual data values, so it stays consistent as the table changes.
- **Index-friendly.** A single `Index Cond` seek + an Index Only Scan; no sort,
  no discarded rows.

### Trade-offs / caveats

- **No random "jump to page 937".** Keyset only moves relative to a known cursor
  (next/previous). That's usually fine for feeds; if you truly need numbered page
  jumps, OFFSET (or a precomputed page map) is the tool.
- **The cursor must be the full sort key.** Carry *every* `ORDER BY` column in
  the cursor (`last_modified_ts` **and** `id`), or ties break pagination.
- **Match directions.** For `ORDER BY a DESC, b DESC` use `(a, b) < (?, ?)`; for
  `ASC, ASC` use `> `. Mixed directions (`a DESC, b ASC`) can't use a single
  row-value comparison — split it into the explicit
  `a < ? OR (a = ? AND b > ?)` form and index `(a DESC, b ASC)`.
- **Index must cover the ORDER BY.** Without `idx_feed_page`, the query falls back
  to a full sort and the seek advantage disappears.

## Application loop (pseudocode)

```python
cursor = None                                    # (last_ts, last_id)
while True:
    if cursor is None:
        rows = db.query("""
            SELECT id, last_modified_ts, payload FROM feed
            ORDER BY last_modified_ts DESC, id DESC
            LIMIT %s""", [PAGE])
    else:
        rows = db.query("""
            SELECT id, last_modified_ts, payload FROM feed
            WHERE (last_modified_ts, id) < (%s, %s)
            ORDER BY last_modified_ts DESC, id DESC
            LIMIT %s""", [cursor[0], cursor[1], PAGE])
    if not rows:
        break
    handle(rows)
    last = rows[-1]
    cursor = (last.last_modified_ts, last.id)    # pass this to the next request
```

Expose the cursor to clients as an opaque token (e.g. base64 of `ts,id`) so the
next request just echoes it back.

See also: [btree.md](Indexes/btree.md) (why the composite B-tree seek is cheap),
[index-comparison.md](Indexes/index-comparison.md).
