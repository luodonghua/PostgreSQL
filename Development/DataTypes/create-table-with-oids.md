# Legacy `WITH OIDS` Tables

Older PostgreSQL let a table carry a hidden system column `oid` via
`WITH (oids=true)`. This was **removed in PostgreSQL 12** — the clause now errors.
This note shows the old behavior and the modern error.

## Creating a table with OIDs (pre-12)

```sql
CREATE TABLE t1 (id int);
CREATE TABLE t2 (id int) WITH (oids=true);
```

`\d+` shows the `Has OIDs: yes` marker on `t2`:

```text
mytest=> \d+ t2
                                    Table "public.t2"
 Column |  Type   | ... | Description
--------+---------+ ... +-------------
 id     | integer | ... |
Has OIDs: yes
```

## The OID is assigned on insert

```sql
INSERT INTO t1 VALUES (1);   -- INSERT 0 1   (no oid)
INSERT INTO t2 VALUES (1);   -- INSERT 16408 1  (oid = 16408)
```

A table without OIDs can't be queried by `oid`, but an OID table can:

```text
mytest=> SELECT oid,* FROM t1;
ERROR:  column "oid" does not exist

mytest=> SELECT oid,* FROM t2;
  oid  | id
-------+----
 16408 |  1

mytest=> SELECT * FROM t2 WHERE oid=16408;
 id
----
  1
```

## The hidden `oid` is a real system column

Comparing `pg_attribute` for the two tables, `t2` has an extra `oid` column
alongside the usual system columns (`cmin`, `cmax`, `ctid`, `xmin`, `xmax`,
`tableoid`):

```text
-- t1: 7 system/user columns, no oid
-- t2: 8 columns, incl. oid
mytest=> SELECT attrelid,attname FROM pg_attribute WHERE attrelid = 't2'::regclass;
 attrelid | attname
----------+----------
    16405 | cmax
    16405 | cmin
    16405 | ctid
    16405 | id
    16405 | oid
    16405 | tableoid
    16405 | xmax
    16405 | xmin
(8 rows)
```

## Modern PostgreSQL (12+) rejects it

```sql
CREATE TABLE t2 (id int) WITH (oids=true);
```

```text
-- tested on PG 13.4 (OIDs desupported since PG 12)
ERROR:  tables declared WITH OIDS are not supported
```

**Takeaway:** don't rely on table OIDs. If you need a stable row identifier, use
an explicit `GENERATED ... AS IDENTITY` (or `serial`/`bigserial`) column.
