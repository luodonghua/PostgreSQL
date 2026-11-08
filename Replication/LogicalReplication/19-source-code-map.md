# 19 — Source-Code Map (optional reading guide)

Level: L400. For when you *do* want to read the code. Every pointer below was obtained
by searching the PostgreSQL source checkout at `../postgres`
(`git describe`: `REL_19_BETA1-1490-g0607aa61090`, i.e. **20devel master**; this is not
GA code). Line numbers are from that checkout and **will drift**; search by function
name. Behaviour was tested on 18.6; the structure below has been stable since PG 10–16 unless
marked ⚠️.

## Directory orientation

| Path (under `src/backend/`) | Role |
|---|---|
| `replication/walsender.c` | The server process that speaks the replication protocol, physical and logical |
| `replication/slot.c`, `slotfuncs.c` | Slot storage, invalidation, SQL-callable slot functions |
| `replication/logical/logical.c` | Logical decoding "context": ties reader, decoder, reorder buffer, plugin together |
| `replication/logical/decode.c` | Reads WAL records, dispatches by resource manager |
| `replication/logical/reorderbuffer.c` | Per-transaction change queues, spill, streaming |
| `replication/logical/snapbuild.c` | Historic catalog snapshots; consistent-point logic |
| `replication/logical/message.c` | `pg_logical_emit_message` |
| `replication/logical/origin.c` | Replication origins (progress tracking, loop prevention) |
| `replication/pgoutput/pgoutput.c` | The built-in output plugin: publications, filters, encoding |
| `replication/logical/proto.c` | Encoding/decoding of the logical replication messages |
| `replication/logical/launcher.c` | Starts/stops apply and sync workers |
| `replication/logical/worker.c` | The apply worker: executes remote changes |
| `replication/logical/applyparallelworker.c` | Parallel apply (leader/worker protocol, locking design comments) |
| `replication/logical/tablesync.c` | Initial copy and hand-off state machine (the header comment is the spec) |
| `replication/logical/relation.c` | Mapping remote relations to local tables; row lookup |
| `replication/logical/conflict.c` | Conflict detection and reporting |
| `replication/logical/slotsync.c` | Failover-slot synchronisation to standbys (17+) |
| `replication/logical/logicalctl.c` | ⚠️ Dynamic enable/disable of logical decoding (`effective_wal_level`, 19) |
| `replication/logical/sequencesync.c` | ⚠️ Sequence synchronisation (19) |
| `commands/publicationcmds.c`, `catalog/pg_publication.c` | `CREATE/ALTER PUBLICATION`, catalog access |
| `commands/subscriptioncmds.c` | `CREATE/ALTER/DROP SUBSCRIPTION` |
| `replication/libpqwalreceiver/` | The libpq client the subscriber uses to talk to the publisher |
| `include/replication/` | Public structs (`ReplicationSlot`, `LogicalDecodingContext`, `ReorderBuffer`…) |

## Follow one change end to end

Concept → function (your debugger/`grep` entry points):

| Step | Concept ([topic](README.md)) | Function(s) |
|---|---|---|
| 1 | Client connects with `START_REPLICATION … LOGICAL` ([08](08-pgoutput-protocol.md)) | `walsender.c: StartLogicalReplication` → `WalSndLoop` → `XLogSendLogical` |
| 2 | Slot create / initial snapshot ([05](05-replication-slots.md), [06](06-logical-decoding.md)) | `walsender.c: CreateReplicationSlot`; `slot.c: ReplicationSlotCreate`; `logical.c: CreateInitDecodingContext`, `DecodingContextFindStartpoint`; `snapbuild.c: SnapBuildProcessRunningXacts`, `SnapBuildInitialSnapshot` |
| 3 | Open an existing slot for decoding | `logical.c: CreateDecodingContext` |
| 4 | Read + dispatch WAL | `decode.c: LogicalDecodingProcessRecord` → `heap_decode` → `DecodeInsert` / `DecodeUpdate` / `DecodeDelete`; `xact_decode` → `DecodeCommit` |
| 5 | Queue the change under its xid ([07](07-reorderbuffer-and-large-transactions.md)) | `reorderbuffer.c: ReorderBufferQueueChange` |
| 6 | Memory pressure → spill or stream | `ReorderBufferCheckMemoryLimit` → `ReorderBufferSerializeTXN` (spill) or `ReorderBufferStreamTXN` (stream) |
| 7 | Catalog snapshot for decoding | `snapbuild.c: SnapBuildCommitTxn`, `SnapBuildBuildSnapshot` |
| 8 | On commit, replay changes to the plugin | `reorderbuffer.c: ReorderBufferCommit` → `ReorderBufferProcessTXN` |
| 9 | Publication filtering, encoding | `pgoutput.c: pgoutput_change`, `pgoutput_row_filter`, `pgoutput_row_filter_init`, `pgoutput_column_list_init`, `send_relation_and_attrs`; `proto.c: logicalrep_write_insert/update/…` |
| 10 | Send, wait for replies; advance slot | `walsender.c: ProcessStandbyReplyMessage` → `logical.c: LogicalConfirmReceivedLocation`, `LogicalIncreaseRestartDecodingForSlot` |
| 11 | Protect WAL / catalog horizon | `slot.c: ReplicationSlotsComputeRequiredLSN`, `ReplicationSlotsComputeRequiredXmin`; invalidation: `InvalidateObsoleteReplicationSlots` |
| 12 | Subscriber: launch workers | `launcher.c: ApplyLauncherMain`, `logicalrep_worker_launch` |
| 13 | Apply worker main loop & dispatch | `worker.c: apply_dispatch` → `apply_handle_insert` / `_update` / `_delete` / `_truncate` / `_commit`; stream: `apply_handle_stream_start`, `apply_handle_stream_commit` |
| 14 | Find the local row to modify ([09](09-replica-identity.md)) | `relation.c: logicalrep_rel_open`; `worker.c: FindReplTupleInLocalRel`; `executor/execReplication.c: RelationFindReplTupleByIndex` (index lookup) / `RelationFindReplTupleSeq` (sequential scan — the slow `FULL`-without-index path) |
| 15 | Record progress atomically with data | `origin.c: replorigin_session_setup`, `replorigin_advance` |
| 16 | Conflicts ([12](12-conflicts-and-error-handling.md)) | `conflict.c: ReportApplyConflict`, `GetTupleTransactionInfo` |
| 17 | Initial copy ([10](10-initial-sync-tablesync.md)) | `tablesync.c: LogicalRepSyncTableStart`, `copy_table`, `ProcessSyncingTablesForApply` |
| 18 | Parallel apply ([11](11-apply-workers-and-parallel-apply.md)) | `applyparallelworker.c: pa_launch_parallel_worker`, `pa_send_data`, `ParallelApplyWorkerMain` |
| 19 | Slot sync to standbys ([16](16-failover-and-ha.md)) | `slotsync.c: ReplSlotSyncWorkerMain`, `synchronize_slots`, `SyncReplicationSlots` |
| 20 | SQL commands | `publicationcmds.c: CreatePublication`, `AlterPublicationTables`; `subscriptioncmds.c: CreateSubscription`, `AlterSubscription`, `AlterSubscription_refresh`, `DropSubscription` |
| 21 | Logical messages ([06](06-logical-decoding.md)) | `message.c: LogLogicalMessage` |
| 22 | ⚠️ Dynamic decoding enablement | `logicalctl.c: EnsureLogicalDecodingEnabled`, `EnableLogicalDecoding` |
| 23 | ⚠️ Sequence sync | `sequencesync.c: LogicalRepSyncSequences`, `SequenceSyncWorkerMain` |

## Data structures worth knowing

| Struct / concept | Where | Why you care |
|---|---|---|
| `ReplicationSlot` / `ReplicationSlotPersistentData` | `include/replication/slot.h` | All slot columns of `pg_replication_slots` map here; invalidation causes `RS_INVAL_*` |
| `LogicalDecodingContext` | `include/replication/logical.h` | The bundle passed to plugin callbacks |
| `ReorderBufferTXN`, `ReorderBufferChange` | `include/replication/reorderbuffer.h` | The queued unit of work |
| `OutputPluginCallbacks` | `include/replication/output_plugin.h` | What a plugin must implement ([06](06-logical-decoding.md)) |
| `SnapBuildState` (`START`, `BUILDING_SNAPSHOT`, `FULL_SNAPSHOT`, `CONSISTENT`) | `include/replication/snapbuild.h` | Why slot creation waits ([06](06-logical-decoding.md)) |
| `ConflictType` (`CT_INSERT_EXISTS` …) | `include/replication/conflict.h` | Maps to `confl_*` columns |
| Relation states `SUBREL_STATE_*` | `include/catalog/pg_subscription_rel.h` | `i d f s r` + in-memory `w c` |
| `LogicalRepWorker` | `include/replication/worker_internal.h` | Per-worker shared-memory state |

## Reading order suggestions

1. `tablesync.c` header comment (state machine) — 60 lines that explain a lot.
2. `applyparallelworker.c` header — the deadlock-avoidance design.
3. `logicalctl.c` header ⚠️ — a good short essay on the dynamic enablement design.
4. `snapbuild.c` header — the most subtle part of logical decoding.
5. `reorderbuffer.c` header — memory, spilling and streaming rules.
6. `pgoutput.c: pgoutput_change` — to see how filters and identity affect messages.
7. `worker.c: apply_handle_update_internal` — conflict detection in the apply path.

## Tooling for exploring

```bash
# in the postgres checkout
git grep -n "ReorderBufferCheckMemoryLimit" -- src/backend
cscope/ctags work well; or use `git log -S"<symbol>" -- <file>` to see when a feature landed
git tag --contains <commit> | sort -V | head      # first release containing a feature
```

That last pattern is how the ⚠️ version labels in these notes were assigned
(e.g. `ALL SEQUENCES`, `retain_dead_tuples`, `effective_wal_level` first appear in
`REL_19_BETA1`; `conflict_log_destination` lands on master after the 19 branch).
