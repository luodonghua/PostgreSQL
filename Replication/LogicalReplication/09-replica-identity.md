# 09 — Replica Identity

Level: L300. Tested on PostgreSQL 18.6. Source: `utils/cache/relcache.c`
(`RelationGetReplicaIndex`), `replication/logical/relation.c`
(subscriber-side row lookup).

## What it is

For an UPDATE or DELETE the subscriber must find *which row* to change. The
publisher therefore writes into WAL — and sends in the stream — enough of the
**old** row to identify it. That "enough" is the table's **replica identity**,
set per table on the **publisher**:

| Setting | Old-row data logged | Requires | Typical use |
|---|---|---|---|
| `DEFAULT` | Primary-key columns | A primary key | Almost always |
| `USING INDEX idx` | Columns of that index | Unique, non-partial, non-deferrable index; all columns `NOT NULL` | Table with no PK but a natural unique key; or filter column added to the key ([topic 02](02-publications.md)) |
| `FULL` | **Entire old row** | Nothing | No usable key at all; downstream needs old values (CDC) |
| `NOTHING` | Nothing | — | Insert-only tables; blocks UPDATE/DELETE under a publishing publication |

```sql
ALTER TABLE t REPLICA IDENTITY FULL;
ALTER TABLE t REPLICA IDENTITY USING INDEX t_natural_key;
SELECT relname, relreplident FROM pg_class WHERE relname = 't';   -- d / f / i / n
```

## Publisher-side enforcement

If a publication publishes UPDATE/DELETE, the **publisher rejects** the write
when the table cannot identify rows (verified 18.6):

```
UPDATE n SET v='c';
ERROR:  cannot update table "n" because it does not have a replica identity and publishes updates
HINT:  To enable updating the table, set REPLICA IDENTITY using ALTER TABLE.
```

Applies to `NOTHING`, and to `DEFAULT` on a table without a PK. INSERT is
always fine. If the publication is `publish = 'insert'` only, no identity is
needed.

## What goes over the wire

From [topic 08](08-pgoutput-protocol.md):

- UPDATE with key unchanged → only the new tuple (the identity is the same
  in the new tuple; for `DEFAULT`/`INDEX`).
- UPDATE that **changes** key columns → `K` (old key) + `N` (new tuple).
- UPDATE under `FULL` → `O` (whole old row) + `N`.
- DELETE → `K` (old key) or `O` (old row under `FULL`).
- The `R` (Relation) message flags which columns are key columns.

## Cost of `FULL`

Measured on 18.6, 10 000 rows × (≈600 byte payload), `UPDATE w SET c = c + 1`
(touches a narrow column, the rest unchanged), WAL written:

| Identity | WAL for 10 000 updates |
|---|---|
| `DEFAULT` | 14 MB |
| `FULL` | 27 MB |

About 2× here; it scales with row width, since every update also logs the whole
old row. It also inflates the ReorderBuffer, network, and the subscriber's
lookup cost (next section). Use `FULL` as a last resort, not a default.

## The subscriber also needs an identity

The subscriber does **not** trust the publisher's choice for lookup; it uses its
**own** table definition to locate the row:

1. The subscriber table's **replica identity index** (`USING INDEX`), or its
   **primary key**; else
2. If the *publisher* sent the full old row (`FULL`), the subscriber may scan —
   using a suitable index if one exists (PG16+), else a **sequential scan per
   changed row**.

If neither is possible, the apply worker raises (verified 18.6, publisher had a
PK, subscriber table was created without one):

```
ERROR:  logical replication target relation "public.n" has neither REPLICA IDENTITY index nor PRIMARY KEY and published relation does not have REPLICA IDENTITY FULL
```

After `ALTER TABLE n ADD PRIMARY KEY (id)` on the subscriber the retrying
apply worker succeeded on its own (row `1|b`). Rule: **a primary key defined
on the publisher must also exist on the subscriber** (or an equivalent
replica-identity index).

### `FULL` without a good subscriber index = slow apply

Setup: 50 000-row table, `REPLICA IDENTITY FULL` on the publisher, publisher
updates N rows, time until the subscriber's `replay_lsn` caught up (single
run each; indicative, not a benchmark):

| Subscriber index | Rows updated | Caught up in |
|---|---|---|
| none (seq scan per row) | 100 | 0.06 s |
| none | 300 | **1.09 s** |
| `btree (id, v)` | 100 | 0.04 s |
| `btree (id, v)` | 300 | 0.06 s |
| `btree (id, v)` | 3 000 | 0.20 s |

With no index the cost is rows × table size — it explodes on large tables
(1 M rows × 10 000 updated rows = ten billion tuple comparisons). With *any*
btree (or hash, PG16+) index whose leading column is usable the subscriber
uses it to find candidates and then compares the rest of the row. Create
a decent index on the subscriber for every `FULL` table.

## Choosing an identity

```
Has a primary key? ──yes──> DEFAULT (and keep the same PK on the subscriber)
        │no
Has a unique NOT NULL index on a natural key? ──yes──> USING INDEX
        │no
Can you add a surrogate key / PK? ──yes──> add it (best long-term answer)
        │no
Insert-only table? ──yes──> publish='insert' (no identity needed) or NOTHING
        │no
        └──> FULL, plus a non-unique index on the subscriber to find rows
```

## Edge cases

- **Partitioned tables**: identity is a per-relation setting and is **not
  inherited**. Verified 18.6: after `ALTER TABLE pt REPLICA IDENTITY FULL` on
  the parent, the existing partition `pt1` and a partition created afterwards
  (`pt2`) both stayed `d`. Set it on every leaf partition you publish (and on
  the parent when using `publish_via_partition_root`).
- **Changing identity** (`ALTER TABLE … REPLICA IDENTITY`) takes a lock and
  takes effect for *new* WAL; already-written WAL keeps the old shape.
- **Dropping the identity index is allowed and silently dangerous.** Verified
  18.6: `DROP INDEX ri_x` succeeded, `relreplident` stayed `i`, and the table
  now has no usable identity (it behaves like `NOTHING`), so UPDATE/DELETE
  start failing. The audit query below checks for it.
- **Duplicate rows with `FULL`**: if the table has identical rows, the
  subscriber updates/deletes *one* of them (first match). Counts stay equal; row
  identities (ctid) may not. Usually harmless, but avoid relying on which.
- **TOAST**: with `FULL`, unchanged TOASTed columns in the old row are still
  sent (it is the old row), so `FULL` on tables with large values is expensive.
- **Generated columns** are not part of the identity.
- **NULLs**: an index with nullable columns cannot be an identity (`USING INDEX`
  requires `NOT NULL`), because `NULL ≠ NULL` would make rows unfindable.

## Checklist

- [ ] Every published table: PK, identity index, or deliberate `publish='insert'`.
- [ ] Same PK / identity index on the subscriber.
- [ ] If `FULL`: subscriber has an index; WAL volume impact understood.
- [ ] Row-filter columns are in the identity (topic 02).
- [ ] Column lists include the identity columns.
- [ ] Audit query:

```sql
-- publisher: tables in publications that cannot publish UPDATE/DELETE safely
SELECT pt.schemaname, pt.tablename
FROM pg_publication_tables pt
JOIN pg_class c ON c.oid = format('%I.%I', pt.schemaname, pt.tablename)::regclass
JOIN pg_publication p ON p.pubname = pt.pubname
WHERE (p.pubupdate OR p.pubdelete)
  AND (c.relreplident = 'n'
       OR (c.relreplident = 'd' AND NOT EXISTS
            (SELECT 1 FROM pg_index i WHERE i.indrelid = c.oid AND i.indisprimary))
       OR (c.relreplident = 'i' AND NOT EXISTS
            (SELECT 1 FROM pg_index i WHERE i.indrelid = c.oid AND i.indisreplident)));
```

Run on a test schema it flagged the table without a PK, the `NOTHING` table,
and (third branch) a table whose identity index had been dropped.
