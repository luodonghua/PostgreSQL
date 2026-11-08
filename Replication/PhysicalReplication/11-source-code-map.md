# 11 — Source-Code Map (optional reading guide)

Level: L400. Pointers from the PostgreSQL checkout at `../postgres`
(`git describe`: `REL_19_BETA1-1490-g0607aa61090`, i.e. **20devel master**). Line numbers are from that
checkout and will drift; search by function name. The behaviour in these notes was tested on 18.6; the
physical-replication architecture has been stable for many releases. Logical-replication
counterpart: [logical topic 19](../LogicalReplication/19-source-code-map.md).

## Where things live (under `src/backend/` unless noted)

| Path | Role |
|---|---|
| `replication/walsender.c` | Walsender: replication-protocol commands, physical (`XLogSendPhysical`) and logical sending, reply handling |
| `replication/walreceiver.c` | Walreceiver on the standby: connects, writes + flushes WAL, sends replies and feedback |
| `replication/walreceiverfuncs.c` | Shared-memory helpers, start/stop of the receiver |
| `replication/libpqwalreceiver/` | libpq client used by the walreceiver |
| `replication/syncrep.c` (+ `syncrep_gram.y`) | Synchronous replication: waiting, release, parsing `synchronous_standby_names` |
| `replication/slot.c`, `slotfuncs.c` | Replication slots (shared with logical) |
| `access/transam/xlogrecovery.c` | Recovery/standby control: reading WAL (archive/stream), applying records, pause, delay, targets |
| `access/transam/xlog.c` | WAL writing, checkpoints and **restartpoints**, WAL recycling (`KeepLogSeg`) |
| `access/transam/xlogarchive.c` | `restore_command` and archiving notifications |
| `access/transam/timeline.c` | Timeline history files |
| `access/transam/xlogfuncs.c` | SQL functions: `pg_promote`, `pg_wal_replay_pause`, … |
| `storage/ipc/standby.c` | Hot-standby conflict resolution (snapshot, lock, buffer pin) |
| `storage/ipc/procarray.c` | Known-assigned XIDs on a standby (snapshots during recovery) |
| `backup/basebackup.c` | Server side of `pg_basebackup` (BASE_BACKUP command) |
| `postmaster/startup.c` | The startup process main loop and signals (promote request) |
| `src/bin/pg_basebackup/` | `pg_basebackup`, `pg_receivewal`, `pg_recvlogical`, `pg_createsubscriber` |
| `src/bin/pg_rewind/` | `pg_rewind` |

## Follow one commit end to end

| Step | Concept ([topic](README.md)) | Function(s) |
|---|---|---|
| 1 | Standby connects; sender starts at a position | `walsender.c: StartReplication` → `WalSndLoop` |
| 2 | Send newly flushed WAL | `walsender.c: XLogSendPhysical` (reads WAL, sends `XLogData`) |
| 3 | Receiver main loop | `walreceiver.c: WalReceiverMain` → `XLogWalRcvProcessMsg` |
| 4 | Write + fsync into the standby's `pg_wal` | `walreceiver.c: XLogWalRcvWrite`, `XLogWalRcvFlush` |
| 5 | Report write/flush/apply positions | `walreceiver.c: XLogWalRcvSendReply` |
| 6 | Primary processes the reply → `pg_stat_replication`, slot, sync waiters | `walsender.c: ProcessStandbyReplyMessage` → `syncrep.c: SyncRepReleaseWaiters` |
| 7 | Backend commit waits ([04](04-synchronous-replication.md)) | `syncrep.c: SyncRepWaitForLSN`; choosing sync standbys: `SyncRepGetSyncRecPtr`, `SyncRepGetCandidateStandbys` |
| 8 | Hot-standby feedback ([05](05-hot-standby-and-query-conflicts.md)) | `walreceiver.c: XLogWalRcvSendHSFeedback` |
| 9 | Standby reads WAL (stream vs archive) ([08](08-cascading-delayed-archive.md)) | `xlogrecovery.c: WaitForWALToBecomeAvailable`; archive: `xlogarchive.c: RestoreArchivedFile` |
| 10 | Redo | `xlogrecovery.c: PerformWalRecovery` → `ApplyWalRecord` |
| 11 | Consistency point (when hot standby may open) | `xlogrecovery.c: CheckRecoveryConsistency` |
| 12 | Delay / pause ([04](04-synchronous-replication.md), [06](06-monitoring-and-lag.md)) | `xlogrecovery.c: recoveryApplyDelay`, `recoveryPausesHere` |
| 13 | Conflicts ([05](05-hot-standby-and-query-conflicts.md)) | `standby.c: ResolveRecoveryConflictWithSnapshot`, `…WithLock`, `…WithBufferPin`; timeouts: `StandbyTimeoutHandler` |
| 14 | Parameter parity check ([02](02-standby-setup-guide.md)) | `xlogrecovery.c: RecoveryRequiresIntParameter` (source of `recovery aborted because of insufficient parameter settings`) |
| 15 | Restartpoints on the standby | `xlog.c: CreateRestartPoint` |
| 16 | WAL retention ([03](03-replication-slots-and-wal-retention.md)) | `xlog.c: KeepLogSeg`, `RemoveOldXlogFiles`; slot minimum: `slot.c: ReplicationSlotsComputeRequiredLSN` |
| 17 | Promotion ([07](07-failover-switchover-promotion.md)) | `xlogfuncs.c: pg_promote`; handled in `postmaster/startup.c` / `xlogrecovery.c`; timelines: `timeline.c: findNewestTimeLine`, `writeTimeLineHistory`, `readTimeLineHistory` |
| 18 | Base backup | `backup/basebackup.c: SendBaseBackup` → `perform_base_backup`; client: `src/bin/pg_basebackup/pg_basebackup.c: main` |
| 19 | `pg_rewind` | `src/bin/pg_rewind/pg_rewind.c: main`, `findCommonAncestorTimeline`; file map in `filemap.c`, WAL scan in `parsexlog.c` |
| 20 | Streaming archive | `src/bin/pg_basebackup/pg_receivewal.c: main` |
| 21 | Pause/resume functions | `xlogfuncs.c: pg_wal_replay_pause` |

## Reading order suggestions

1. `walreceiver.c` file header, then `WalReceiverMain` — the shortest path to understand the standby side.
2. `syncrep.c` header comment — the data structures for waiting and the quorum logic.
3. `xlogrecovery.c: WaitForWALToBecomeAvailable` — the state machine between archive, `pg_wal` and streaming
   (it explains the restore-then-stream behaviour tested in [08](08-cascading-delayed-archive.md)).
4. `standby.c` header — how recovery conflicts are detected and resolved.
5. `src/bin/pg_rewind/pg_rewind.c` — the algorithm (find the divergence, build the file/page map, copy).
6. `timeline.c` — history files (what `00000002.history` in [07](07-failover-switchover-promotion.md) contains).

## Tips

```bash
git grep -n "ResolveRecoveryConflictWithSnapshot" -- src/backend           # who raises snapshot conflicts
git log -S"synchronized_standby_slots" --oneline -- src/backend/replication # when a feature arrived
git tag --contains <commit> | sort -V | head -1                            # first release containing it
```
