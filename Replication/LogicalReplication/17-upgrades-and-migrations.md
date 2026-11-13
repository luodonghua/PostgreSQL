# 17 — Upgrades, Migrations and Bidirectional Setups

Level: L400. **Tested on PostgreSQL 18.6**: `pg_createsubscriber`, `pg_upgrade`
slot/subscription preservation, bidirectional `origin` behaviour. The only server
version I had locally was 18, so the `pg_upgrade` run is a same-major run: it
proves the mechanism (slot and subscription state carried over), not a version jump.

## Which tool for which job

| Goal | Tool | Min. versions | Downtime |
|---|---|---|---|
| Major-version upgrade, minimal downtime | Logical replication to a new-version cluster | publisher ≥ 10 | seconds–minutes (cut-over) |
| Same, but huge data: skip the initial copy | Physical standby → `pg_createsubscriber` → upgrade the subscriber | 17+ | seconds–minutes |
| In-place upgrade that keeps existing logical consumers working | `pg_upgrade` | **old cluster ≥ 17** to keep slots/subscription state | minutes (offline) |
| Move to another host/cloud/provider | Logical replication | ≥ 10 | seconds–minutes |
| Change table layout (partition, rename schema) | Logical replication with `publish_via_partition_root` | ≥ 13 | cut-over only |
| Rollback safety net | Reverse logical replication | ≥ 16 (`origin = none`) | — |

## Recipe 1 — Zero-downtime major upgrade with logical replication

```
Old cluster (v N)  ──logical replication──►  New cluster (v N+k)
   writes continue            catch up           cut-over: stop writes, wait for lag 0, switch app
```

1. **Prepare the new cluster**: install the new version, same extensions, same
   collation/encoding settings (collation differences break indexes).
2. **Pre-checks on the old cluster**: every table has a PK/identity; list
   sequences; `wal_level = logical`; enough `max_replication_slots`/senders;
   long-running transactions are known ([topic 06](06-logical-decoding.md)).
3. **Copy the schema only**: `pg_dump --schema-only --no-publications --no-subscriptions`
   from old → new, using the **new** version's `pg_dump` if possible. Create roles first
   (`pg_dumpall --roles-only`).
4. **Create the publication** on old (`FOR ALL TABLES` is convenient — but remember
   new tables created during the migration will break the stream until they exist on the
   target).
5. **Create the subscription** on new; watch `pg_subscription_rel` reach `r`
   everywhere ([topic 10](10-initial-sync-tablesync.md)).
6. **Run in parallel for a while**: validate row counts/checksums, run read traffic and
   query-plan checks on the new cluster. Run `ANALYZE` on the new cluster (statistics are
   **not** replicated).
7. **Freeze DDL** from here on.
8. **Cut-over**:
   1. Stop writers on old (revoke connect / pause app / `ALTER DATABASE … SET default_transaction_read_only`).
   2. Wait until the slot is fully consumed: `confirmed_flush_lsn = pg_current_wal_lsn()` on old.
   3. **Sync sequences** (they are not replicated before 19):

      ```sql
      -- old: run as the sequences' owner or a role with SELECT/USAGE on them (see below)
      SELECT format('SELECT setval(%L, %s);',
                    quote_ident(schemaname) || '.' || quote_ident(sequencename),
                    last_value)
      FROM pg_sequences WHERE last_value IS NOT NULL;
      -- run the output on new (add a safety margin if you can't fully quiesce)
      ```

      This is correct for **any `CACHE` size**, not only `CACHE 1`. `pg_sequences.last_value`
      is the highest value *allocated* to any session's cache. That is ≥ every value
      actually handed out. With `CACHE 50` it read 50 after a session had used only 1–3.
      So a cache leaves a gap on the new side, never a duplicate, provided no session on
      *old* keeps using its cached values. Watch for:
      - **Unreadable sequences are skipped.** `last_value` is NULL for sequences the role
        can't read (and for never-used ones), so `WHERE last_value IS NOT NULL` silently
        skips them. Run it as owner or admin, and compare with `SELECT count(*) FROM pg_sequences`.
      - **Quoting.** Use `quote_ident`. Without it, `"MySeq"` becomes `setval('public.MySeq', …)`,
        which fails with `relation "public.myseq" does not exist`.
      - **Descending sequences** (`increment < 0`): apply the safety margin downwards.
   4. `DROP SUBSCRIPTION` on new (drops the slot on old).
   5. Point the app at new. Re-enable writers.
9. **Rollback plan**: before step 8.5 set up the reverse stream (below) so old
   stays current.

Things that silently differ after a logical migration: statistics, sequence
state, permissions on roles that weren't recreated, extension-owned objects,
unlogged tables (empty), large objects, event triggers, and `pg_stat_*` history.

## Recipe 2 — Skip the initial copy with `pg_createsubscriber` (PG17+)

For multi-TB databases, copying every table through `COPY` is slow. Instead clone
physically (fast, parallel, file-level) and **convert the standby into a logical
subscriber in place**.

Tested on 18.6 (publisher `5433`, standby on `5435`, 1000 rows):

```bash
# standby is a normal physical standby in sync with the primary (pg_basebackup -R), then:
pg_ctl -D standby stop

pg_createsubscriber -D standby \
   -P "host=primary port=5433 user=repl dbname=postgres" \
   -d postgres --publication=pub_all --subscription=sub_all \
   -U repl -p 5435 -s /tmp/lr-lab --verbose
```

What it printed (condensed): checks system ids and settings on both servers →
starts the standby → **creates publication `pub_all` and slot `sub_all` on
the primary** → waits for the standby to reach a consistent point → drops the
copied publication on the target → **creates subscription `sub_all`**, sets the
**replication origin progress** to the slot's LSN → enables it → stops the
server → **rewrites the system identifier** with `pg_resetwal`. Afterwards:

```
in_recovery=false          subscription sub_all, enabled
rows: 1000                 live insert on primary → 1001 on the new subscriber
primary:  sub_all | logical | active = t ;   pub_all (puballtables = t)
```

The converted node is now an independent, writable database receiving logical
changes from the primary with **no copy phase**. Notes:

- The standby and the primary are the **same major version** — this
  tool does not upgrade. Combine it with `pg_upgrade` (on the converted node) or
  use it to build a same-version logical replica quickly.
- It requires: `wal_level = logical` on the primary; enough `max_replication_slots`
  (a few extra), `max_logical_replication_workers`, `max_wal_senders`; a role with
  replication/superuser privileges on both; the target must be stopped and cleanly
  caught up (it will start it itself).
- Failure after the "consistent state" hint means you must re-create the standby.
- It creates one publication (`FOR ALL TABLES`) and one subscription per
  database given with `-d`.
- `--dry-run` to preview. Use `--publication/--subscription/--replslot` to name objects.

## Recipe 3 — In-place `pg_upgrade` that keeps logical replication

From PG17 `pg_upgrade` carries across:

- **Logical slots on the publisher** (the old cluster must be 17+, and all
  changes must already be consumed by the subscriber — "valid logical replication slots"
  check).
- **Subscription state on the subscriber** (`pg_subscription_rel` states and origin
  LSNs), so a subscriber upgrade doesn't need a re-copy.

Tested sequence on 18.6 (publisher with one subscription): disable the
subscription, stop the publisher cleanly, `pg_upgrade -b … -B … -d old -D new`,
output:

```
Checking for valid logical replication slots                  ok
Checking for subscription state                               ok
Checking for new cluster logical replication slots            ok
Restoring logical replication slots in the new cluster        ok
Upgrade Complete
```

New publisher: slot `s | pgoutput | active = f | confirmed_flush_lsn = 0/80001D0`,
publication `p` and data intact. Re-enabling the subscription and inserting a row
made it arrive (`1x,2after-upgrade`) — **no re-copy, no gap**.

Requirements and constraints:

- New cluster: `wal_level = logical`, enough `max_replication_slots`.
- Run **only after the subscriber has caught up**; otherwise pg_upgrade refuses
  (unconsumed WAL for the slot would be lost).
- Disable the subscriptions (or stop subscribers) during the upgrade to avoid new
  changes.
- Upgrading from < 17 does **not** preserve slots: drop the subscription, upgrade,
  recreate with `copy_data = false` after verifying data equality, or use recipe 1.

## Reverse replication (rollback safety net) and bidirectional setups

After a cut-over you can keep the old cluster current by subscribing it to the new one,
using `origin = none` to avoid echoing changes back:

```sql
-- on OLD (now the follower):
CREATE SUBSCRIPTION rollback_sub CONNECTION '…new…' PUBLICATION p
  WITH (origin = none, copy_data = false);
```

### Tested: `origin = none` vs `origin = any`

Two nodes A (`5433`) and B (`5434`), each publishes `t` and subscribes to the other,
`copy_data = false`.

| `origin` | Result |
|---|---|
| `none` | A inserted id=1, B inserted id=2: both ended with `1A,2B`. An update on A (`A2`) reached B once. No ping-pong, no errors. |
| `any` | A inserted id=1 → B applied it → B's own publication sent it **back** to A → `ERROR: conflict=insert_exists` on A (two errors in 4 s, `apply_error_count` rising). Rows converge on a stalled stream. |

`origin = none` makes the publisher skip changes that carry a replication origin
(i.e., ones that were applied by another subscription), so only locally originated changes
propagate. The stream marks such transactions with an Origin (`O`) message ([topic 08](08-pgoutput-protocol.md)).

Rules for bidirectional:

1. `origin = none` on **both** subscriptions, `copy_data = false` (or the
   server warns that initial copy might copy replicated data).
2. Disjoint writes: each row has a single "home" node (key ranges, per-site UUID
   prefix, `site_id` in the PK).
3. Independent sequences: ranges (`INCREMENT BY 2 START WITH 1/2`) or UUIDs.
4. Conflicts are *detected* but not resolved ([topic 12](12-conflicts-and-error-handling.md)):
   `update_origin_differs` will happen if both sides write the same row, and
   the last applier wins on each side → **permanent divergence**.
5. Schema changes must be coordinated on both.
6. Three or more nodes: every node needs a subscription to every other node (with
   `origin = none`); transitive forwarding does not exist with `origin = none`.
   This is a real multi-master architecture, not a supported turnkey product;
   consider specialised extensions if you need more.

## Migration patterns

| Scenario | Notes |
|---|---|
| **On-prem → AWS RDS/Aurora** | Subscriber is RDS; needs network path, `rds.logical_replication` on the publisher side if RDS is the source; see [topic 20](20-amazon-rds-and-aurora.md) |
| **RDS → self-managed** | RDS as publisher: `rds.logical_replication = 1` + reboot; the replication role needs `rds_replication` |
| **Consolidate N databases into one** | N publications → N subscriptions into distinct schemas/tables (same name per target schema) |
| **Split a database** | Publications by table subset → separate targets |
| **Partition a big table online** | Target is the partitioned table; `publish_via_partition_root` isn't needed when only the *target* is partitioned (subscriber can be partitioned freely); use it when the *source* is partitioned and the target is not |
| **Change PK type / data layout** | Subscriber table with different compatible types (widening) works ([topic 13](13-limitations.md)) |
| **Blue/green with partial cut-over** | One subscription per tenant group; cut-over group by group |

## Cut-over verification checklist

- [ ] Lag zero: `confirmed_flush_lsn = pg_current_wal_lsn()` after writes stopped.
- [ ] Row counts and checksums per table.
- [ ] Sequences set (+ margin).
- [ ] `ANALYZE` done on the new cluster; `pg_stat_statements` baseline compared.
- [ ] All indexes/constraints/triggers/grants present (diff `pg_dump --schema-only`).
- [ ] Extensions, collations, `postgresql.conf` differences reviewed.
- [ ] Roles and passwords/auth config equal.
- [ ] Replication objects cleaned up on the old side (slot dropped!) or kept as rollback.
- [ ] Monitoring and backups pointed at the new cluster.

## ⚠️ Non-GA

- 19 adds sequence replication/sync, which would remove step 8.3 for those
  cases; 19 source also adds `retain_dead_tuples` for better conflict detection in
  bidirectional use. Not tested here; see the [README policy](README.md#version-policy-read-this-first).
