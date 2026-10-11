# Inspecting Heap & Index Pages with pageinspect

The [`pageinspect`](https://www.postgresql.org/docs/14/pageinspect.html#id-1.11.7.32.4)
extension exposes the raw, on-disk layout of PostgreSQL pages — heap tuples and
B-tree index entries — as ordinary rows you can query. It is a debugging and
learning tool: it lets you see line pointers, tuple headers, item/ctid pointers,
and the hex-encoded tuple data that normally live hidden inside 8 KB blocks.

This walkthrough builds a small table `t`, adds three B-tree indexes, inserts a
few rows, and then uses `pageinspect` to look at the heap page and each index
page. It finishes by inserting a wider row to show how variable-length index
entries grow.

## Installing the extension

```sql
create extension pageinspect;
```

```text
mytest=> create extension pageinspect;
CREATE EXTENSION
mytest=> \dx
                                List of installed extensions
    Name     | Version |   Schema   |                      Description
-------------+---------+------------+-------------------------------------------------------
 pageinspect | 1.8     | public     | inspect the contents of database pages at a low level
 plpgsql     | 1.0     | pg_catalog | PL/pgSQL procedural language
(2 rows)
```

## Setting up the table and indexes

A simple three-column table with a unique index on `id`, a plain index on
`name`, and a composite index on `(id, name)`:

```sql
create table t (id int, name varchar(10), extra text);
create unique index t_id on t(id);
create index t_name on t(name);
create index t_id_name on t(id,name);
```

```text
mytest=> \d t
                        Table "public.t"
 Column |         Type          | Collation | Nullable | Default
--------+-----------------------+-----------+----------+---------
 id     | integer               |           |          |
 name   | character varying(10) |           |          |
 extra  | text                  |           |          |
Indexes:
    "t_id" UNIQUE, btree (id)
    "t_id_name" btree (id, name)
    "t_name" btree (name)
```

Insert four rows and look at their `ctid` — the physical `(block, offset)`
location of each row in the heap:

```sql
insert into t values(1,'a','xxxx');
insert into t values(2,'a','xxxx');
insert into t values(3,'b','xxxx');
insert into t values(4,'c','xxxx');
select ctid,* from t;
```

```text
mytest=> select ctid,* from t;
 ctid  | id | name | extra
-------+----+------+-------
 (0,1) |  1 | a    | xxxx
 (0,2) |  2 | a    | xxxx
 (0,3) |  3 | b    | xxxx
 (0,4) |  4 | c    | xxxx
```

All four rows live in block `0` at offsets `1`–`4`.

## Heap page inspection

`page_header(get_raw_page('t', 0))` reads block `0` of the heap and decodes its
24-byte page header; `heap_page_items(...)` decodes the line pointers and tuple
headers on that page.

```sql
SELECT * FROM page_header(get_raw_page('t', 0));
SELECT * FROM heap_page_items(get_raw_page('t', 0));
```

The page header shows where free space sits inside the block. `lower` (40) is
the end of the line-pointer array; `upper` (8032) is the start of the tuple data
that grows downward from the end of the page; the gap between them is free space.

```text
mytest=> SELECT * FROM page_header(get_raw_page('t', 0));
    lsn     | checksum | flags | lower | upper | special | pagesize | version | prune_xid
------------+----------+-------+-------+-------+---------+----------+---------+-----------
 0/1C020408 |        0 |     0 |    40 |  8032 |    8192 |     8192 |       4 |         0
(1 row)
```

Switching to expanded display (`\x`), `heap_page_items` shows one record per
line pointer. Key fields:

- `lp` / `lp_off` / `lp_len` — the line pointer index, the byte offset of the
  tuple within the page, and its length. Tuples are packed from the end of the
  page downward (8152, 8112, 8072, 8032 — 40 bytes apart).
- `t_ctid` — self-pointer `(0,1)`…`(0,4)`, matching the `ctid` seen above.
- `t_xmin` — the inserting transaction id (586–589 here).
- `t_hoff` — 24-byte tuple header offset before the user data begins.
- `t_data` — the hex-encoded column values.

```text
mytest=> SELECT * FROM heap_page_items(get_raw_page('t', 0));
 lp | lp_off | lp_flags | lp_len | t_xmin | t_xmax | t_field3 | t_ctid | t_infomask2 | t_infomask | t_hoff | t_bits | t_oid |          t_data
----+--------+----------+--------+--------+--------+----------+--------+-------------+------------+--------+--------+-------+--------------------------
  1 |   8152 |        1 |     35 |    586 |      0 |        0 | (0,1)  |           3 |       2306 |     24 |        |       | \x0100000005610b78787878
  2 |   8112 |        1 |     35 |    587 |      0 |        0 | (0,2)  |           3 |       2306 |     24 |        |       | \x0200000005610b78787878
  3 |   8072 |        1 |     35 |    588 |      0 |        0 | (0,3)  |           3 |       2306 |     24 |        |       | \x0300000005620b78787878
  4 |   8032 |        1 |     35 |    589 |      0 |        0 | (0,4)  |           3 |       2306 |     24 |        |       | \x0400000005630b78787878
(4 rows)
```

Reading `t_data` for record 1, `\x0100000005610b78787878`:

- `01000000` — `id = 1` (4-byte little-endian int).
- `0561` — the `varchar` `name`: a 1-byte varlena header (`05` = length 2 →
  1 char) followed by `61` (`'a'`).
- `0b78787878` — the `text` `extra`: `0b` varlena header followed by
  `78 78 78 78` (`'xxxx'`).

(The last row records a one-off decode check: `convert_from('\x78','utf-8')`
returns `x`, confirming `0x78` is the ASCII `x` seen in `'xxxx'`.)

## B-tree index inspection

For B-tree indexes, `pageinspect` provides three functions:

- `bt_metap(index)` — the metapage: version, `root` block, tree `level`.
- `bt_page_stats(index, blkno)` — per-page summary: page `type` (`l` = leaf),
  live/dead item counts, average item size, free space, sibling links.
- `bt_page_items(index, blkno)` — the individual index tuples, each pointing at
  a heap `ctid`/`htid`.

Across all three indexes below the metapage is identical in shape: a single-page
tree where `root` and `fastroot` are block `1` at `level` `0`, so block `1` is a
leaf and also the root.

### Unique index `t_id`

```sql
SELECT * FROM bt_metap('t_id');
SELECT * FROM bt_page_stats('t_id', 1);
SELECT itemoffset, ctid, itemlen, nulls, vars, data, dead, htid, tids[0:2] AS some_tids
FROM bt_page_items('t_id', 1);
```

```text
mytest=> SELECT * FROM bt_metap('t_id');
-[ RECORD 1 ]-----------+-------
magic                   | 340322
version                 | 4
root                    | 1
level                   | 0
fastroot                | 1
fastlevel               | 0
oldest_xact             | 0
last_cleanup_num_tuples | -1
allequalimage           | t

mytest=> SELECT * FROM bt_page_stats('t_id', 1);
-[ RECORD 1 ]-+-----
blkno         | 1
type          | l
live_items    | 4
dead_items    | 0
avg_item_size | 16
page_size     | 8192
free_size     | 8068
btpo_prev     | 0
btpo_next     | 0
btpo          | 0
btpo_flags    | 3
```

Each leaf item carries the indexed key (`data`) and a heap pointer
(`ctid`/`htid`). For the integer `id` the key is an 8-byte little-endian value:
`01 00 00 00 ...` for `id = 1`, up to `04 ...` for `id = 4`. `vars = f` because
`int` is fixed-length.

```text
mytest=> SELECT itemoffset, ctid, itemlen, nulls, vars, data, dead, htid, tids[0:2] AS some_tids
mytest-> FROM bt_page_items('t_id', 1);
-[ RECORD 1 ]-----------------------
itemoffset | 1
ctid       | (0,1)
itemlen    | 16
nulls      | f
vars       | f
data       | 01 00 00 00 00 00 00 00
dead       | f
htid       | (0,1)
some_tids  |
-[ RECORD 2 ]-----------------------
itemoffset | 2
ctid       | (0,2)
itemlen    | 16
nulls      | f
vars       | f
data       | 02 00 00 00 00 00 00 00
dead       | f
htid       | (0,2)
some_tids  |
-[ RECORD 3 ]-----------------------
itemoffset | 3
ctid       | (0,3)
itemlen    | 16
nulls      | f
vars       | f
data       | 03 00 00 00 00 00 00 00
dead       | f
htid       | (0,3)
some_tids  |
-[ RECORD 4 ]-----------------------
itemoffset | 4
ctid       | (0,4)
itemlen    | 16
nulls      | f
vars       | f
data       | 04 00 00 00 00 00 00 00
dead       | f
htid       | (0,4)
some_tids  |
```

### Plain index `t_name`

```sql
SELECT * FROM bt_metap('t_name');
SELECT * FROM bt_page_stats('t_name', 1);
SELECT itemoffset, ctid, itemlen, nulls, vars, data, dead, htid, tids[0:2] AS some_tids
FROM bt_page_items('t_name', 1);
```

The metapage and page stats match `t_id` exactly (single leaf page, 4 live
items, avg item size 16). Here `vars = t` because `varchar` is variable-length,
and the `data` is the varlena-encoded key: `05 61` for `'a'`, `05 62` for `'b'`,
`05 63` for `'c'`. Note that `name` is stored in index order, so the two `'a'`
rows (`(0,1)` and `(0,2)`) come first.

```text
mytest=> SELECT * FROM bt_metap('t_name');
-[ RECORD 1 ]-----------+-------
magic                   | 340322
version                 | 4
root                    | 1
level                   | 0
fastroot                | 1
fastlevel               | 0
oldest_xact             | 0
last_cleanup_num_tuples | -1
allequalimage           | t

mytest=> SELECT * FROM bt_page_stats('t_name', 1);
-[ RECORD 1 ]-+-----
blkno         | 1
type          | l
live_items    | 4
dead_items    | 0
avg_item_size | 16
page_size     | 8192
free_size     | 8068
btpo_prev     | 0
btpo_next     | 0
btpo          | 0
btpo_flags    | 3

mytest=> SELECT itemoffset, ctid, itemlen, nulls, vars, data, dead, htid, tids[0:2] AS some_tids
mytest-> FROM bt_page_items('t_name', 1);
-[ RECORD 1 ]-----------------------
itemoffset | 1
ctid       | (0,1)
itemlen    | 16
nulls      | f
vars       | t
data       | 05 61 00 00 00 00 00 00
dead       | f
htid       | (0,1)
some_tids  |
-[ RECORD 2 ]-----------------------
itemoffset | 2
ctid       | (0,2)
itemlen    | 16
nulls      | f
vars       | t
data       | 05 61 00 00 00 00 00 00
dead       | f
htid       | (0,2)
some_tids  |
-[ RECORD 3 ]-----------------------
itemoffset | 3
ctid       | (0,3)
itemlen    | 16
nulls      | f
vars       | t
data       | 05 62 00 00 00 00 00 00
dead       | f
htid       | (0,3)
some_tids  |
-[ RECORD 4 ]-----------------------
itemoffset | 4
ctid       | (0,4)
itemlen    | 16
nulls      | f
vars       | t
data       | 05 63 00 00 00 00 00 00
dead       | f
htid       | (0,4)
some_tids  |
```

### Composite index `t_id_name`

```sql
SELECT * FROM bt_metap('t_id_name');
SELECT * FROM bt_page_stats('t_id_name', 1);
SELECT itemoffset, ctid, itemlen, nulls, vars, data, dead, htid, tids[0:2] AS some_tids
FROM bt_page_items('t_id_name', 1);
```

The composite key packs both columns into `data`: the 4-byte `id` followed by
the varlena `name`. For example `01 00 00 00 05 61` is `id = 1` + `'a'`.

```text
mytest=> SELECT * FROM bt_metap('t_id_name');
-[ RECORD 1 ]-----------+-------
magic                   | 340322
version                 | 4
root                    | 1
level                   | 0
fastroot                | 1
fastlevel               | 0
oldest_xact             | 0
last_cleanup_num_tuples | -1
allequalimage           | t

mytest=> SELECT * FROM bt_page_stats('t_id_name', 1);
-[ RECORD 1 ]-+-----
blkno         | 1
type          | l
live_items    | 4
dead_items    | 0
avg_item_size | 16
page_size     | 8192
free_size     | 8068
btpo_prev     | 0
btpo_next     | 0
btpo          | 0
btpo_flags    | 3

mytest=> SELECT itemoffset, ctid, itemlen, nulls, vars, data, dead, htid, tids[0:2] AS some_tids
mytest-> FROM bt_page_items('t_id_name', 1);
-[ RECORD 1 ]-----------------------
itemoffset | 1
ctid       | (0,1)
itemlen    | 16
nulls      | f
vars       | t
data       | 01 00 00 00 05 61 00 00
dead       | f
htid       | (0,1)
some_tids  |
-[ RECORD 2 ]-----------------------
itemoffset | 2
ctid       | (0,2)
itemlen    | 16
nulls      | f
vars       | t
data       | 02 00 00 00 05 61 00 00
dead       | f
htid       | (0,2)
some_tids  |
-[ RECORD 3 ]-----------------------
itemoffset | 3
ctid       | (0,3)
itemlen    | 16
nulls      | f
vars       | t
data       | 03 00 00 00 05 62 00 00
dead       | f
htid       | (0,3)
some_tids  |
-[ RECORD 4 ]-----------------------
itemoffset | 4
ctid       | (0,4)
itemlen    | 16
nulls      | f
vars       | t
data       | 04 00 00 00 05 63 00 00
dead       | f
htid       | (0,4)
some_tids  |
```

## What if the data is larger than 16 bytes?

Insert a row with a large `id` and a 10-character `name`, then re-read each
index. The default `avg_item_size`/`itemlen` of 16 bytes only holds for short
keys — a wider key produces a longer index tuple.

```sql
insert into t values(1000000000,'abcdefghij','yyyy');
SELECT itemoffset, ctid, itemlen, nulls, vars, data, dead, htid, tids[0:2] AS some_tids
FROM bt_page_items('t_id', 1);
SELECT itemoffset, ctid, itemlen, nulls, vars, data, dead, htid, tids[0:2] AS some_tids
FROM bt_page_items('t_name', 1);
SELECT itemoffset, ctid, itemlen, nulls, vars, data, dead, htid, tids[0:2] AS some_tids
FROM bt_page_items('t_id_name', 1);
```

In `t_id` the new key stays 16 bytes (fixed-length `int`): `1000000000` encodes
as `00 ca 9a 3b` at `(0,5)`.

```text
mytest=> SELECT itemoffset, ctid, itemlen, nulls, vars, data, dead, htid, tids[0:2] AS some_tids
mytest-> FROM bt_page_items('t_id', 1);
 itemoffset | ctid  | itemlen | nulls | vars |          data           | dead | htid  | some_tids
------------+-------+---------+-------+------+-------------------------+------+-------+-----------
          1 | (0,1) |      16 | f     | f    | 01 00 00 00 00 00 00 00 | f    | (0,1) |
          2 | (0,2) |      16 | f     | f    | 02 00 00 00 00 00 00 00 | f    | (0,2) |
          3 | (0,3) |      16 | f     | f    | 03 00 00 00 00 00 00 00 | f    | (0,3) |
          4 | (0,4) |      16 | f     | f    | 04 00 00 00 00 00 00 00 | f    | (0,4) |
          5 | (0,5) |      16 | f     | f    | 00 ca 9a 3b 00 00 00 00 | f    | (0,5) |
(5 rows)
```

In `t_name` the 10-char `'abcdefghij'` needs a 24-byte item (`itemlen = 24`):
`17` varlena header + `61 62 63 64 65 66 67 68 69 6a` (the ASCII bytes). It also
sorts into its alphabetical position, between the `'a'` entries and `'b'`.

```text
mytest=> SELECT itemoffset, ctid, itemlen, nulls, vars, data, dead, htid, tids[0:2] AS some_tids
FROM bt_page_items('t_name', 1);
 itemoffset | ctid  | itemlen | nulls | vars |                      data                       | dead | htid  | some_tids
------------+-------+---------+-------+------+-------------------------------------------------+------+-------+-----------
          1 | (0,1) |      16 | f     | t    | 05 61 00 00 00 00 00 00                         | f    | (0,1) |
          2 | (0,2) |      16 | f     | t    | 05 61 00 00 00 00 00 00                         | f    | (0,2) |
          3 | (0,5) |      24 | f     | t    | 17 61 62 63 64 65 66 67 68 69 6a 00 00 00 00 00 | f    | (0,5) |
          4 | (0,3) |      16 | f     | t    | 05 62 00 00 00 00 00 00                         | f    | (0,3) |
          5 | (0,4) |      16 | f     | t    | 05 63 00 00 00 00 00 00                         | f    | (0,4) |
(5 rows)
```

In the composite `t_id_name` the new entry combines both wide values:
`00 ca 9a 3b` (`id`) + `17 61 … 6a` (`name`), again 24 bytes.

```text
mytest=> SELECT itemoffset, ctid, itemlen, nulls, vars, data, dead, htid, tids[0:2] AS some_tids
mytest-> FROM bt_page_items('t_id_name', 1);
 itemoffset | ctid  | itemlen | nulls | vars |                      data                       | dead | htid  | some_tids
------------+-------+---------+-------+------+-------------------------------------------------+------+-------+-----------
          1 | (0,1) |      16 | f     | t    | 01 00 00 00 05 61 00 00                         | f    | (0,1) |
          2 | (0,2) |      16 | f     | t    | 02 00 00 00 05 61 00 00                         | f    | (0,2) |
          3 | (0,3) |      16 | f     | t    | 03 00 00 00 05 62 00 00                         | f    | (0,3) |
          4 | (0,4) |      16 | f     | t    | 04 00 00 00 05 63 00 00                         | f    | (0,4) |
          5 | (0,5) |      24 | f     | t    | 00 ca 9a 3b 17 61 62 63 64 65 66 67 68 69 6a 00 | f    | (0,5) |
```

A quick decode check confirms the ASCII mapping used throughout
(`0x78` is `x`):

```sql
select convert_from('\x78','utf-8');
```

```text
 convert_from
--------------
 x
```

## Takeaways

- `pageinspect` turns the opaque 8 KB page into queryable rows — `page_header`,
  `heap_page_items`, `bt_metap`, `bt_page_stats`, and `bt_page_items` cover the
  heap and B-tree internals you most often want to see.
- A heap tuple's `t_ctid` is a self-pointer to its own `(block, offset)`, and
  every B-tree leaf entry's `ctid`/`htid` points back at the heap tuple it
  indexes — this is the physical link that index scans follow.
- `t_data` and the index `data` are the raw column bytes: fixed-length types
  (`int`) store a plain little-endian value, while variable-length types
  (`varchar`, `text`) carry a 1-byte varlena length header before the content.
- Index tuples are stored in **key order**, not insert order — the `'abcdefghij'`
  row slots between the `'a'` and `'b'` entries in `t_name`.
- Short keys fit in the typical 16-byte item; a longer value (10-char `name`)
  grows the entry to 24 bytes, so wider keys mean larger, less dense indexes.
- A single-page B-tree has `root = fastroot = 1` at `level 0`, meaning block `1`
  is simultaneously the root and the only leaf (`type = l`).
