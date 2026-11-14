# slot-peek — see what is waiting in a logical replication slot

`slot-peek` shows the changes a logical replication slot is holding: which transactions,
tables, operations and keys, and the row values. It **never consumes the slot**, and on
PostgreSQL 12+ it doesn't disturb the slot's consumer either. Use it to:

- **Troubleshoot lag.** What is the subscriber stuck behind? One huge transaction? Which table?
- **Reconcile after a failover or promotion.** List the changes the subscriber never applied,
  and generate SQL to replay them.
- **Audit a slot** that belongs to a CDC tool (Debezium, AWS DMS, pglogical, ...).

## Start here: the simple scripts (no objects created)

For the common case, troubleshooting native logical replication, use one of these. Each is
**one read-only `SELECT`**: it creates no functions, tables or slot copies, so it needs no
change approval. They return the same rows; pick the one that matches how you work:

| | For | How you set the slot name and limit |
|---|---|---|
| [`sql/peek_pgoutput_simple.sql`](sql/peek_pgoutput_simple.sql) | `psql` | `-v slot=... -v limit=...` on the command line |
| [`sql/peek_pgoutput_ide.sql`](sql/peek_pgoutput_ide.sql) | **SQL IDEs** (pgAdmin, DBeaver, DataGrip, ...) | Edit the three values in the `params` block at the top, then run |

### In an IDE

1. Connect to the publisher, to the database the slot belongs to.
2. Open `peek_pgoutput_ide.sql` in the query editor.
3. Edit the `params` block at the top, then run the whole statement:

```sql
WITH RECURSIVE params AS (
  SELECT 'my_slot'::text AS slot_name,      -- <== EDIT: the replication slot name
         100             AS row_limit,      -- <== EDIT: changes to show (a transaction is always read to its end)
         ''::text        AS publications    -- <== EDIT (optional): comma-separated publication names; empty = all publications
),
```

It has no psql commands, no `?` or `:name` markers, and is one statement, so IDEs run it as-is.
The result is a single grid. The first row, with no `lsn`, describes what was read. **Problems
show up in that row too** (missing slot, slot in use, wrong plugin, other database, no
publication) instead of as an error. If the limit was hit, the last row says so.

```
    lsn    |          commit_time          | schema_name | table_name  | operation |         pk         | note
-----------+-------------------------------+-------------+-------------+-----------+--------------------+------------------------------------------
           |                               |             |             |           |                    | slot app_sub | publications app_pub | pending WAL 716 kB (from 0/17AC5F0) | showing up to 6 changes
 0/17AC5F0 | 2026-11-13 22:41:04.295705+08 | public      | orders      | INSERT    | id=2               |
 0/17AC6B0 | 2026-11-13 22:41:04.304097+08 | public      | order_items | INSERT    | order_id=2, line=1 |
 0/17AC770 | 2026-11-13 22:41:04.309823+08 | public      | orders      | UPDATE    | id=1               |
 0/17AC7D0 | 2026-11-13 22:41:04.309823+08 | public      | order_items | DELETE    | order_id=1, line=2 |
 0/17AC848 | 2026-11-13 22:41:04.380405+08 | public      | order_items | INSERT    | order_id=3, line=1 |
 0/17AC8D8 | 2026-11-13 22:41:04.380405+08 | public      | order_items | INSERT    | order_id=3, line=2 |
           |                               |             |             |           |                    | Limit reached: more changes may be pending. Increase row_limit in the params block to see them.
```

### With psql

```bash
psql -v slot=app_sub -f peek_pgoutput_simple.sql                  # first 100 changes
psql -v slot=app_sub -v limit=1000 -f peek_pgoutput_simple.sql    # more rows
psql -v slot=app_sub -v publication=app_pub -f peek_pgoutput_simple.sql
```

It assumes:
- a **pgoutput** slot (native logical replication),
- the slot is **not in use**: either pause the subscription first (`ALTER SUBSCRIPTION <sub> DISABLE;` on the
  subscriber, `ENABLE` afterwards), or, on PostgreSQL 12+, [peek a copy of the slot](#if-the-slot-is-in-use-copy-it-first-postgresql-12).
  Application writes continue either way; the slot just keeps its WAL meanwhile,
- a role with `REPLICATION` (RDS/Aurora: `rds_replication`); any PostgreSQL 10+.

#### If the slot is in use: copy it first (PostgreSQL 12+)

The simple scripts refuse a slot that has an active consumer. Instead of pausing the
subscription, peek a copy. Copying doesn't touch the original or its consumer. Run on the
publisher, in the slot's database:

```sql
-- 1. Copy the slot (keeps the pgoutput plugin; starts at the original's current position)
SELECT pg_copy_logical_replication_slot('app_sub', 'app_sub_peek', false);   -- false = not temporary
```

```bash
# 2. Run the script against the copy (use the copy's name in -v slot=, or in the params block of the IDE script)
psql -v slot=app_sub_peek -v publication=app_pub -f peek_pgoutput_simple.sql
```

```sql
-- 3. Drop the copy when done
SELECT pg_drop_replication_slot('app_sub_peek');
```

- **The `peek_pgoutput_*.sql` scripts only decode pgoutput slots.** The copy keeps the original's
  plugin, so for a slot owned by another tool (`test_decoding`, `wal2json`, `pglogical_output`, ...)
  pass `'pgoutput'` as the fourth argument, and give the publication name:

  ```sql
  SELECT pg_copy_logical_replication_slot('cdc_slot', 'cdc_slot_peek', false, 'pgoutput');
  ```

  Without it the script stops with `slot '...' uses plugin 'test_decoding' - this script only decodes pgoutput`.
  For such a slot the output is only an approximation of what the original consumer sees: it
  lists just the tables of the publication you name. To see every table, use
  [`slot_peek.sql`](sql/slot_peek.sql) instead.
- The copy must be **non-temporary** (`false`): a temporary slot is dropped when the copying
  session ends, so it would be gone by the time the script runs in another session.
- Drop the copy promptly. It retains WAL like any slot until dropped.
- It needs one free replication slot (`max_replication_slots`) and the `REPLICATION` role.
- The copy starts from the original's position at copy time, so it can still show changes the
  consumer has applied since. If you need the current backlog, drop the copy and make a new one.

Output, one row per change (lsn, commit time, schema, table, operation, primary key):

```
slot app_sub | publications app_pub | pending WAL 716 kB (from 0/17AC5F0) | limit 100
    lsn    |          commit_time           | schema_name | table_name  | operation |         pk
-----------+--------------------------------+-------------+-------------+-----------+---------------------
 0/17AC5F0 | 2026-11-13 22:35:15.961678 +08 | public      | orders      | INSERT    | id=2
 0/17AC6B0 | 2026-11-13 22:35:15.968513 +08 | public      | order_items | INSERT    | order_id=2, line=1
 0/17AC770 | 2026-11-13 22:35:15.972451 +08 | public      | orders      | UPDATE    | id=1
 0/17AC7D0 | 2026-11-13 22:35:15.972451 +08 | public      | order_items | DELETE    | order_id=1, line=2
 0/17AC848 | 2026-11-13 22:35:16.030953 +08 | public      | order_items | INSERT    | order_id=3, line=1
 0/17AC8D8 | 2026-11-13 22:35:16.030953 +08 | public      | order_items | INSERT    | order_id=3, line=2
 ...
(100 rows)

Limit reached: more changes may be pending. Re-run with a larger -v limit=... to see them.
```

| Column | Meaning |
|---|---|
| `lsn` | WAL position of the change. Changes of one transaction share a `commit_time` |
| `pk` | The replica-identity (key) columns and values, enough to find the row on the subscriber. For `UPDATE` it is the **old** key if the key changed. For a table with `REPLICA IDENTITY FULL`, all columns are listed. `TRUNCATE` has no key |
| `pending WAL` | WAL between the slot's `confirmed_flush_lsn` and now: how far behind the subscriber is |

Behaviour to know:
- **`limit`** counts changes shown (default 100). A transaction is always read to its end, so one
  huge transaction can take a while (a 60,000-row one took about 4 seconds in the test lab).
  `-v timeout=300s` (default) stops runaway reads.
- It shows changes of the publications' tables only. An unknown `publication=` name returns
  nothing and the server prints a `skipped loading publication` warning.
- It refuses, with a clear message, when the slot doesn't exist, belongs to another database,
  isn't pgoutput, or is in use.
- It shows keys only, not row values, and doesn't generate replay SQL. Use the tools below for those.

Both scripts were verified identical (lsn, table, operation, key) to the full tool for 60,016
changes on PostgreSQL 12, 14, 16 and 18. They created no catalog objects and left the slot's
position unchanged.

## The full tools

If you need row values, replay SQL, an in-use slot, other plugins, or a summary, use these:

There are two equivalent implementations with the same output (the SQL one creates helper
functions in `pg_temp`, which disappear with the session). Pick the one that suits you:

| | Python | SQL (psql + PL/pgSQL) |
|---|---|---|
| Files | [`python/slot_peek.py`](python/slot_peek.py) | [`sql/overview.sql`](sql/overview.sql), [`sql/slot_peek.sql`](sql/slot_peek.sql), [`sql/position.sql`](sql/position.sql) |
| Needs | Python 3.8+ and `psycopg` 3 **or** `psycopg2` ([`requirements.txt`](python/requirements.txt)) | `psql` only |
| Installs anything on the server? | No | No persistent objects; session-local helpers in `pg_temp` |
| Extra output formats | `csv`, `jsonl` | — |

## Quick start

```bash
# 1. Publisher: list slots and what to run for each
python3 slot_peek.py overview                     psql -f overview.sql

# 2. Publisher: summary + changes waiting in a slot
python3 slot_peek.py peek --slot app_sub          psql -v slot=app_sub -f slot_peek.sql

# 3. Reconciliation: how far did the subscriber get?  (run on the SUBSCRIBER)
python3 slot_peek.py position                     psql -f position.sql
#    ... then replay SQL for everything after that point (run on the PUBLISHER)
python3 slot_peek.py peek --slot app_sub --format sql --since-lsn 0/17AC5F0 > replay.sql
psql -v slot=app_sub -v format=sql -v since_lsn=0/17AC5F0 -f slot_peek.sql > replay.sql
```

Connect to the **database the slot belongs to** (`overview` tells you which one). Connection
settings come from `--dsn "host=... dbname=... user=..."` or the usual `PG*` environment
variables (both tools).

## Which script do I use? (by PostgreSQL version)

You don't choose by version. The same script works on every version and picks the safe method
for the server:

| PostgreSQL | Slot plugin | What the tool does | Do I need to pause anything? |
|---|---|---|---|
| **12+** | pgoutput | Copies the slot to a temporary slot and decodes the copy with pgoutput. You see exactly what the subscriber will receive | **No** |
| **12+** | anything else (pglogical, wal2json, test_decoding, ...) | Copies the slot as a temporary `test_decoding` slot and decodes it as text | **No** |
| 10–11 | pgoutput or test_decoding | Peeks the slot directly. That only works while nothing is connected to it | **Yes**: the consumer must be paused ([below](#pausing-the-consumer-postgresql-1011-only)) |
| 10–11 | pglogical / others | Not supported (a slot can only be read with its own plugin before 12) | — |

On PostgreSQL 14+, large transactions are read in streamed chunks. One huge transaction
therefore can't make the tool decode gigabytes before returning ([why](#production-safety)).

## The two decoders

| | `pgoutput` (default when possible) | `text` (via `test_decoding`) |
|---|---|---|
| Used when | The slot's plugin is pgoutput and the publication names are known | Any other plugin, or publications unknown |
| Tables shown | Only what the publications send. Row filters and column lists are applied | **All** tables of the database |
| Key columns | Replica-identity columns, as the subscriber sees them | Primary key from the current catalog |
| Big transactions | Streamed in chunks on 14+ (bounded) | Bounded by a WAL window (`--wal-window` / `-v wal_window_mb`, default 256 MB) |
| Publication names | Auto-detected from the connected subscriber's walsender, or `--publication` / `-v publication=` | not needed |

Auto-detecting the publication needs `pg_read_all_stats`, or the role that owns the
subscriber's connection. Without it the tool says so and falls back to the text decoder.

## Sample output

From a lab where the subscriber was stuck behind a lock while the publisher kept writing
(the same output from both tools; Python shown, SQL is the psql-formatted equivalent).

`overview` (publisher):

```
PostgreSQL 18.6 (Ubuntu 18.6-1.pgdg24.04+2), database postgres, free replication slots: 9
slot     plugin    database  in use by                    pending WAL  retained WAL  how to inspect
-------  --------  --------  ---------------------------  -----------  ------------  -------------------
app_sub  pgoutput  postgres  pid 40294 app_sub 127.0.0.1  715.7 kB     716.5 kB      peek --slot app_sub
```

`peek --slot app_sub --publication app_pub --per-txn 3` (publisher):

```
Slot            : app_sub  (plugin pgoutput, not in use)
Server          : PostgreSQL 18.6 (Ubuntu 18.6-1.pgdg24.04+2)
Method          : temporary copy slot_peek_44197 (pgoutput); original slot untouched
Decoder         : pgoutput (publications: app_pub)
Pending WAL     : 1.8 MB  (confirmed_flush_lsn 0/17AC5F0 -> current 0/196F020)
Rows decoded    : 5017 (limit 1000; applied at transaction or stream-chunk boundaries)
Stopped early   : limit reached - more changes may follow; raise --limit to see them
Transactions    : 4 committed, 0 open (no commit seen in the scanned range)
Commit time     : 2026-11-13 21:39:41.629034+08:00  ..  2026-11-13 21:39:41.734406+08:00
Commit end LSN  : 0/17AC6B0  ..  0/185F4A0

table                insert   update   delete truncate
public.order_items     5001        0        1        0
public.orders             1        1        0        0

Largest transaction: xid 760 with 5000 changes
Logical messages: 1

end_lsn    commit_time              xid  status     table               op       key                             change
---------  -----------------------  ---  ---------  ------------------  -------  ------------------------------  ---------------------------------------------------------------------
0/17AC6B0  2026-11-13 21:39:41.629  756  committed  public.orders       INSERT   {"id": "2"}                     id=2, customer=Bob, amount=75.50, status=new
0/17AC770  2026-11-13 21:39:41.638  757  committed  public.order_items  INSERT   {"order_id": "2", "line": "1"}  order_id=2, line=1, sku=SKU-GREEN, qty=3
0/17AC848  2026-11-13 21:39:41.645  758  committed  public.orders       UPDATE   {"id": "1"}                     customer=Alice, amount=99.90, status=shipped
0/17AC848  2026-11-13 21:39:41.645  758  committed  public.order_items  DELETE   {"order_id": "1", "line": "2"}
0/17AC8C8  2026-11-13 21:39:41.648  759  committed  -                   MESSAGE                                  transactional {"prefix": "app", "content": "batch 2026-11-13 closed"}
0/185F4A0  2026-11-13 21:39:41.734  760  committed  public.order_items  INSERT   {"order_id": "3", "line": "1"}  order_id=3, line=1, sku=SKU-BULK, qty=1
0/185F4A0  2026-11-13 21:39:41.734  760  committed  public.order_items  INSERT   {"order_id": "3", "line": "2"}  order_id=3, line=2, sku=SKU-BULK, qty=1
0/185F4A0  2026-11-13 21:39:41.734  760  committed  public.order_items  INSERT   {"order_id": "3", "line": "3"}  order_id=3, line=3, sku=SKU-BULK, qty=1
... 4997 more changes of xid 760 not shown (--per-txn 3; use --format csv/jsonl/sql for all)
```

How to read it:

| Field | Meaning |
|---|---|
| `Pending WAL` | WAL between what the consumer has confirmed and now. This is how far behind it is |
| `Stopped early` | The row limit was reached, so more changes follow. Raise `--limit` / `-v limit=` to see them |
| `Transactions … open` | Transactions with no commit in the scanned range: still running on the publisher, or committed beyond `--limit` / the WAL window |
| `end_lsn` | End of the transaction's commit record. This is the value a subscriber reports as applied, so it can be compared with `position` |
| `key` | Replica-identity (pgoutput) or primary-key (text) columns. Use it to find the row on the subscriber |
| `change` | INSERT: all columns. UPDATE: `col: old -> new` where the old value is known, otherwise the new values. pgoutput sends old values only for `REPLICA IDENTITY FULL` or when the key changes |
| `status (applied)` | With `--since-lsn`: already applied by the subscriber |

`position` (subscriber):

```
subscription         enabled  slot                 applied up to    publications
app_sub              True     app_sub              0/17AC5F0        app_pub
```

`peek --slot app_sub --format sql --since-lsn 0/17AC5F0 --table public.orders` (publisher):

```sql
-- Generated by slot_peek.py 1.0 from slot app_sub, 2026-11-13T21:39:47
-- Review before running. Unchanged TOAST columns are left out of UPDATE SET lists.
-- Only transactions with end_lsn after 0/17AC5F0 (not yet applied by the subscriber).

-- xid 756 committed 2026-11-13 21:39:41.629034+08:00, end_lsn 0/17AC6B0
BEGIN;
INSERT INTO public.orders (id, customer, amount, status) VALUES ('2', 'Bob', '75.50', 'new');
COMMIT;

-- xid 758 committed 2026-11-13 21:39:41.645258+08:00, end_lsn 0/17AC848
BEGIN;
UPDATE public.orders SET id = '1', customer = 'Alice', amount = '99.90', status = 'shipped' WHERE id = '1';
COMMIT;

-- xid 759 committed 2026-11-13 21:39:41.648651+08:00, end_lsn 0/17AC8C8
BEGIN;
-- logical message: {"prefix": "app", "content": "batch 2026-11-13 closed"}
COMMIT;
```

`--format jsonl` (Python) prints one JSON object per change for scripting:

```json
{"commit_lsn": "0/17AC680", "end_lsn": "0/17AC6B0", "commit_time": "2026-11-13 21:39:41.629034+08:00", "xid": 756, "status": "committed", "applied": null, "origin": null, "schema": "public", "table": "orders", "op": "INSERT", "key": {"id": "2"}, "old": null, "new": {"id": "2", "customer": "Bob", "amount": "75.50", "status": "new"}, "unchanged_toast": [], "lsn": "0/17AC5F0"}
```

## Reconciliation workflow

Use this when a subscriber was promoted or cut over before it had received everything:

1. On the **subscriber**: `position` → note `applied up to` for the subscription.
2. On the **publisher** (if it still exists): `peek --slot <slot> --since-lsn <applied up to>`.
   Rows marked `(applied)` are already on the subscriber. The rest are not.
3. `--format sql` writes replay statements for the committed, not-yet-applied transactions,
   in commit order, one transaction per `BEGIN … COMMIT`.
4. **Review before running.** The statements are plain DML. They don't merge with changes made
   on the promoted side in the meantime: an `INSERT` may hit a duplicate key, an `UPDATE` may
   overwrite newer data.

Limits of the replay SQL:
- Values are emitted as text literals and rely on PostgreSQL's input conversion.
- An UPDATE leaves out columns whose large (TOAST) value was unchanged and therefore not
  logged. It does not set them to NULL.
- UPDATE/DELETE on a table without a key (replica identity `NOTHING`) can't be generated; a
  comment says so.
- Changes of transactions that were not committed in the scanned range are never included.

The replay SQL was checked by applying it to an empty copy of the schema and comparing every
table with the publisher: identical on PostgreSQL 12, 14, 16 and 18, for both decoders and both
tools. The test data covered composite keys, `REPLICA IDENTITY FULL`, a key change, an
unchanged TOAST column, a rolled-back savepoint, an aborted large transaction, quoted
identifiers, JSON, arrays, bytea and NULLs.

## Production safety

| Concern | What the tool does |
|---|---|
| Consuming the slot | Never. Only `pg_logical_slot_peek_*` is used, and on 12+ only on a temporary copy. The original slot's `confirmed_flush_lsn` was verified unchanged |
| Disturbing the consumer | On 12+ the consumer keeps running; copying doesn't wait for it or for open transactions |
| One huge transaction | The row limit is checked only between transactions. A single transaction without streaming is always decoded in full (1M rows took 17–25 s in a test). On 14+ pgoutput streams, so the limit applies per chunk, with session `logical_decoding_work_mem` set to `1MB` (`--decoding-mem`). The text decoder is bounded by the WAL window instead |
| Runaway statement | `statement_timeout` = 300 s by default (`--timeout` / `-v timeout=`) |
| Leftover slots | The copy is `TEMPORARY`: it is dropped explicitly, and also automatically if the session ends or is killed (verified) |
| Vacuum | The copy holds back catalog vacuum (`catalog_xmin`) only while the tool runs |
| Slot capacity | Needs one free slot (`max_replication_slots`). The tool checks and stops with a clear message if there isn't one |
| Publisher load | Decoding reads WAL and costs CPU, like a subscriber catching up. Keep `--limit` modest on busy systems |

## Pausing the consumer (PostgreSQL 10/11 only)

Only needed on PostgreSQL 10 and 11, where a slot can't be copied and an in-use slot can't be
peeked. On 12+ nothing needs to be paused. Pausing does **not** stop the application: writes on
the publisher continue. Only replication lags, and the slot keeps retaining WAL until the
consumer resumes, so keep the pause short.

| Consumer | Pause (run on the subscriber / consumer side) | Resume |
|---|---|---|
| Native subscription | `ALTER SUBSCRIPTION app_sub DISABLE;` | `ALTER SUBSCRIPTION app_sub ENABLE;` |
| pglogical | `SELECT pglogical.alter_subscription_disable('sub', true);` | `SELECT pglogical.alter_subscription_enable('sub', true);` |
| Debezium / Kafka Connect | Pause or stop the connector | Resume or start it |
| AWS DMS | Stop the replication task | Resume the task |

Then confirm on the publisher that the slot is free before running the tool:

```sql
SELECT slot_name, active FROM pg_replication_slots WHERE slot_name = 'app_sub';  -- active = f
```

If the slot is still in use, the tool refuses and prints these instructions.

## Requirements and privileges

- A role with **`REPLICATION`**. On RDS/Aurora, membership in **`rds_replication`**, which the
  master user has. Without it: `Only roles with the REPLICATION attribute may use replication slots`.
- Optional: `pg_read_all_stats`, to auto-detect the subscriber's publication names.
- One free replication slot (PostgreSQL 12+).
- `wal_level = logical` (already true wherever logical slots exist).
- **`output_plugin_libraries`** (new in 14.24, 15.19, 16.15, 17.11 and 18.6) lists the output
  plugins replication users may load. Its default is `pgoutput, test_decoding`, which are the
  only two plugins this tool uses. Other plugins (`pglogical_output`, `wal2json`, ...) must be
  added for **their own** consumers to work. It is a list setting, so write
  `ALTER SYSTEM SET output_plugin_libraries = pgoutput, test_decoding, pglogical_output;`
  without quotes around the whole list. With quotes, it becomes one library named
  `"pgoutput, test_decoding, pglogical_output"`.

## Limitations

- **Two-phase transactions** (`PREPARE TRANSACTION` with a `two_phase` subscription) are not supported.
- **PostgreSQL 10/11** were not tested on real servers (packages for them are no longer available).
  The 10/11 code path (direct peek of an idle slot, refusal of an in-use slot) was exercised by
  simulating the version on PostgreSQL 18.
- No native pglogical decoder: pglogical slots are read through the text decoder (PostgreSQL 12+).
- The text decoder shows every table in the database and takes key columns from the current
  catalog. If a table's definition changed since the change was written, use the pgoutput decoder.
- Old values of an UPDATE are only available with `REPLICA IDENTITY FULL` (or for key columns
  when the key changes).
- The Python tool decodes text as UTF-8. On servers with another encoding, use the SQL tool,
  which uses `server_encoding`.

## Tested

| Environment | Result |
|---|---|
| `peek_pgoutput_ide.sql`, PostgreSQL 12 and 18 | Same 60,016 changes as the psql script; sent as one plain query (no psql commands), through the extended protocol (`\bind`) and as a `PREPARE`d statement; all error cases reported in the note row. Not run in pgAdmin or DBeaver themselves |
| `peek_pgoutput_simple.sql`, PostgreSQL 12, 14, 16, 18 | 60,016 changes identical to the full tool; no catalog objects created, slot position unchanged; error paths checked (missing slot, other database, wrong plugin, slot in use, no publication); keys with multibyte text, bytea, uuid, timestamptz, bigint extremes, quoted schema and table names |
| PostgreSQL 12.22, 14.25, 16.16, 18.6 (local) | Both tools × both decoders: replay SQL identical to the publisher; original slot unchanged |
| pglogical 2.4.8 on PostgreSQL 18.7 | pglogical slot in use, read through the text decoder |
| Amazon RDS for PostgreSQL 18.6 | Both tools, both decoders, slot in use by a CDC client; as the master user and as a role with only `rds_replication`. Original slot unchanged, no copies left behind. RDS's `output_plugin_libraries` already lists `pgoutput, test_decoding, wal2json, decoder_raw, pglogical, pglogical_output, pgactive` |
| psycopg 3.1 and psycopg2 2.9 | Same results |
| Role with only `REPLICATION` | Works; publication auto-detect needs `pg_read_all_stats` |
| PostgreSQL 10/11 | Code path simulated only (see Limitations) |
