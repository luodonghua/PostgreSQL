# 09 — Best Practices and Troubleshooting

Level: L400. Consolidates [01–08](README.md). Error texts marked **(tested)** were produced on PostgreSQL
18.6 in the lab; **(docs)** are standard messages I did not reproduce here.

## 1. Best practices

### Topology and durability

1. **At least two standbys** for anything that matters: one to promote, one so that synchronous/quorum replication can survive a
   failure ([04](04-synchronous-replication.md)).
2. Put standbys in **different failure domains** (host, rack, AZ) from the primary and from each other.
3. Choose your **RPO explicitly**: async (small loss window), `remote_write`/`on` (no loss with sync), `remote_apply` (read-your-writes).
   Document what happens when the sync standby disappears ([04](04-synchronous-replication.md)).
4. **Replication is not a backup**: `DROP TABLE`, corruption and bad deploys replicate instantly. Keep base backups + WAL archive
   and test restores ([08](08-cascading-delayed-archive.md)). Add a delayed standby if human error is a concern.
5. Keep a **WAL archive** even if you use slots: it converts "rebuild the standby" into "wait while it catches up" (tested in [08](08-cascading-delayed-archive.md)).

### Configuration

| Area | Recommendation |
|---|---|
| Slots | One slot per standby, `max_slot_wal_keep_size` set to protect the primary's disk, alerts on inactive slots ([03](03-replication-slots-and-wal-retention.md)) |
| Capacity | `max_wal_senders` ≥ standbys + backup tools + 2 spare; `max_replication_slots` ≥ standbys + other slots |
| Parameter parity | Standby `max_connections`, `max_worker_processes`, `max_wal_senders`, `max_prepared_transactions`, `max_locks_per_transaction` **≥ primary** ([02](02-standby-setup-guide.md)). Raise standbys first |
| Naming | Set `application_name` in each `primary_conninfo` |
| Timeouts | `wal_sender_timeout`/`wal_receiver_timeout` (60 s default) fit your network; `wal_receiver_status_interval` 10 s |
| Read replicas | Decide per standby: HA target (small delay, feedback off) or reporting (large delay or feedback on) ([05](05-hot-standby-and-query-conflicts.md)) |
| Checksums / hints | Keep data checksums (default in PG18 `initdb`) or `wal_log_hints = on` so `pg_rewind` works ([07](07-failover-switchover-promotion.md)) |
| Host-specific settings | Keep outside the replicated/rewound config (include files), because base backups and `pg_rewind` copy `postgresql.conf` ([07](07-failover-switchover-promotion.md)) |
| `pg_hba.conf` | Replication entries present on **every** node that might become primary |
| TLS | `hostssl` + `sslmode=verify-full` in `primary_conninfo`; passwords via `passfile`, never in command lines |
| Time | NTP/chrony on all nodes (time-based lag, PITR targets, heartbeat tables) |

### Operations

- Monitor: standby count and `state`, byte lag by stage, slot retention/`wal_status`, archiver failures, WAL disk, replay paused, conflict counters
  ([06](06-monitoring-and-lag.md)).
- Alert on **bytes**, not only time: `replay_lag` can be stale while a standby is far behind ([06](06-monitoring-and-lag.md)).
- Schedule DDL/maintenance considering recovery conflicts: `lock_timeout` for DDL; avoid long standby queries during `VACUUM FULL`/`ALTER TABLE` ([05](05-hot-standby-and-query-conflicts.md)).
- Practice failover and switchover regularly; keep the runbook in version control ([07](07-failover-switchover-promotion.md)).
- **Fence** the old primary before promoting — the cheapest incident is the one where only one node can write.
- After a failover, rebuild/rewind the old primary promptly; until then you have no redundancy.
- Test restore from backup+archive quarterly; test `pg_rewind` prerequisites (WAL retained, checksums).
- Use `idle_replication_slot_timeout` (18+) to stop forgotten slots from pinning WAL ([03](03-replication-slots-and-wal-retention.md)).

### Anti-patterns

| Anti-pattern | Why it hurts |
|---|---|
| Unlimited slot retention, no alerts | A dead standby fills the primary's disk |
| One synchronous standby, no fallback plan | Standby loss = write outage ([04](04-synchronous-replication.md)) |
| Forgetting `standby.signal` after copying a data dir | The node starts as an independent **primary** (tested, below) |
| Long reporting queries on the HA standby with `max_standby_streaming_delay = -1` | Replay stalls; failover would need a long catch-up ([05](05-hot-standby-and-query-conflicts.md)) |
| `hot_standby_feedback = on` plus an idle-in-transaction session on the standby | Primary bloat |
| Using the replica as backup | No point-in-time history |
| Copying `postgresql.conf` blindly between nodes | Wrong `port`, paths, `archive_command` ([07](07-failover-switchover-promotion.md)) |
| Promoting a standby without checking it is the most advanced | Loses acknowledged commits unnecessarily |
| Two nodes writable ("split brain") | Divergent timelines; one side's work must be discarded |

## 2. Troubleshooting: symptom → cause → fix

### Connection and startup

| Symptom / message | Cause | Fix |
|---|---|---|
| `FATAL: no pg_hba.conf entry for replication connection from host "…", user "repl"` **(docs; not reproducible in my lab because `initdb`'s default `pg_hba.conf` already allows localhost replication)** | Missing `replication` line | Add `host replication repl <ip>/32 scram-sha-256`, reload. Remember `all` does **not** match `replication` |
| `FATAL: streaming replication receiver "walreceiver" could not connect to the primary server: … FATAL: password authentication failed for user …` **(tested)** | Wrong/absent password in `primary_conninfo`/`.pgpass` | Fix credentials; `ALTER ROLE repl PASSWORD …` |
| `FATAL: number of requested standby connections exceeds "max_wal_senders" (currently 0)` **(tested, via `pg_basebackup`)** | `max_wal_senders` too low | Increase on the primary (restart) |
| `FATAL: WAL streaming ("max_wal_senders" > 0) requires "wal_level" to be "replica" or "logical"` **(tested; primary refuses to start)** | `wal_level = minimal` with senders enabled | Set `wal_level = replica` or set `max_wal_senders = 0` |
| `FATAL: could not start WAL streaming: ERROR: replication slot "nosuch" does not exist` **(tested)** | `primary_slot_name` points to a missing slot | Create it on the upstream or fix the name |
| `ERROR: replication slot "s1" is active for PID 119` **(tested, second receiver)** | A slot has one active consumer | Use a distinct slot per consumer; stop the other |
| `FATAL: recovery aborted because of insufficient parameter settings` + `max_connections = 50 is a lower setting than on the primary…` **(tested)** | Parameter parity | Raise on the standby, restart |
| Standby came up `in_recovery = f` after copying a data directory **(tested)** | `standby.signal` missing → normal crash recovery, then **a second primary** | Recreate with `-R`/`touch standby.signal`; check `pg_is_in_recovery()` before exposing it |
| `FATAL: could not receive data from WAL stream: ERROR: requested WAL segment … has already been removed` **(tested, [03](03-replication-slots-and-wal-retention.md))** | Standby too far behind and no slot/archive | Provide `restore_command` + archive, or rebuild the standby |
| `FATAL: could not start WAL streaming: ERROR: can no longer access replication slot "s2"` / `invalidated due to "wal_removed"` **(tested)** | Slot exceeded `max_slot_wal_keep_size` | Rebuild or recover via archive; fix retention/alerts |
| Standby loops on `new timeline 2 forked off current database system timeline 1 before current recovery point` **(tested, [07](07-failover-switchover-promotion.md))** | Old primary diverged | `pg_rewind` or re-clone |

### Lag and conflicts

| Symptom | Cause | Fix |
|---|---|---|
| `ERROR: canceling statement due to conflict with recovery` + `User query might have needed to see row versions that must be removed.` **(tested)** | Snapshot conflict | `hot_standby_feedback` on (watch bloat) or larger `max_standby_streaming_delay` ([05](05-hot-standby-and-query-conflicts.md)) |
| Same + `User was holding a relation lock for too long.` **(tested)** | DDL / ACCESS EXCLUSIVE replayed | Feedback does **not** help: schedule DDL, shorten queries |
| `flush_lsn` advances but `replay_lsn` doesn't | Replay paused, conflict wait, delayed standby, slow redo | `pg_is_wal_replay_paused()`; check `recovery_min_apply_delay`; check long standby queries |
| `replay_lag` looks fine but data is old | Stale lag sample | Use byte lag ([06](06-monitoring-and-lag.md)) |
| `now() - pg_last_xact_replay_timestamp()` large on an idle system | No WAL to replay, not lag | Compare receive vs replay LSN ([06](06-monitoring-and-lag.md)) |
| Writers hang with `wait_event = SyncRep` **(tested)** | Sync standby gone | Restore the standby or edit `synchronous_standby_names` ([04](04-synchronous-replication.md)) |
| Primary disk fills | Inactive slot, failing `archive_command`, huge `wal_keep_size` | Find the slot/archiver; cap retention ([03](03-replication-slots-and-wal-retention.md), [08](08-cascading-delayed-archive.md)) |
| Lag only during bulk jobs | Redo throughput | Throttle jobs; faster standby I/O; `recovery_prefetch`; see [06](06-monitoring-and-lag.md) |
| `archive_command` failing, `pg_wal` growing | Archive target down / permissions | `pg_stat_archiver.last_failed_wal`; fix command; the primary keeps WAL until it succeeds |

### Failover day

| Symptom | Cause | Fix |
|---|---|---|
| Promoted standby refuses connections from the next standby | `pg_hba.conf`/`max_wal_senders`/role missing there | Pre-provision on every candidate |
| `pg_rewind: error: could not fetch remote file … permission denied for function pg_read_binary_file` **(tested)** | Source role lacks privileges | Superuser or the four `GRANT EXECUTE` statements in [07](07-failover-switchover-promotion.md) |
| `pg_rewind: error: could not find previous WAL record` **(tested)** | WAL since the last common checkpoint was recycled | `-c`/`--restore-target-wal` with a `restore_command`, or keep more WAL; else re-clone |
| Rewound node won't start: `could not create any TCP/IP sockets` **(tested)** | `pg_rewind` copied the source's `postgresql.conf` | Restore `port`/addresses/paths |
| Standbys on different timelines | Promoted a standby that wasn't the most advanced | Rebuild the ones ahead; always compare LSNs first |
| Old primary reappears and accepts writes | No fencing | Fence; rewind or discard it |

## 3. Diagnostic cheat-sheet

```sql
-- primary
SELECT * FROM pg_stat_replication;
SELECT slot_name, active, wal_status, restart_lsn, safe_wal_size FROM pg_replication_slots;
SELECT * FROM pg_stat_archiver;
SELECT pg_current_wal_lsn(), pg_walfile_name(pg_current_wal_lsn());
SELECT name, setting FROM pg_settings WHERE name IN
 ('wal_level','max_wal_senders','max_replication_slots','wal_keep_size','max_slot_wal_keep_size',
  'synchronous_standby_names','synchronous_commit','archive_mode','archive_command');

-- standby
SELECT pg_is_in_recovery(), pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn(), pg_is_wal_replay_paused();
SELECT * FROM pg_stat_wal_receiver;
SELECT * FROM pg_stat_database_conflicts;
SELECT name, setting FROM pg_settings WHERE name IN
 ('hot_standby','hot_standby_feedback','max_standby_streaming_delay','max_standby_archive_delay',
  'primary_conninfo','primary_slot_name','recovery_min_apply_delay','restore_command');
```

```bash
pg_controldata $PGDATA | egrep "cluster state|TimeLineID|checkpoint location|Minimum recovery"
ls $PGDATA/pg_wal | tail            # which timeline/segments
tail -f $PGDATA/log/*.log           # walreceiver / startup messages are the best clues
```

## 4. Pre-production checklist

- [ ] ≥ 2 standbys; failure domains separated; fencing exists.
- [ ] Parameter parity table checked; `application_name` set; HBA/roles on all candidates.
- [ ] Slots + cap + alerts + archive; archiver monitored; restore tested.
- [ ] Lag alerts in bytes; sync-wait alert; replay-paused alert; conflict counters.
- [ ] Failover and switchover rehearsed; `pg_rewind` prerequisites verified; runbook current.
- [ ] Standby query policy decided and enforced (`statement_timeout`).
- [ ] Backups independent of replication; PITR drill done.
- [ ] Config management keeps host-specific settings outside copied files.
