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

### Does a blocked copy of the new table stall the existing tables? (tested)

No. Setup on 18.6: subscription `s` streaming table `a` (state `r`), then a session on the
publisher opened a transaction that holds an xid and stayed idle. Then
`ALTER PUBLICATION p ADD TABLE b` and `ALTER SUBSCRIPTION s REFRESH PUBLICATION`:

```
-- subscriber
a | r
b | d                                    <- tablesync worker started, waiting
-- publisher walsenders
6747 | active | Client | WalSenderWaitForWal | START_REPLICATION SLOT "s" …           <- main apply stream
6766 | active | Lock   | transactionid       | CREATE_REPLICATION_SLOT "pg_16400_sync_16392_…"
```

While `b` waited, three inserts into `a` arrived on the subscriber at once (`count(a)` went
1 → 4). When the open transaction ended, `b` went `d → r` with its pre-existing row.

The details:

- The tablesync worker is a **separate process with its own temporary slot**. Only that
  slot's creation waits, for every transaction that holds an xid when it starts (a slot
  needs a consistent snapshot). The apply worker keeps streaming the tables already in `r`.
- The wait is **instance-wide**, not per schema or per database. A second run had the
  published schema `s1`, an open transaction writing to schema `s2`, and another in a
  **different database**. After the `s2` transaction was terminated, `s1.b` stayed in `d`.
  It moved to `r` only when the other database's transaction ended too.
- **A long block (100 s, longer than the 1 min `wal_sender_timeout` / `wal_receiver_timeout`)**
  was sampled every 13 s while one row per sample was inserted into the already-replicating table:

  ```
  t+14s  s1.a pub/sub 1/1  sync walsender 13541 wait=transactionid 00:00:13  sync worker 13539
  t+53s  s1.a pub/sub 4/4  sync walsender 13541 wait=transactionid 00:00:53  sync worker 13539
  t+67s  s1.a pub/sub 5/5  sync walsender 13541 wait=transactionid 00:01:06  sync worker 13539
  t+93s  s1.a pub/sub 7/7  sync walsender 13541 wait=transactionid 00:01:33  sync worker 13539
  t+106s s1.a pub/sub 8/8  sync walsender none                                sync worker none
  ```

  The same sync worker and walsender PIDs waited for the whole time. Neither timeout fired
  in this run, and there were no errors (`sync_error_count = 0`).
  The existing table kept up at every sample. `b` finished copying a few seconds after the
  blocker ended. Expect the wait to last as long as the longest open xid-holding transaction.
- What it does cost: the blocked worker uses one of the
  `max_sync_workers_per_subscription` slots, so other newly added tables queue behind it in `i`.
  It also uses a replication slot and a walsender on the publisher. `b` gets no changes on the
  subscriber until it is `r`. They are not lost: the copy snapshot is taken after the wait,
  then the catch-up from the temp slot applies the rest.
- Find the blocker on the publisher:
  `SELECT pid, datname, xact_start, backend_xid FROM pg_stat_activity WHERE backend_xid IS NOT NULL ORDER BY xact_start;`

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

Use case: one subscription carries 10 tables and one of them (`t3`) is busy enough to slow
the single apply worker. You want to move it to its own publication and subscription,
`p2`/`s2`, without copying it again and without stopping the application. Later you may
want to merge it back. Both directions were tested on 18.6 with a loop writing to `t3`
the whole time. The writes were `INSERT` + `UPDATE` + `DELETE` for the merge test and
`INSERT`s for the split test, and the writers were never paused. Each run was checked with
`count(*), sum(hashtext(t3::text))` on both sides and with the conflict counters.

### The rule that makes it work

Decoding reads publication membership **as of each change's commit**, through the
historic catalog snapshot. So if one publisher transaction moves the table from `p1` to
`p2`, its commit LSN `X` is an exact switch point: changes committed before `X` go to
`s1`'s slot, and changes after `X` go to `s2`'s slot. No change goes to both or to neither,
on two conditions:

1. **The receiving slot must already exist before `X`.** A slot only sees WAL from its own
   creation point onwards.
2. **The receiving subscription must already have the table in `pg_subscription_rel`
   (state `r`) when the changes arrive.** If not, the apply worker drops them *silently*.

A copied slot (`pg_copy_logical_replication_slot`) is **not** needed. Creating the new slot
ahead of the switch is enough. I did not test the copy-slot variant.

### Split: move `t3` from `p1`/`s` to a new `p2`/`s2`

```sql
-- publisher: empty publication + the new slot, created BEFORE the switch
CREATE PUBLICATION p2;
SELECT pg_create_logical_replication_slot('s2', 'pgoutput');

-- publisher: the switch, in ONE transaction; note its LSN = X
BEGIN;
ALTER PUBLICATION p1 DROP TABLE t3;
ALTER PUBLICATION p2 ADD TABLE t3;
COMMIT;
SELECT pg_current_wal_lsn();            -- X (just after the commit)

-- subscriber: attach to the existing slot; t3 is in p2 now, so it is registered as 'r'
CREATE SUBSCRIPTION s2 CONNECTION '…' PUBLICATION p2
  WITH (create_slot = false, slot_name = 's2', copy_data = false, enabled = false);

-- publisher: wait until the OLD subscription has applied everything up to X
SELECT replay_lsn >= 'X' FROM pg_stat_replication WHERE application_name = 's';

-- subscriber
ALTER SUBSCRIPTION s  REFRESH PUBLICATION WITH (copy_data = false);   -- s forgets t3
ALTER SUBSCRIPTION s2 ENABLE;                                         -- s2 streams t3 from X
```

| Run | Publisher `t3` | Subscriber `t3` | Errors / conflicts |
|---|---|---|---|
| **Pre-created slot** (above) | 1129, `-44335499338` | 1129, `-44335499338` | 0 |
| Naive: `CREATE PUBLICATION p2 FOR TABLE t3` in the switch transaction, then `CREATE SUBSCRIPTION s2 … copy_data = false` (its slot created **after** `X`) | 1141 | **1139**, checksum differs | 0 — the loss is silent |

Why each step is there (the two failure modes below are reasoned from how the apply worker
filters tables; I did not reproduce them):

- **`enabled = false` and the wait for `s` to pass `X`.** These keep the two apply workers
  from touching `t3` at the same time. If `s2` applied an `UPDATE` committed after `X` before
  `s` had applied the `INSERT` from before `X`, you would get an `update_missing` conflict.
- **`REFRESH` on `s` after the wait.** Do it too early and `s` would silently skip `t3`
  changes from before `X` that it has not applied yet.
- **No application downtime.** Writers to `t3` and to the other nine tables ran
  throughout.
- **Cost: cross-table consistency.** After the split, a transaction that touches `t3` and
  `t1` reaches the subscriber through two independent streams ([topic 13](13-limitations.md) §6).

### Merge (reverse): move `t3` from `p2`/`s2` back into `p1`/`s`

Here the receiving slot (`s`) already exists, so condition 1 holds. Condition 2 is the
problem. `s` can only register `t3` with `REFRESH PUBLICATION`, which only sees tables that
are already in `p1`. A plain `ADD TABLE` would send `t3` changes to both `s` and `s2` until
the switch. The way out is a **row filter that matches nothing**, used as a placeholder:

```sql
-- publisher: t3 joins p1, but no row passes the filter yet
ALTER PUBLICATION p1 ADD TABLE t3 WHERE (false);
-- subscriber: s now tracks t3 ('r') without copying anything
ALTER SUBSCRIPTION s REFRESH PUBLICATION WITH (copy_data = false);

-- publisher: the switch, one transaction, LSN = X
BEGIN;
ALTER PUBLICATION p2 DROP TABLE t3;
ALTER PUBLICATION p1 DROP TABLE t3;      -- remove the placeholder filter …
ALTER PUBLICATION p1 ADD  TABLE t3;      -- … and re-add it unfiltered
COMMIT;
SELECT pg_current_wal_lsn();             -- X

-- wait until s2 has applied up to X, then
ALTER SUBSCRIPTION s2 REFRESH PUBLICATION WITH (copy_data = false);   -- s2 forgets t3
-- when s2 carries nothing any more: DROP SUBSCRIPTION s2;  (drops its slot) and DROP PUBLICATION p2
```

Tested with the `INSERT`/`UPDATE`/`DELETE` writer running. The first move into `p2` used the
same placeholder trick. After moving `t3` there and back: publisher `1000 | -64742994327`,
subscriber `1000 | -64742994327`; `apply_error_count`, `confl_insert_exists`,
`confl_update_missing` and `confl_delete_missing` were 0 for both subscriptions; the
subscriber log had no `ERROR`. So **the row filter is only needed when the receiving
subscription already exists** (merge, or a split into an existing subscription). For a
split into a new subscription, `CREATE SUBSCRIPTION` registers `t3` itself, and the
pre-created slot is all you need.

To merge every table of `s2` into `s`, do the same with all of them in the placeholder step
and in the single switch transaction, then drop `s2`.

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
