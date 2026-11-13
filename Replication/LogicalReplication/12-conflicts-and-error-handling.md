# 12 — Conflicts and Error Handling

Level: L300. Tested on PostgreSQL 18.6 (every conflict type below was
reproduced). Non-GA items are marked ⚠️. Source: `replication/logical/conflict.c`.

## Mental model

Logical replication assumes the subscriber's tables only change through
replication. When something else wrote to them — a local application, a
second publisher, a half-finished manual fix — the incoming change may not
match the local row. PostgreSQL (through 18) **detects and reports** most such
situations but has **no automatic resolution policy**: it either applies the
remote change anyway, skips it, or stops with an error.

## Conflict types (18.6)

Setup: table `c(id int primary key, u int unique, v text)`, subscriber with
`track_commit_timestamp = on` (needed only for the two `*_origin_differs` types).

| Conflict | Meaning | Severity | What the worker does |
|---|---|---|---|
| `insert_exists` | INSERT violates a unique index on the subscriber | **ERROR** | Stops; retries forever (or until `disable_on_error`) |
| `update_exists` | UPDATE produces a value that violates a unique index | **ERROR** | Same |
| `multiple_unique_conflicts` | The change violates **more than one** unique index | **ERROR** | Same |
| `update_missing` | Row to update not found | LOG | **Skips** that update and continues |
| `delete_missing` | Row to delete not found | LOG | **Skips** and continues |
| `update_origin_differs` | Row was last modified by a *different origin* (e.g. locally) | LOG | **Applies** the remote update (remote wins) |
| `delete_origin_differs` | Same for DELETE | LOG | **Applies** the delete |
| ⚠️ `update_deleted` (19 source) | Row to update was deleted locally and a tombstone is still known | LOG | Needs `retain_dead_tuples`; see below |

So only unique-key violations stall replication. The "missing" and "origin
differs" cases are *silent divergence*: a log line, a counter, and rows that
no longer match.

### Real log output (18.6)

```
LOG:  conflict detected on relation "public.c": conflict=update_missing
DETAIL:  Could not find the row to be updated.
         Remote row (1, 1, A); replica identity (id)=(1).

LOG:  conflict detected on relation "public.c": conflict=delete_missing
DETAIL:  Could not find the row to be deleted.

LOG:  conflict detected on relation "public.c": conflict=update_origin_differs
DETAIL:  Updating the row that was modified locally in transaction 761 at 2026-11-07 19:00:09.563604+08.
         Existing local row (3, 3, local); remote row (3, 3, remote); replica identity (id)=(3).

ERROR:  conflict detected on relation "public.c": conflict=update_exists
DETAIL:  Key already exists in unique index "c_u_key", modified locally in transaction 765 at 2026-11-07 19:00:12.224763+08.
```

The `update_origin_differs` case: the subscriber had changed row 3 locally to
`local`; the remote update to `remote` simply overwrote it (final row
`3 | 3 | remote`). The local change was lost, with only the log line as evidence.

The "…modified locally in transaction N at T" part needs
`track_commit_timestamp = on` (restart); without it the DETAIL is shorter and
`*_origin_differs` conflicts can't be detected at all.

### Counters

```sql
SELECT subname, apply_error_count, sync_error_count,
       confl_insert_exists, confl_update_origin_differs, confl_update_exists,
       confl_update_missing, confl_delete_origin_differs, confl_delete_missing,
       confl_multiple_unique_conflicts
FROM pg_stat_subscription_stats;
 s | 2 | 0 | 0 | 1 | 2 | 1 | 0 | 1 | 0       (my test run)
```

`update_exists = 2` although I caused it once: **each retry increments the
counter**. A growing `apply_error_count` with a flat `confl_*` total points to
non-conflict errors (missing column, permission, constraint, etc.).

Alert on increases of any `confl_*` (they mean divergence), and on
`apply_error_count`.

## Behaviour on ERROR: the retry loop

An error aborts the remote transaction on the subscriber (it is rolled back
entirely), the worker exits, and the launcher restarts it after
`wal_retrieve_retry_interval` (5 s). It re-receives the **same** transaction
and fails again. While it loops:

- `confirmed_flush_lsn` does not move, the slot retains WAL (topic 05);
- **all later transactions of the subscription wait** behind it (commit order);
- logs fill with the same error every 5 s.

### `disable_on_error`

```sql
CREATE SUBSCRIPTION s … WITH (disable_on_error = true);
```

Tested: after a unique violation the subscription went to
`subenabled = f`, the worker stopped, the slot became inactive and
retained only **464 bytes** (nothing else was happening). Row `(2,'after')`
behind the poisoned transaction was **not** applied until recovery.
It stops the log spam and the CPU churn, but the slot keeps accumulating WAL
while disabled, so alert on it.

## Ways out of a stalled subscription

| Option | When to use | How | Risk |
|---|---|---|---|
| **A. Fix the data, let it retry** | Local row is stale/wrong | Delete or correct the conflicting subscriber row; `ENABLE` if disabled | None; loses nothing. Tested: after `DELETE FROM c WHERE id=1` and `ALTER SUBSCRIPTION s ENABLE`, the remote row `(1,'remote')` and the following `(2,'after')` both arrived |
| **B. `ALTER SUBSCRIPTION … SKIP (lsn = …)`** | The remote transaction should be discarded | Take the LSN from the error CONTEXT (`finished at 0/…`). PG15 required superuser; from PG16 the **subscription owner** may run it (the PG15 `must be superuser to skip transaction` check is gone from `subscriptioncmds.c` on 16+). Works on RDS/Aurora, see below | Whole remote transaction is dropped → permanent divergence. See [topic 03](03-subscriptions.md) |
| **C. `pg_replication_origin_advance`** | Skip several transactions / older versions | `SELECT pg_replication_origin_advance('pg_<subid>', '0/…')` after disabling. In community PostgreSQL the origin functions are executable only by superuser by default (`proacl => '{POSTGRES=X}'` in `pg_proc.dat`) | Easy to overshoot; manual |
| **D. Drop & recreate subscription** | Divergence too large to patch | New subscription with `copy_data` after truncating | Full re-copy |

Always find *why* it conflicted before skipping (a second writer? a
half-done migration?).

### On Amazon RDS / Aurora PostgreSQL (no superuser)

Tested on RDS for PostgreSQL 18.6 as the master user (`rolsuper = f`, member of
`rds_superuser`, `rds_replication` and `pg_create_subscription`), on a subscription it owns:

| Command | Result |
|---|---|
| `ALTER SUBSCRIPTION s2 SKIP (lsn = '0/1000000')` | Succeeded; `pg_subscription.subskiplsn = 0/1000000` |
| `ALTER SUBSCRIPTION s2 SKIP (lsn = NONE)` | Clears it (`NONE` is a keyword value of `lsn`; `SKIP (NONE)` is a syntax error) |
| `pg_replication_origin_advance('pg_<subid>', '0/2000000')` | Succeeded; RDS grants the origin functions to the admin role |
| `pg_replication_origin_create` / `_session_setup` | Succeeded |

So options B and C both work on RDS. Aurora PostgreSQL uses the same `rds_superuser` model;
I did not repeat the test there. SKIP only works for the **owner** of the subscription, so a
subscription created by another role needs `ALTER SUBSCRIPTION … OWNER TO` first, or must be
run as that role.

## How to avoid conflicts (design, not tooling)

1. **Single writer rule.** Treat subscriber tables as read-only (`REVOKE` write
   privileges from application roles, or set the database/transactions
   read-only for them). Most conflicts disappear.
2. **Bidirectional / multi-writer setups** (`origin = none`): partition
   the key space by site (ids from disjoint ranges or UUIDv7 per node) so two sides
   never touch the same row. Unique constraints on non-key columns are the most
   common source of `*_exists` conflicts.
3. **Use UUIDs / site-prefixed sequences**, never independent `serial`s.
4. **Don't add subscriber-only unique constraints.**
5. **Schema in lock-step** ([topic 04](04-step-by-step-setup-guide.md) §9.1).
6. **Backfills on the subscriber** go in separate tables, not the replicated ones.
7. Turn on `track_commit_timestamp` if you run any local writes at all,
   otherwise `origin_differs` is invisible.

## Last-update-wins? Not built in (through 18)

There is no resolver option on GA releases. If you need LWW:

- Add `updated_at timestamptz` and a `BEFORE UPDATE` trigger on the subscriber
  declared `ENABLE REPLICA TRIGGER` that keeps the row with the newer
  timestamp (and returns NULL to skip the change). This runs for replicated rows
  only.
- Or use an extension/third-party product designed for multi-master.

## ⚠️ Non-GA: where this is heading

- **19 source:** `retain_dead_tuples` / `max_retention_duration`
  (`CREATE SUBSCRIPTION … WITH (retain_dead_tuples = true)`) make the
  subscriber's vacuum keep dead rows long enough to tell "never existed" from
  "was deleted locally", enabling the `update_deleted` conflict type.
- **20devel master only (2026-07):** `conflict_log_destination`
  (`log` / `table` / `all`) records conflict details in a table in
  addition to the server log, making conflicts queryable.
- Still no automatic resolution policies in the code I read. Interfaces and
  names of these features may change before/after release.

## Non-conflict errors you will meet

| Error text (abbreviated) | Cause | Fix |
|---|---|---|
| `logical replication target relation "public.t" is missing replicated column: "x"` | Subscriber lacks a column the publisher sends | Add the column on the subscriber (topic 04 §9.1) |
| `… does not exist` (relation) | Table not created on the subscriber (e.g. new partition) | Create it; refresh |
| `… has incompatible generated column` | Subscriber column is `GENERATED` ([topic 02](02-publications.md)) | Make it ordinary |
| `… has neither REPLICA IDENTITY index nor PRIMARY KEY and published relation does not have REPLICA IDENTITY FULL` | No lookup key on the subscriber | Add PK/identity index ([topic 09](09-replica-identity.md)) |
| `permission denied for table` / `must be able to SET ROLE` | Table owner vs subscription owner mismatch with `run_as_owner = false` | Grant privileges / adjust owner |
| `null value in column … violates not-null constraint` | Subscriber stricter than publisher | Align constraints |
| `could not receive data from WAL stream: … terminating due to timeout` | Network or `wal_sender_timeout`/`wal_receiver_timeout` | Check network, raise timeouts |
