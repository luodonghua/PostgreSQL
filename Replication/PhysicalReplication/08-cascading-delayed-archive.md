# 08 — Cascading Replication, Delayed Standbys, WAL Archiving and PITR

Level: L300. Tested on PostgreSQL 18.6; each section below reports what was executed.
Use these to extend the basic primary→standby topology from [02](02-standby-setup-guide.md).

## 1. WAL archiving as a safety net

Streaming replication needs the WAL to still exist on the primary. An **archive** keeps
every segment, so a standby (or a restore) can fetch WAL that the primary already recycled.

Primary:

```
archive_mode = on
archive_command = 'cp %p /archive/%f'          # real systems: pgBackRest/WAL-G/aws s3 cp; must return 0 only on success
```

Standby:

```
restore_command = 'cp /archive/%f %p'
```

### Tested: archive rescues a standby that fell behind

This is the exact scenario that **failed** in [03](03-replication-slots-and-wal-retention.md) (scenario A:
`requested WAL segment … has already been removed`), now with archiving:

```
primary pg_wal segments: 3     archived: 10      (pg_stat_archiver: archived_count 11, failed_count 0)
standby log:
  LOG: restored log file "000000010000000000000002" from archive
  …
  LOG: started streaming WAL from primary at 0/B000000 on timeline 1
standby caught up: primary rows 240000, standby rows 240000
```

The standby first pulled everything it was missing from the archive (`restore_command`), then switched to streaming
once it reached WAL the primary still had. That's the standard recovery order:

```
restore_command (archive)  →  streaming from primary  →  (if the stream drops) back to archive …
```

### `archive_command` rules

- Return **non-zero on any failure**; the segment is retried and **stays in `pg_wal`** meanwhile — a broken
  `archive_command` slowly fills the primary's WAL disk. Monitor `pg_stat_archiver.failed_count` and `last_archived_time`.
- Never overwrite an existing archived file with different content; use an atomic copy (`cp` to temp + rename, or a real tool).
- `archive_mode = always` makes standbys archive too (cascading/standby archiving); default `on` archives only on the primary.
- `archive_timeout` forces a segment switch to bound RPO for the archive on quiet systems (it does not affect streaming).
- Keep the archive in a different failure domain from the primary's disk.
- Back up the **base backup + archive** together; test restores.

## 2. Point-in-time recovery (PITR)

Restore a base backup and replay archived WAL up to a chosen point. Tested:

```bash
pg_basebackup … -D pitr -X stream            # no -R: this is a recovery copy, not a standby
# note the target, e.g. recovery_target_lsn = '0/5000000'
# (the table had 100 rows; afterwards 50 more rows were inserted and the table was DROPPED)
cat >> pitr/postgresql.conf <<EOF
restore_command = 'cp /archive/%f %p'
recovery_target_lsn = '0/5000000'
recovery_target_action = 'promote'
EOF
touch pitr/recovery.signal                   # recovery.signal = PITR; standby.signal = continuous standby
pg_ctl -D pitr start
```

Log and result:

```
LOG: recovery stopping after WAL location (LSN) "0/5000028"
LOG: redo done at 0/5000028
LOG: selected new timeline ID: 2
table t rows=100 | min(v)=before          <- the dropped table is back, without the later inserts
```

| Target option | Meaning |
|---|---|
| `recovery_target_time` | Replay to a timestamp (typical: just before the bad `DROP`) |
| `recovery_target_lsn` | Exact WAL position |
| `recovery_target_xid` | Up to a transaction id |
| `recovery_target_name` | A restore point from `pg_create_restore_point('name')` |
| `recovery_target = 'immediate'` | Stop as soon as the backup is consistent |
| `recovery_target_inclusive` | Stop after (default `on`) or before the target |
| `recovery_target_action` | `pause` (default), `promote`, `shutdown` |
| `recovery_target_timeline` | `latest` (default) / `current` / explicit |

Gotchas: recovery stops at the **first** point that satisfies the target; after promotion a **new timeline** is created, so
a second PITR must name the right timeline; the archive must contain *every* segment from the base backup's start to the target.

## 3. Cascading replication

A standby can feed another standby: `standby2` connects to `standby1` instead of the primary. Use it to cut the
primary's walsender/network load (many replicas, cross-region hop) or to isolate reporting replicas.

Setup used (via `plab_add_standby2` in [lab.sh](lab.sh)):

```bash
# standby1 must allow replication connections in pg_hba.conf and has max_wal_senders > 0 (copied from the primary)
pg_basebackup -h standby1 -p 5435 -U repl -D standby2 -R -X stream
```

Result:

```
primary:   1 standby in pg_stat_replication (standby1 only)
standby1:  1 downstream in pg_stat_replication   (application_name walreceiver, state streaming, 0 bytes behind)
standby2:  pg_stat_wal_receiver → sender_port 5435, status streaming ; data present
```

Facts:

- A cascading standby sends WAL downstream as it has **received/flushed** it, so downstream lag is at least the
  upstream lag. (From the walsender design, cascading senders send flushed WAL without waiting for replay, so replay
  conflicts on the middle node should mainly affect that node's own queries — I did not test this.)
- Slots live on the node you connect to: `primary_slot_name` on standby2 names a slot **on standby1**
  (create it there; the docs allow creating physical slots on a standby — I did not test this).
- `hot_standby_feedback` propagates up the chain (standby2 → standby1 → primary).
- If the middle standby is promoted, the downstream follows the new timeline automatically.
- Synchronous replication is only for direct standbys of the primary; a cascaded standby cannot be synchronous.
- Failure of the middle node orphans the downstream (it can fall back to `restore_command` or you re-point it).

## 4. Delayed standbys

```
recovery_min_apply_delay = '1h'
```

The standby **receives and flushes WAL immediately** but delays *applying* each commit record until its commit
timestamp + the delay. Tested with `6s`:

```
row visible on delayed standby after 6.1 s
received_immediately = t      (flush_lsn = pg_current_wal_lsn())      replay_lag = 00:00:01.4
```

Purposes: undo human error (e.g. a `DROP TABLE` or bad `DELETE`) within the delay window — you can pause replay
(`pg_wal_replay_pause()`), query the old state, or `recovery_target_*` + replay up to just before the mistake.
Not a backup: it is only as good as the delay and it consumes WAL disk (slot or archive needed for the window).

Cautions:

- It delays acknowledgements only for `synchronous_commit = remote_apply`. For `on` the standby acknowledges at **flush**,
  which still happens immediately (by reasoning from the acknowledgement stages, not tested); a `remote_apply` commit against a delayed standby would
  wait for the full delay, so don't put a delayed standby in `synchronous_standby_names`.
- With `hot_standby_feedback` it will hold back vacuum on the primary for the delay window — keep feedback off on delayed standbys.
- Promotion of a delayed standby first needs the backlog replayed unless you `pg_wal_replay_resume()` + skip via a `recovery_target`.
- A long delay with a **slot** retains at least that much WAL on its upstream; size disk for `delay × WAL rate`.

## 5. Streaming WAL to storage: `pg_receivewal`

`pg_receivewal` is a walreceiver that writes WAL to a directory instead of replaying it: a "streaming archive" with
near-zero RPO (vs. `archive_command`, which ships a finished 16 MB segment).

```bash
pg_receivewal -h primary -U repl -D /walarchive --slot=rw1 --create-slot
pg_receivewal -h primary -U repl -D /walarchive --slot=rw1 --synchronous     # also flush as received (for sync replication)
```

Tested: the directory held `000000010000000000000006.partial` (the in-progress segment, finished and renamed when complete)
and the slot `rw1` showed `active = f` after stopping, with a non-NULL `restart_lsn` — the slot keeps pinning WAL
while the tool is down, like any other ([03](03-replication-slots-and-wal-retention.md)). Use `--synchronous` and list its
application_name in `synchronous_standby_names` only if you really want commits to wait for it.

## 6. Putting the options together

| Goal | Build |
|---|---|
| Typical HA | 1–2 streaming standbys, slot + `max_slot_wal_keep_size`, archive as fallback |
| Many read replicas / remote region | Standbys cascade from a regional hub standby |
| Protection from human error | Delayed standby **and** PITR-capable backups |
| Near-zero RPO archive | `pg_receivewal --slot --synchronous` to durable storage |
| Cheaper recovery from big outages | Base backups + archive (pgBackRest/Barman/WAL-G), tested restores |

## Notes on the experiments

- All run locally over loopback (single machine). Archive is a local directory standing in for object storage.
- Items explicitly flagged "by reasoning" or "I did not test" above are not verified on 18.6.
