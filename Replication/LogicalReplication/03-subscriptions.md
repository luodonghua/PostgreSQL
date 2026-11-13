# 03 — Subscriptions

Level: L200 → L300. Tested on PostgreSQL 18.6.

A **subscription** lives on the subscriber. It records the connection to the
publisher, the publication name(s) to follow, and the options that control how
changes are applied. Creating one normally does four things in one command:

1. connects to the publisher,
2. creates a **logical replication slot** there (named after the subscription
   unless `slot_name` is given),
3. records every published table in `pg_subscription_rel` (state `i`),
4. starts the **apply worker**, which launches **tablesync workers** to copy
   existing rows.

```sql
CREATE SUBSCRIPTION sub_orders
  CONNECTION 'host=pub.example.com port=5432 dbname=app user=repl password=… sslmode=verify-full'
  PUBLICATION pub_orders;
-- NOTICE:  created replication slot "sub_orders" on publisher
```

> `CREATE SUBSCRIPTION` cannot run inside a transaction block when it creates a
> slot. If the publisher is unreachable use `WITH (connect = false)` and
> create the slot yourself (below).

## Options

| Option | Default | What it does | Notes |
|---|---|---|---|
| `copy_data` | true | Copy existing rows at start (and on `REFRESH` for new tables) | `false` = start from "now"; you must have loaded the data yourself |
| `create_slot` | true | Create the slot on the publisher | `false` + `slot_name` to use a pre-created slot |
| `slot_name` | subscription name | Slot to use | `NONE` detaches (needed to drop a sub whose publisher is gone) |
| `enabled` | true | Start the worker now | |
| `connect` | true | Connect during CREATE | `false` implies `enabled=false, create_slot=false, copy_data=false` |
| `streaming` | `parallel` since 18 (`off` before) | How in-progress big transactions are received | `off` / `on` / `parallel` ([topic 07](07-reorderbuffer-and-large-transactions.md), [11](11-apply-workers-and-parallel-apply.md)) |
| `binary` | false | Use binary send/recv instead of text | Faster for some types; types must be binary-compatible |
| `two_phase` | false | Decode `PREPARE TRANSACTION` and apply at prepare time | Can only be set at creation (or while disabled with care); see gotcha below |
| `disable_on_error` | false | Auto-disable the subscription on apply error instead of retry loop | Stops the log spam; you must `ENABLE` |
| `synchronous_commit` | `off` | Commit mode of the apply worker on the subscriber | Visible as `subsynccommit` |
| `origin` | `any` | `any` = replicate everything; `none` = only changes that did not come from another replication origin | Basis for bidirectional setups ([topic 17](17-upgrades-and-migrations.md)) |
| `failover` | false | Slot is synchronised to physical standbys | ([topic 16](16-failover-and-ha.md)) |
| `password_required` | true | Non-superuser owners must connect with a password | Security guard |
| `run_as_owner` | false | Apply as the subscription owner instead of the table owner | Security: see below |
| ⚠️ `retain_dead_tuples`, `max_retention_duration` | off | Keep dead rows long enough to detect `update_deleted` conflicts | Non-GA, in 19 source (`subscriptioncmds.c`) |
| ⚠️ `wal_receiver_timeout` | server default | Per-subscription receiver timeout | Non-GA, in 19 source |
| ⚠️ `conflict_log_destination` | `log` | Send conflict details to a table too | Non-GA, 20devel master only |

### Real catalog row (18.6)

Created with `streaming=parallel, binary=true, disable_on_error=true, two_phase=true`:

```
subenabled          | t
subbinary           | t
substream           | p            -- f=off, t=on, p=parallel
subtwophasestate    | e            -- d=disabled, p=pending, e=enabled
subdisableonerr     | t
subpasswordrequired | t
subrunasowner       | f
subfailover         | f
subslotname         | s
subsynccommit       | off
subpublications     | {p}
suborigin           | any
subskiplsn          | 0/0
```

## Per-table state: `pg_subscription_rel`

| `srsubstate` | Meaning |
|---|---|
| `i` | initialise — queued for copy |
| `d` | data is being copied |
| `f` | copy finished, waiting for the apply worker to catch up |
| `s` | synchronised; tablesync has caught up and hands over |
| `r` | ready — normal replication (final state) |

```sql
SELECT srrelid::regclass, srsubstate, srsublsn FROM pg_subscription_rel;
 srrelid | srsubstate | srsublsn
 orders  | r          | 0/17C6048
```

A table stuck at `d` or `f` means the initial sync is stuck — see
[topic 10](10-initial-sync-tablesync.md) and [14](14-monitoring-and-troubleshooting.md).

## Day-2 commands

```sql
ALTER SUBSCRIPTION s DISABLE;                    -- stop worker; publisher slot stays and keeps accumulating WAL!
ALTER SUBSCRIPTION s ENABLE;
ALTER SUBSCRIPTION s CONNECTION 'host=newhost …';
ALTER SUBSCRIPTION s SET PUBLICATION p1, p2;     -- change which publications to follow
ALTER SUBSCRIPTION s ADD PUBLICATION p3;
ALTER SUBSCRIPTION s SET (streaming = parallel, binary = false, disable_on_error = true);
ALTER SUBSCRIPTION s REFRESH PUBLICATION;        -- pick up tables added to the publication
ALTER SUBSCRIPTION s REFRESH PUBLICATION WITH (copy_data = false);
ALTER SUBSCRIPTION s SKIP (lsn = '0/17AB8C8');   -- skip one failing remote transaction
ALTER SUBSCRIPTION s OWNER TO someone;
```

### Tested: adding a table later

On the publisher `ALTER PUBLICATION p ADD TABLE b;` then on the subscriber
`ALTER SUBSCRIPTION s REFRESH PUBLICATION;` — table `b` moved through the
states and ended in `r` with its pre-existing row copied:

```
 srrelid | srsubstate
 a       | r
 b       | r
```

Without the `REFRESH`, inserts into `b` were *not* applied (count stayed 0 in my test).

### Does a blocked copy of the new table stall the existing tables?

No. The tablesync worker for the new table is a separate process with its own temporary
slot. Creating that slot waits for every transaction that holds an xid, **instance-wide**:
in any schema, and in any database. The table stays in `d` and its walsender shows
`wait_event = transactionid` on `CREATE_REPLICATION_SLOT`. Meanwhile the apply worker keeps
streaming the tables already in `r` (verified with a 100 s blocker: the existing table kept
up throughout, no timeout fired, and no error was logged).

What the wait does cost:
- It holds one of the `max_sync_workers_per_subscription` workers, so other new tables queue in `i`.
- It holds one replication slot and one walsender on the publisher.
- The new table gets no changes until it reaches `r`. They are not lost: the copy snapshot
  is taken after the wait.

Find the blocker on the publisher:

```sql
SELECT pid, datname, xact_start, backend_xid
FROM pg_stat_activity WHERE backend_xid IS NOT NULL ORDER BY xact_start;
```

### Gotcha: `two_phase` blocks `REFRESH` with copy

```
ALTER SUBSCRIPTION s REFRESH PUBLICATION;
ERROR:  ALTER SUBSCRIPTION ... REFRESH with copy_data is not allowed when two_phase is enabled
HINT:  Use ALTER SUBSCRIPTION ... REFRESH with copy_data = false, or use DROP/CREATE SUBSCRIPTION.
```

If you enable `two_phase`, adding tables later means loading them manually and
using `copy_data = false`.

### Skipping a poisoned transaction

When the apply worker hits an error it retries (default every 5 s,
`wal_retrieve_retry_interval`) and
`pg_stat_subscription_stats.apply_error_count` climbs. The log gives the exact
LSN to skip. Reproduced on 18.6 by inserting `id=2` locally, then on the
publisher:

```
ERROR:  conflict detected on relation "public.a": conflict=insert_exists
DETAIL:  Key already exists in unique index "a_pkey", modified in transaction 766.
CONTEXT: processing remote data for replication origin "pg_16400" during message type "INSERT"
         for replication target relation "public.a" in transaction 758, finished at 0/17AB8C8
```

```sql
ALTER SUBSCRIPTION s SKIP (lsn = '0/17AB8C8');
-- LOG: logical replication starts skipping transaction at LSN 0/17AB8C8
-- LOG: logical replication completed skipping transaction at LSN 0/17AB8C8
```

After skipping, `subskiplsn` returns to `0/0`. `SKIP` throws away the **whole**
remote transaction, so the tables diverge: use it only when you have decided
the transaction's effects are not needed (or you applied them by hand).
Prefer fixing the data so the retry succeeds ([topic 12](12-conflicts-and-error-handling.md)).

## Moving a table between subscriptions without re-copying (split and merge)

Use case: one busy table (`t3`) slows the single apply worker of a 10-table subscription.
You want to move it to its own `p2`/`s2`, or later merge it back, without copying it again
and without stopping writers. Both procedures below were verified with writers running
throughout. The data matched by checksum and no conflicts were raised.

### The rule that makes it work

Decoding evaluates publication membership as of each transaction's commit. If **one**
publisher transaction moves `t3` from `p1` to `p2`, its commit LSN `X` is an exact switch
point. Changes committed before `X` go to the old slot, changes after `X` go to the new one.
Nothing is lost or doubled, provided that:

1. **The receiving slot exists before `X`.** A slot sees WAL only from its creation point.
   This is the step people miss: creating the subscription (and its slot) after the switch
   lost rows silently. Copying a slot (`pg_copy_logical_replication_slot`) is not needed.
2. **The receiving subscription already tracks `t3`** (`pg_subscription_rel` state `r`)
   when changes arrive. The apply worker silently ignores changes for tables it doesn't track.
3. **The two apply workers never handle `t3` at the same time.** The new one waits until
   the old one has applied up to `X`. Otherwise a post-`X` `UPDATE` could arrive before the
   pre-`X` `INSERT` it depends on.

### Split: move `t3` from `p1`/`s` to a new `p2`/`s2`

```sql
-- publisher: empty publication + the new slot, created BEFORE the switch
CREATE PUBLICATION p2;
SELECT pg_create_logical_replication_slot('s2', 'pgoutput');

-- publisher: the switch, in ONE transaction
BEGIN;
ALTER PUBLICATION p1 DROP TABLE t3;
ALTER PUBLICATION p2 ADD TABLE t3;
COMMIT;
SELECT pg_current_wal_lsn();            -- X

-- subscriber: attach to the existing slot; t3 is registered as 'r' (it is in p2 now)
CREATE SUBSCRIPTION s2 CONNECTION '…' PUBLICATION p2
  WITH (create_slot = false, slot_name = 's2', copy_data = false, enabled = false);

-- publisher: wait until the OLD subscription has applied up to X
SELECT replay_lsn >= 'X' FROM pg_stat_replication WHERE application_name = 's';

-- subscriber
ALTER SUBSCRIPTION s  REFRESH PUBLICATION WITH (copy_data = false);   -- s stops tracking t3
ALTER SUBSCRIPTION s2 ENABLE;                                         -- s2 streams t3 from X
```

After the split, a transaction that touches `t3` and another table reaches the subscriber
through two independent streams ([topic 13](13-limitations.md) §6).

### Merge: move `t3` from `p2`/`s2` back into `p1`/`s`

The receiving slot `s` already exists, so condition 1 holds. But `s` can only start tracking
`t3` through `REFRESH PUBLICATION`, which needs `t3` to be in `p1` already, and adding it
plainly would send its changes down both streams. The answer is to add it first with a **row
filter that matches nothing**, as a placeholder:

```sql
-- publisher: t3 joins p1, but no row passes the filter yet
ALTER PUBLICATION p1 ADD TABLE t3 WHERE (false);
-- subscriber: s now tracks t3 ('r') without copying anything
ALTER SUBSCRIPTION s REFRESH PUBLICATION WITH (copy_data = false);

-- publisher: the switch, in ONE transaction
BEGIN;
ALTER PUBLICATION p2 DROP TABLE t3;
ALTER PUBLICATION p1 DROP TABLE t3;      -- drop the placeholder …
ALTER PUBLICATION p1 ADD  TABLE t3;      -- … and re-add it unfiltered
COMMIT;
SELECT pg_current_wal_lsn();             -- X

-- wait until s2 has applied up to X (replay_lsn of application_name 's2'), then
ALTER SUBSCRIPTION s2 REFRESH PUBLICATION WITH (copy_data = false);   -- s2 stops tracking t3
-- once s2 carries nothing: DROP SUBSCRIPTION s2 (drops its slot); DROP PUBLICATION p2
```

The placeholder filter is needed only when the receiving subscription already exists.
For a split into a new subscription, `CREATE SUBSCRIPTION` registers the table itself.
To merge every table of `s2`, include them all in the placeholder step and in the single
switch transaction.

## Dropping a subscription — mind the slot

```sql
DROP SUBSCRIPTION s;
```

- Normal case: the command connects to the publisher and **drops the slot**
  (`NOTICE: dropped replication slot "s" on publisher`).
- It must be **disabled first** if you want to detach from the slot
  (`ALTER SUBSCRIPTION s DISABLE; ALTER SUBSCRIPTION s SET (slot_name = NONE);`)
  and then the slot, if it still exists, must be dropped by hand on the
  publisher — otherwise it keeps pinning WAL forever
  (`SELECT pg_drop_replication_slot('s')`).
- If the publisher is gone and you do not detach, `DROP` fails trying to reach it.
- Dropping the *database* on the subscriber does not drop remote slots.

## Security model

- The connecting role needs `LOGIN` + `REPLICATION` (or superuser) and `SELECT`
  on the published tables (needed by the initial copy). For `pg_hba.conf`:
  logical replication connects to a *normal database* (`dbname=` in the
  conninfo) using the replication protocol, so the matching line is an
  ordinary `host <dbname> <role> <subscriber-ip>/32 scram-sha-256` entry. The
  special `replication` database keyword only matches *physical* replication
  connections (standbys, `pg_basebackup`).
- Creating a subscription requires superuser **or** membership in
  `pg_create_subscription` plus `CREATE` on the database. A non-superuser owner
  must use a password (`password_required=true`).
- The apply worker runs, by default, with the privileges of the **table
  owner** (`run_as_owner=false`), switching role per table. This protects
  against a subscription owner who could otherwise plant triggers/functions
  that run with the owner's rights. Set `run_as_owner=true` only when the
  owner is trusted *and* the table owners lack rights the subscription needs.
- Triggers on the subscriber table do **not** fire for replicated rows by
  default (`ENABLE REPLICA TRIGGER` / `ENABLE ALWAYS TRIGGER` change that).

## Creating the slot yourself (`create_slot=false`)

Useful when the user running `CREATE SUBSCRIPTION` cannot create slots, when
you need the slot's snapshot for a manual dump, or for `pg_createsubscriber`:

```sql
-- publisher
SELECT pg_create_logical_replication_slot('s', 'pgoutput');
-- subscriber
CREATE SUBSCRIPTION s CONNECTION '…' PUBLICATION p
  WITH (create_slot = false, slot_name = 's', copy_data = false);
```

## Checklist: what a subscription needs from the subscriber side

- Tables must **already exist** with compatible column names/types (columns are
  matched **by name**, order does not matter, subscriber may have extra
  columns that are nullable/defaulted, and types need only be castable from
  text/binary).
- The same schema-qualified name unless you use `publish_via_partition_root`.
- Constraints, indexes, triggers on the subscriber are enforced as for any
  local write, so a subscriber-only `NOT NULL`/`UNIQUE` can make the apply
  worker fail.
- For UPDATE/DELETE the subscriber needs a usable replica-identity index (see
  [topic 09](09-replica-identity.md)).
