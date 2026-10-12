# Estimating Table Size from Page Layout

A worked example of *why* a table occupies the space it does, by inspecting the
on-disk heap pages with the `pageinspect` extension and reconciling the result
with PostgreSQL's documented page layout.

## The table

```sql
CREATE TABLE t_test (id serial, name text);
INSERT INTO t_test (name) SELECT 'hans' FROM generate_series(1, 2000000);
INSERT INTO t_test (name) SELECT 'paul' FROM generate_series(1, 2000000);
```

4,000,000 short rows occupy **169 MB**:

```text
mytest=> \dt+ t_test
 Schema |  Name  | Type  |  Owner   | Persistence |  Size  | Description
--------+--------+-------+----------+-------------+--------+-------------
 public | t_test | table | postgres | permanent   | 169 MB |
```

## Inspect the heap pages

```sql
CREATE EXTENSION pageinspect;

-- how many tuples fit on a single 8 KB page?
SELECT count(*) FROM heap_page_items(get_raw_page('t_test', 0));   -- 185
SELECT count(*) FROM heap_page_items(get_raw_page('t_test', 1));   -- 185
```

Each page holds **185** tuples. A single line pointer / tuple looks like:

```text
mytest=> SELECT * FROM heap_page_items(get_raw_page('t_test', 1)) WHERE lp=1;
-[ RECORD 1 ]---------------------
lp          | 1
lp_off      | 8152
lp_len      | 33          <-- tuple length
t_xmin      | 584
t_ctid      | (1,1)
t_hoff      | 24          <-- header offset (HeapTupleHeaderData)
t_data      | \xba0000000b68616e73
```

## Reconcile with the documented page layout

Reference: <https://www.postgresql.org/docs/current/storage-page-layout.html>

```text
Block size                  8192 bytes
  PageHeaderData            24 bytes
  Per row:                  ItemId (4) + HeapTupleHeaderData (24) + data
    data = ceiling((4-byte id) + (text 'hans' = 1 len byte + 4 chars)) with alignment
    ~ 9 bytes actual data; per-row total ~ 44 bytes (incl. 4-byte ItemId)

Fits per page:  24 + 44 × 185 = 8164 bytes  (<= 8192)  -> 185 rows/page  ✓
```

## Estimate the total

```text
rows / rows_per_page × page_size
= 4,000,000 / 185 × 8 KB / 1024
≈ 168 MB   (matches the reported 169 MB)
```

## Takeaway

Table size is driven by **tuples-per-page**, which comes from the 8 KB block
minus the 24-byte page header, divided by (`ItemId` 4 B + tuple header 24 B +
aligned row data). For tiny rows the fixed 28-byte per-row overhead dominates —
here ~44 bytes of overhead+data per 9 bytes of actual data — so narrow tables
are far larger on disk than the raw column data suggests.
