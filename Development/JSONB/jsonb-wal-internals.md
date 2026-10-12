# What PostgreSQL writes to the WAL on UPDATE — JSONB vs relational

This note explains, with **real WAL records decoded from a live PostgreSQL 18.6
database** (via the `pg_walinspect` extension), what an `UPDATE` actually costs
and where a banking account `balance` should live for cheap, high-frequency
updates.

Companion files:
[hybrid-jsonb-banking.md](hybrid-jsonb-banking.md) ·
[hybrid-jsonb-banking.sql](hybrid-jsonb-banking.sql)

## The one thing to remember

The cost of an `UPDATE` is driven by the **size of the row it rewrites**, not by
which field changed or whether that field is a column or a JSONB key.

PostgreSQL (MVCC) never updates a row in place — every `UPDATE` writes a brand
new copy of the **whole row**. So a frequently-updated field like `balance`
should live in a **small, dedicated row**. If you bury it inside a large JSONB
document, every balance change rewrites the entire ~1 KB document.

A controlled test (same data, same workload, only the location of `balance`
differs) shows this directly:

| Where `balance` lives | Row size | WAL for 5 update rounds |
|-----------------------|----------|-------------------------|
| A column in a big ~680 B row | 681 B | 21 MB |
| A JSONB key in the same big row | 697 B | 21 MB |
| Its own narrow 37 B row | 37 B | ~4–5 MB |

Column vs JSONB key makes no real difference when the row is the same size. The
~4–5× saving comes entirely from keeping the hot row small.

## How an UPDATE becomes WAL

Every `UPDATE`:

1. Writes a **new tuple** (new row version) into a heap page.
2. Marks the old tuple as superseded (reclaimed later by `VACUUM`).
3. Emits a WAL record so the change survives a crash and reaches replicas.

Three properties of the WAL `heap_update` record matter here:

- **The row is identified by physical location** — `(relfilenode, block, item
  offset)` — not by primary key. Replay re-finds the row by its page and offset.
- **The new tuple is logged as a byte-range delta**: a common-prefix length, a
  common-suffix length, and the differing bytes in between. This is a physical
  byte diff, not a column-aware one — it simply skips leading/trailing bytes
  that happen to match the old tuple.
- **The first change to a page after a checkpoint also logs a full-page image**
  (FPI, ~8 KB) to protect against torn pages. Later changes to the same page in
  the same checkpoint cycle do not. Bulk updates touch many pages, so FPIs
  dominate their WAL volume.

### Reading the samples below

| Field | Meaning |
|-------|---------|
| `record_type` | heap operation (`HOT_UPDATE`, `INSERT`, `DELETE`, `LOCK`, …) |
| `main_data_length` | the record's fixed metadata (offsets, flags) |
| `record_length` | total bytes this WAL record occupies |
| `fpi_length` | bytes of full-page image (0 once the page is warm) |
| `block_ref` | `rel <tablespace>/<db>/<relfilenode> ... blk N` — the page touched |

The samples use three tables; this maps their `relfilenode` to a name:

| relfilenode | table | role |
|-------------|-------|------|
| `16556` | `account_balances` | balance in its own narrow row (good) |
| `16576` | `accounts_jsonb_only` | balance inside a ~1 KB inline JSONB (bad) |
| `16604` | `toast_demo` | a ~4 KB JSONB stored out-of-line in TOAST |
| `16611` | `pg_toast_16604` | `toast_demo`'s TOAST relation |
| `16612` | — | the TOAST relation's internal B-tree index |

All per-record samples are **steady state** (page already warm, `fpi_length = 0`)
so they show the true delta, not the one-time full-page image.

## Scenario 1 — balance in its own narrow row (good)

```sql
UPDATE account_balances SET balance = balance + 1 WHERE account_id = 1;
```

```
record_type | main_data_length | record_length | fpi_length | block_ref
------------+------------------+---------------+------------+---------------------------
HOT_UPDATE  |               14 |            71 |          0 | rel .../16556 ... blk 36
```

A single **71-byte** record. The row is only ~56 bytes and just the numeric
`balance` changed. It is a `HOT_UPDATE` (Heap-Only Tuple): the new version fits
on the same page and no indexed column changed, so no index WAL is produced
either. This is the cheapest possible update.

## Scenario 2 — balance inside a large inline JSONB (bad)

```sql
UPDATE accounts_jsonb_only
   SET doc = jsonb_set(doc, '{balance}', to_jsonb((doc->>'balance')::numeric + 1))
 WHERE account_id = 1;
```

The `doc` is ~1 KB — below the ~2 KB TOAST threshold — so it is stored inline in
the heap tuple. A single-row update produces a small record:

```
record_type | main_data_length | record_length | fpi_length | block_ref
------------+------------------+---------------+------------+----------------------------
HOT_UPDATE  |               14 |            71 |          0 | rel .../16576 ... blk 714
```

That 71 bytes is only the per-record byte-delta — the prefix/suffix diff skips
the unchanged part of the document, so one small key change stays small (a
mid-document change measured ~90 bytes). The real cost of the big row shows up
in three measurable ways:

**(a) Each new tuple is full-size.** `pageinspect` reports the stored length of
every row version (`lp_len`):

```sql
SELECT lp, lp_len FROM heap_page_items(get_raw_page('accounts_jsonb_only', 714)) WHERE lp_len>0 LIMIT 3;
--  lp | lp_len
--   1 |   1085        <- balance trapped in a ~1 KB row
SELECT lp, lp_len FROM heap_page_items(get_raw_page('account_balances', 36)) WHERE lp_len>0 LIMIT 3;
--  lp | lp_len
--   1 |     56        <- balance in its own narrow row
```

Every update rewrites the full tuple: ~1085 B in the big row vs ~56 B in the
narrow row — about 19× more data written per row version.

**(b) Heap bloat grows by one full tuple per update.** Starting from a
`VACUUM FULL`-compacted table, 10 full-table update rounds (no vacuum between):

| Table | Start | After 10 rounds |
|-------|-------|-----------------|
| `accounts_jsonb_only` (balance in big row) | 5.7 MB | 61 MB |
| `account_balances` (narrow row) | 296 kB | 3.2 MB |

The big-row table grew ~55 MB — roughly `5000 rows × 10 × ~1.1 KB`.

**(c) Bulk WAL is dominated by full-page images.** One full-table update round
(5000 rows), measured right after a `CHECKPOINT`:

| Table | WAL for one round |
|-------|-------------------|
| `accounts_jsonb_only` | 66 MB |
| `account_balances` | 5 MB |

The big-row table occupies ~5× more pages, and the first touch of each page
after a checkpoint logs an ~8 KB full-page image, so it pays far more FPI WAL.

## Scenario 3 — large JSONB left unchanged (TOAST pointer reused)

Here `toast_demo.big_doc` is ~4 KB of incompressible data, so it is stored
**out-of-line in the TOAST relation**; the heap tuple holds only an 18-byte
pointer to it. We update a *different*, small column:

```sql
UPDATE toast_demo SET hot_val = hot_val + 1 WHERE id = 1;   -- big_doc untouched
```

```
record_type | main_data_length | record_length | fpi_length | block_ref
------------+------------------+---------------+------------+--------------------------
LOCK        |                8 |            54 |          0 | rel .../16604 ... blk 14
HOT_UPDATE  |               14 |            71 |          0 | rel .../16604 ... blk 14
```

About **125 bytes total, and nothing written to the TOAST relation**. Because
`big_doc` did not change, the new heap tuple reuses the same TOAST pointer, so
the 4 KB of out-of-line data is neither rewritten nor WAL-logged. This TOAST
optimization only helps the columns you do *not* modify.

## Scenario 4 — change a key inside a large TOASTed JSONB

```sql
UPDATE toast_demo
   SET big_doc = jsonb_set(big_doc, '{balance}', to_jsonb((big_doc->>'balance')::numeric + 1))
 WHERE id = 1;
```

Modifying the JSONB forces it to be re-TOASTed from scratch. A single-row update
produces **11+ WAL records**:

```
rm          | record_type | record_length | block_ref
------------+-------------+---------------+-----------------------------------
Heap        | LOCK        |            54 | rel .../16604 blk 14   (lock old heap tuple)
Heap        | INSERT      |          2063 | rel .../16611 blk 2    (new TOAST chunk ~2 KB)
Btree       | INSERT_LEAF |            64 | rel .../16612 blk 67   (index the new chunk)
XLOG        | FPI_FOR_HINT|          8241 | rel .../16611 fsm       (free-space map FPI)
Heap        | INSERT+INIT |          2071 | rel .../16611 blk 3    (new TOAST chunk ~2 KB)
Btree       | INSERT_LEAF |            64 | rel .../16612 blk 67
Heap        | INSERT      |           115 | rel .../16611 blk 3    (new TOAST chunk, tail)
Btree       | INSERT_LEAF |            64 | rel .../16612 blk 67
Heap        | DELETE      |            54 | rel .../16611 blk 2    (old TOAST chunk)
Heap        | DELETE      |            54 | rel .../16611 blk 2    (old TOAST chunk)
Heap        | DELETE      |            54 | rel .../16611 blk 2    (old TOAST chunk)
Heap        | HOT_UPDATE  |            71 | rel .../16604 blk 14   (heap tuple gets new pointer)
Transaction | COMMIT      |            34 |
```

For one logical "balance + 1":

- The whole 4 KB JSONB is rebuilt and split into new ~2 KB TOAST chunks
  (`INSERT` into `pg_toast_16604`), each indexed (`Btree INSERT_LEAF`).
- The old TOAST chunks are deleted (three `DELETE` records).
- Finally the heap tuple is updated to point at the new chunks.

That is roughly **5 KB of WAL for a single row**, and it scales with the JSONB
size, not with what you logically changed.

## Summary

| Scenario | What changed | WAL records | Cost per row |
|----------|--------------|-------------|--------------|
| 1 — narrow row | small `numeric` column | 1 | ~71 B |
| 2 — balance in ~1 KB inline JSONB | one key | 1 | small record, but full ~1085 B tuple → heap bloat + FPI-heavy bulk WAL (66 MB/round) |
| 3 — large TOASTed JSONB unchanged | a sibling column | 2 | ~125 B, TOAST pointer reused |
| 4 — key inside ~4 KB TOASTed JSONB | one key | 11+ | ~5 KB, full re-TOAST + reindex |

The pattern across all four: an `UPDATE` is cheap when the row it rewrites is
small (Scenarios 1 and 3) and expensive when it is large (Scenarios 2 and 4).

## Design guidance

- Keep hot, high-write fields (`balance`, `status`, counters, timestamps) in a
  small, dedicated relational row so each update rewrites only a few dozen bytes.
- Reserve JSONB for complex, read-mostly data that is not touched by every
  hot-path write.
- Avoid trapping a frequently-updated field inside a large row — whether that
  bulk is a big JSONB document or many wide columns.
- When a large column must change often, remember TOAST only saves you while
  that column is left unchanged (Scenario 3); modifying it re-TOASTs the whole
  value (Scenario 4).

## Reproduce it yourself

```sql
CREATE EXTENSION IF NOT EXISTS pg_walinspect;

CHECKPOINT;                                                              -- start a fresh checkpoint cycle
UPDATE account_balances SET balance = balance + 1 WHERE account_id = 1;  -- warm the page (absorbs the one-time FPI)
SELECT pg_current_wal_lsn() AS s1 \gset
UPDATE account_balances SET balance = balance + 1 WHERE account_id = 1;  -- the measured update
SELECT pg_current_wal_lsn() AS s2 \gset

SELECT record_type, main_data_length, record_length, fpi_length, block_ref
FROM   pg_get_wal_records_info(:'s1', :'s2')
WHERE  resource_manager = 'Heap';
```

Tips:

- Always `CHECKPOINT` and run one warm-up update first; otherwise the measured
  record includes an ~8 KB full-page image that hides the real delta.
- `pg_get_wal_records_info(start_lsn, end_lsn)` decodes every record in the
  range. Filter by `resource_manager` (`Heap`, `Heap2`, `Btree`, `XLOG`,
  `Transaction`) to focus.
- Map a `relfilenode` back to a table with
  `SELECT relname, relfilenode, reltoastrelid FROM pg_class WHERE ...`.
