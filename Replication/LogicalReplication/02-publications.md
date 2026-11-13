# 02 — Publications

Level: L200 (with L300 detail on filters). Tested on PostgreSQL 18.6.

A **publication** lives on the publisher and answers one question: *which
changes of which tables are eligible to be sent?* It does not know who will
subscribe, and it does not hold any WAL. (WAL is held by the
[slot](05-replication-slots.md).)

## Defining the scope

```sql
CREATE PUBLICATION p_orders  FOR TABLE orders;                       -- explicit tables
CREATE PUBLICATION p_schema  FOR TABLES IN SCHEMA sales;             -- every table in a schema, including future ones
CREATE PUBLICATION p_all     FOR ALL TABLES;                         -- every table in the database, including future ones (superuser)
CREATE PUBLICATION p_empty;                                          -- no tables yet; ADD later
```

Rules worth knowing:

- Only **tables** (ordinary and partitioned) can be published on GA releases.
  Views, materialized views, foreign tables, sequences and large objects cannot.
- `FOR ALL TABLES` and `FOR TABLES IN SCHEMA` need superuser; `FOR TABLE`
  needs ownership of the table plus `CREATE` on the database.
  On **Amazon RDS / Aurora PostgreSQL** there is no superuser, and `rds_superuser`
  takes its place. Other roles get `ERROR: must be rds_superuser to create FOR ALL TABLES
  publication` ([topic 20 §1](20-amazon-rds-and-aurora.md#privileges-without-a-superuser)).
- You can mix forms in one publication (`ALTER PUBLICATION ... ADD TABLE`
  on a schema publication worked in my test).
- A table can be in several publications; a subscription may subscribe to
  several publications and receives the union.
- ⚠️ **Non-GA (19 source `gram.y`):** `FOR ALL SEQUENCES` and
  `FOR ALL TABLES EXCEPT (TABLE …)` exist in the 19 grammar. Not run by me.

Catalogs and views:

```sql
SELECT * FROM pg_publication;           -- options per publication
SELECT * FROM pg_publication_tables;    -- expanded: one row per published table, with attnames and rowfilter
```

Real output (18.6):

```
  oid  |  pubname   | pubowner | puballtables | pubinsert | pubupdate | pubdelete | pubtruncate | pubviaroot | pubgencols
-------+------------+----------+--------------+-----------+-----------+-----------+-------------+------------+------------
 16394 | pub_orders |       10 | f            | t         | t         | t         | t           | f          | n

  pubname   | schemaname | tablename |            attnames             | rowfilter
------------+------------+-----------+---------------------------------+-----------
 pub_orders | public     | orders    | {id,customer,amount,created_at} |
```

## `publish` — which operations

```sql
CREATE PUBLICATION p_nodelete FOR TABLE orders WITH (publish = 'insert, update');
```

Default is `insert, update, delete, truncate`. Omitting `delete` means deletes
on the publisher are *not* applied on the subscriber — handy for an
append-only archive, but the two sides then diverge by design.

## Replica identity decides whether UPDATE/DELETE are even allowed

If a publication publishes UPDATE or DELETE, the table must have a replica
identity (primary key by default). Otherwise the **publisher** rejects the
write — not the subscriber:

```
CREATE PUBLICATION p_all_tables FOR ALL TABLES;
UPDATE t_nopk SET b='y';
ERROR:  cannot update table "t_nopk" because it does not have a replica identity and publishes updates
HINT:  To enable updating the table, set REPLICA IDENTITY using ALTER TABLE.
```

Fix with `ALTER TABLE t_nopk REPLICA IDENTITY FULL;` (works, but see
[topic 09](09-replica-identity.md) for the cost). This is the most common
production surprise: creating a `FOR ALL TABLES` publication can start failing
application writes to tables without a primary key.

## Row filters (PG 15+)

```sql
CREATE PUBLICATION p_eu FOR TABLE sales.o WHERE (region = 'EU');
```

Semantics, all verified on 18.6:

- The filter is evaluated on the **publisher** for each change; rows that do
  not match are never sent. The initial table copy honours it too.
- For **UPDATE**, both the old and the new row are evaluated and the change is
  *transformed*:

  | Old row matches | New row matches | What the subscriber receives |
  |---|---|---|
  | yes | yes | UPDATE |
  | no | yes | **INSERT** |
  | yes | no | **DELETE** |
  | no | no | nothing |

  Test: with filter `region = 'EU'`, `UPDATE o SET region='EU' WHERE id=2`
  (was US) arrived as an INSERT, and `UPDATE o SET region='US' WHERE id=1`
  (was EU) removed the row on the subscriber.
- **A filter column must be part of the replica identity** if the publication
  publishes UPDATE or DELETE, otherwise the publisher rejects the write:

  ```
  ERROR:  cannot update table "o"
  DETAIL:  Column used in the publication WHERE expression is not part of the replica identity.
  ```

  Practical recipe: a unique, NOT NULL index containing the key *and* the
  filter column, then `REPLICA IDENTITY USING INDEX`:

  ```sql
  CREATE UNIQUE INDEX o_ri ON o (id, region);
  ALTER TABLE o REPLICA IDENTITY USING INDEX o_ri;      -- region must be NOT NULL
  ```
- Filter expressions are restricted: no user-defined functions/operators,
  no system columns, only immutable built-in functions. Filters are ignored for
  `TRUNCATE`.
- If a table appears in several publications of one subscription, the filters
  are OR-ed.
- Combining a filter with `publish_via_partition_root` uses the root table's
  columns for the expression.

## Column lists (PG 15+)

```sql
CREATE PUBLICATION p_pub FOR TABLE sales.o (id, region, total);   -- 'secret' never leaves
```

- The listed columns must include the replica identity columns when UPDATE or
  DELETE is published. I hit this with `REPLICA IDENTITY FULL` + a partial list:

  ```
  ERROR:  cannot update table "o"
  DETAIL:  Column list used by the publication does not cover the replica identity.
  ```
  (`FULL` means *all* columns, so a partial list can never cover it.)
- Columns not in the list arrive as defaults/NULL on the subscriber; the
  subscriber table may omit them or give them local defaults.
- You cannot drop a column that is in a list without dropping the dependency:

  ```
  ERROR:  cannot drop column total of table o because other objects depend on it
  DETAIL:  publication of table o in publication p depends on column total of table o
  ```
  (A useful safety net against accidental schema drift.)
- Changing a list: `ALTER PUBLICATION p SET TABLE o (id, region)`.
- A column list is not a security boundary against the *subscriber's role* —
  anyone with the replication privilege can still read the table another way —
  but it is a good data-minimisation tool.

## Partitioned tables and `publish_via_partition_root`

```
CREATE PUBLICATION p_part      FOR TABLE m;
CREATE PUBLICATION p_part_root FOR TABLE m WITH (publish_via_partition_root=true);

 pubname     | tablename
-------------+-----------
 p_part      | m1          <- leaf partitions are published under their own names
 p_part_root | m           <- changes are published as if made to the root
```

- **false (default):** changes are sent for the *leaf partition* that stores
  the row. The subscriber needs a matching table for each leaf partition
  (name/schema must match). A new partition on the publisher joins the
  publication automatically (`pg_publication_tables` listed `m2` right after
  `CREATE TABLE ... PARTITION OF`), but data written to it fails on the
  subscriber until the matching table exists there:

  ```
  ERROR:  logical replication target relation "public.m2" does not exist
  ```
  Create the partition on the subscriber first, then
  `ALTER SUBSCRIPTION ... REFRESH PUBLICATION` (the worker retries on its own
  once the table exists; I did not test the post-fix recovery).
- **true:** changes appear to come from the root table. The subscriber can be
  partitioned differently — or not partitioned at all. This is the knob that
  makes "partitioned → plain table" or "re-partition during migration" work.
- Row filters and column lists on a partitioned table use the root's
  definition when `true`.

## Generated columns (PG 18+)

```sql
CREATE PUBLICATION p_gen FOR TABLE g WITH (publish_generated_columns = stored);
```

Pre-18, stored generated columns were never published. In 18 the option has
two values — `none` (default, `pubgencols = 'n'`) and `stored` (`'s'`).
Tested on 18.6 with `b int GENERATED ALWAYS AS (a*2) STORED` on the publisher:

| Publication option | Subscriber column `b` | Result |
|---|---|---|
| `none` (default) | plain `int` | rows arrive, `b` is NULL |
| `stored` | plain `int` | rows arrive, `b` = 2, 4 (computed values copied) |
| `stored` | its own `GENERATED ... STORED` | **apply worker error**: `target relation "public.g" has incompatible generated column: "b"` |

So the subscriber-side column must be an ordinary column if you want the
published value; it cannot be a generated column itself.

## Changing a publication

```sql
ALTER PUBLICATION p ADD TABLE t2;
ALTER PUBLICATION p DROP TABLE t2;
ALTER PUBLICATION p SET TABLE t1, t2;        -- replaces membership
ALTER PUBLICATION p SET (publish = 'insert');
ALTER PUBLICATION p OWNER TO someone;
```

`ADD TABLE` only affects *future* changes. The subscriber has to
`ALTER SUBSCRIPTION ... REFRESH PUBLICATION` to start copying and tracking the
new table ([topic 03](03-subscriptions.md)).

## Permissions summary

| Action | Needed |
|---|---|
| Create publication | `CREATE` on the database |
| `FOR TABLE` | owner of each table |
| `FOR ALL TABLES` / `TABLES IN SCHEMA` | superuser (RDS/Aurora: `rds_superuser`, tested on RDS 18.6) |
| Subscriber connecting | role with `REPLICATION` (or superuser) **and** `SELECT` on published tables (for the initial copy) |

## Pitfalls checklist

- Table without a PK + `publish` includes update/delete → publisher write errors.
- Row filter column not in replica identity → publisher write errors.
- Column list narrower than replica identity (or with `FULL`) → publisher write errors.
- Publishing `FOR ALL TABLES` also publishes tables you create tomorrow —
  including ones the subscriber does not have, which stalls the apply worker.
- Forgetting `REFRESH PUBLICATION` after `ADD TABLE`.
- Expecting DDL or sequences to follow ([limitations](13-limitations.md)).
