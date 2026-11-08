# 13 — Limitations

Level: L300. Tested on PostgreSQL 18.6; everything marked "tested" was run. Items
that changed in newer releases are marked ⚠️ (non-GA) or by version.

A one-page answer to "will logical replication do X for me?"

## At a glance

| Area | Limitation | Workaround |
|---|---|---|
| DDL | Not replicated (`CREATE/ALTER/DROP`, indexes, constraints, grants) | Apply DDL on both sides in the right order; migration tooling |
| Sequences | Values not replicated (GA ≤ 18) | `setval` at cut-over; ⚠️ 19 adds sequence sync |
| Large objects | Not replicated | Store as `bytea`, or copy separately |
| Object kinds | Only tables (incl. partitioned) can be published | Publish the base tables; recreate views/matviews on the subscriber |
| Unlogged / temp tables | Cannot be published | Make the table logged |
| Foreign tables | Cannot be published | — |
| Table identity | Subscriber table must have the same schema-qualified name | Same name; `publish_via_partition_root` for partition differences |
| Row lookup | UPDATE/DELETE need a replica identity | [topic 09](09-replica-identity.md) |
| Conflicts | Detected, not auto-resolved (GA) | [topic 12](12-conflicts-and-error-handling.md) |
| Throughput | One apply worker per subscription | [topic 11](11-apply-workers-and-parallel-apply.md) |
| Subscriber | Must be writable (not a physical standby); tables must pre-exist | — |
| Cross-subscription consistency | None; independent streams | One subscription for tables that need atomic visibility |
| Initial copy | Not incremental; long snapshots hold back vacuum | Pre-seed (`pg_createsubscriber` 17+) |
| Security | Initial-copy and apply semantic differences (see below) | — |

## 1. DDL is not replicated

Verified in the decoder: `ALTER TABLE` never appears in the stream
([topic 06](06-logical-decoding.md)). Practical results, all tested on 18.6:

| Publisher operation | Effect on the subscription |
|---|---|
| `ADD COLUMN` (then writes using it) | Apply worker error `missing replicated column`; self-heals once the subscriber has the column ([topic 04](04-step-by-step-setup-guide.md) §9.1) |
| `RENAME TABLE t TO t2` | The publication follows the rename (`pg_publication_tables` shows `t2`), the subscriber has no `t2` → `ERROR: logical replication target relation "public.t2" does not exist`; stalls until you rename the subscriber's table too |
| `DROP TABLE` | Table leaves the publication automatically (confirmed); the subscriber still has its copy and a `pg_subscription_rel` entry until `REFRESH PUBLICATION` |
| `DROP COLUMN` | Publisher stops sending it; subscriber column must be nullable or have a default or inserts fail |
| `ALTER COLUMN TYPE` | Values are sent in text/binary of the *new* type; works if the subscriber type can parse it. Rewrites of the publisher table are not replicated as data changes |
| `CREATE INDEX`, constraints | Not replicated; define separately |
| `TRUNCATE` | Is replicated (if `publish` includes truncate) |
| `GRANT`, roles | Never replicated |

**Order rules** (summary):

- Additive (add column, add table): **subscriber first, then publisher**.
- Subtractive (drop column/table): **publisher first**, then subscriber.
- Rename: coordinate; treat as drop+add or pause the subscription:
  `DISABLE` → rename both → `ENABLE`.
- Type widening (`int → bigint`): subscriber first. Narrowing: refuse, or
  publisher first after verifying all values fit.

DIY DDL replication: event triggers on the publisher can emit
`pg_logical_emit_message` with the DDL text, and an external process applies it
on the subscriber. Fragile; prefer a migration tool run against both.

## 2. Sequences

Tested: 5 rows inserted through a `serial` column; the subscriber had the 5
rows but its sequence `last_value` was still 1 (publisher: 5).

The sequence is an independent object: only the *row data* travels. If you
promote the subscriber, new inserts collide with existing ids. Cut-over
procedure:

```sql
-- publisher (stopped for writes), per sequence
SELECT last_value FROM t_id_seq;
-- subscriber
SELECT setval('t_id_seq', <last_value + safety_margin>);
```

Generate the statements for all sequences with a query over `pg_sequences`.
⚠️ **Non-GA (19 source):** `CREATE PUBLICATION … FOR ALL SEQUENCES` and a
sequence-sync worker (`sequencesync.c`) exist; not tested, details may change.

## 3. What can be published

Tested errors on 18.6:

```
CREATE PUBLICATION px FOR TABLE vv;   -- view
ERROR:  cannot add relation "vv" to publication
DETAIL:  This operation is not supported for views.
… materialized views:  This operation is not supported for materialized views.
… unlogged tables:     This operation is not supported for unlogged tables.
```

(Temporary tables can't be named from another session at all.) Large objects:
created one on the publisher; `pg_largeobject_metadata` count publisher = 1,
subscriber = 0.

Partitioned tables are supported since PG13; see
[topic 02](02-publications.md) for the leaf-vs-root rules. Inheritance
children are separate tables and must be published explicitly.

## 4. TRUNCATE and foreign keys

On the publisher, `TRUNCATE parent` fails if a table references it
(`cannot truncate a table referenced in a foreign key constraint`) — the same
as ever. `TRUNCATE parent, child` in one statement works, and both tables were
emptied on the subscriber (tested). A `TRUNCATE` published in a publication
that doesn't contain the referencing table fails on the subscriber with the
same FK error (documented behaviour; I did not test this one). Keep FK-related tables in the same publication, or drop
`truncate` from `publish`.

## 5. Differences between publisher and subscriber tables

Tested on 18.6 with subscriber `a(id bigint, v numeric, s varchar(3), extra int default 7)`
vs publisher `a(id int, v int, s text)`:

| Difference | Result |
|---|---|
| Wider type (`int → bigint`, `int → numeric`) | Works |
| Extra subscriber column with default | Filled by its default (`extra = 7`) |
| Narrower type (`text → varchar(3)`, value `'toolong'`) | **Apply error** `value too long for type character varying(3)`; fixed by widening the column — the worker then succeeded on retry |
| Column order | Irrelevant (matched by name) |
| Missing subscriber column | Error (above) |
| Extra `NOT NULL` column without default on the subscriber | Insert fails |

General rule: values are converted through the types' text (or binary)
input/output functions. If the subscriber type can parse what the publisher
type prints, it works; otherwise the apply worker errors at that row.

## 6. Ordering and consistency

- Within one subscription: commit order is preserved.
- **Across subscriptions: no relationship.** A transaction touching table A (sub 1) and
  table B (sub 2) can be visible on the subscriber for A before B.
- During **initial sync**, tables become consistent one by one at different
  times; FKs between them can be violated transiently on the subscriber (the
  FK triggers are not fired during replication, so no error — but queries
  may see orphans).
- The subscriber is **eventually consistent** and *not* a snapshot of one
  publisher instant. Don't point a financial report at it expecting
  point-in-time integrity unless you quiesce first.

## 7. Operational limits

| Limit | Detail |
|---|---|
| WAL retention risk | Slots pin WAL ([topic 05](05-replication-slots.md)) |
| `wal_level = logical` | Restart to enable on GA; more WAL |
| Single-database slots | A logical slot is tied to one database; N databases need N subscriptions |
| Slot count | `max_replication_slots`, `max_wal_senders`; each tablesync adds temporaries |
| Long transactions | Delay delivery and slot creation ([06](06-logical-decoding.md), [07](07-reorderbuffer-and-large-transactions.md)) |
| Slots don't follow failover | Until PG17 failover slots ([topic 16](16-failover-and-ha.md)) |
| Two-phase | `two_phase` can only be changed under restrictions; `REFRESH` with copy blocked |
| Triggers | Don't fire on the subscriber for replicated rows unless `ENABLE REPLICA`/`ALWAYS` |
| Superuser operations | Some (`CREATE SUBSCRIPTION` without privileges, `SKIP`) need superuser; managed services may restrict them |
| Publisher version | ≥ 10; the subscriber can be any later version; older subscribers than the publisher are best-effort |

## 8. Things people expect that do not exist (GA)

- Automatic **conflict resolution** ("last update wins").
- **Row-level DDL replication** / schema auto-sync.
- **Replication of sequences** (⚠️ 19+).
- **Subscriber-side filtering by column renaming** — no column mapping or table renaming.
- **Multi-master** with guarantees. Bidirectional works only with
  `origin = none` and disciplined, disjoint writes ([topic 17](17-upgrades-and-migrations.md)).
- **Synchronous logical replication** is possible by listing the subscription's
  `application_name` in `synchronous_standby_names` (a logical walsender
  reports as that name); it adds commit latency and the subscriber's apply
  becomes a write availability dependency. Use with care and test failure
  behaviour first (I did not test it).
- **Replicating from a physical standby** needs PG16+ and has its own caveats
  ([topic 16](16-failover-and-ha.md)).

## 9. Security differences worth knowing

- The **initial copy** runs `COPY` as the connecting replication role with
  its `SELECT` privilege; row-level security applies to that role. Column
  lists/row filters are the *intended* data-minimisation tools.
- On the subscriber, with `run_as_owner = false` (default) each change is applied
  as the **table owner**, so RLS bypass depends on that owner's attributes
  ([topic 03](03-subscriptions.md)).
- `pg_subscription.subconninfo` contains the password; only superusers can
  read it.
