# 07 — Reorder Buffer, Spilling and Streaming of Large Transactions

Level: L300. Tested on PostgreSQL 18.6 (spill vs streaming experiment below).
Source: `replication/logical/reorderbuffer.c`.

## The problem

Logical replication must deliver transactions in **commit order**, but WAL
interleaves all running transactions by *change* order. The walsender therefore
buffers each transaction's changes until it sees the COMMIT record. A single
bulk load (`INSERT … SELECT` of 10 M rows) is a single transaction, so the
walsender holds — or must otherwise park — all of it before the first row can
be sent.

## Three strategies as the buffer fills

Controlled by `logical_decoding_work_mem` (default **64 MB**, per walsender /
decoding session, not per transaction):

| Strategy | When | Cost |
|---|---|---|
| Keep in memory | Total buffered < `logical_decoding_work_mem` | None |
| **Spill** to disk | Limit exceeded and streaming not in use | Writes `pg_replslot/<slot>/xid-<xid>-lsn-….spill`, re-read at commit; doubles the I/O and delays the first byte |
| **Stream** in progress | Limit exceeded and the subscriber asked for `streaming = on/parallel` | Sends changes immediately as "stream chunks"; subscriber stages or applies them; final COMMIT/ABORT message ends it |

When the limit is hit the buffer evicts the **largest** top-level transaction
(so one monster does not force small ones to disk).

## Experiment: spill vs stream (18.6)

Publisher with `logical_decoding_work_mem = 1MB`. One transaction inserted
200 000 rows × ~200 bytes (≈ 65 MB of decoded changes), held open 2 s, then
committed. Subscriber created with `streaming = off | on | parallel`.
`pg_stat_replication_slots` on the publisher afterwards:

| `streaming` | `spill_txns` | `spill_count` | `spill_bytes` | `stream_txns` | `stream_count` | `stream_bytes` | `total_bytes` | Extra subscriber process |
|---|---|---|---|---|---|---|---|---|
| `off` | 1 | 65 | 65 MB | 0 | 0 | 0 | 65 MB | — |
| `on` | 0 | 0 | 0 | 1 | 65 | 65 MB | 65 MB | — |
| `parallel` | 0 | 0 | 0 | 1 | 65 | 65 MB | 65 MB | `logical replication parallel apply worker` |

All three finished with 200 000 rows on the subscriber. The difference is
*where the 65 MB waited*:

- `off`: written to disk on the publisher and read back after the commit.
- `on`: pushed straight to the subscriber, which stages it in temporary
  `BufFile`s on disk (source: `worker.c`) and applies it at commit.
- `parallel`: pushed to a **parallel apply worker** which applies as the
  chunks arrive, so the commit is nearly instantaneous on the subscriber
  ([topic 11](11-apply-workers-and-parallel-apply.md)).

Counter meanings:

| Column | Meaning |
|---|---|
| `spill_txns` | transactions that ever spilled |
| `spill_count` | spill *events* (a transaction can spill many times) |
| `spill_bytes` | total bytes written to spill files |
| `stream_txns` / `stream_count` / `stream_bytes` | the same for streaming |
| `total_txns` / `total_bytes` | all decoded transactions / bytes sent to the output plugin |

Alerting idea: `spill_bytes / total_bytes` high → raise
`logical_decoding_work_mem` or turn on streaming.

## Setting `logical_decoding_work_mem`

- It is allocated **per slot / walsender**. 20 subscriptions × 256 MB = 5 GB of
  potential memory on the publisher.
- Raise it when spill counts are non-zero for ordinary traffic and you have
  memory; avoid raising it just to hide an occasional bulk load — use
  streaming for that.
- It can be set per-role/database for a specific replication user:
  `ALTER ROLE repl SET logical_decoding_work_mem = '256MB';`
- For testing the streaming path without giant transactions, the debug GUC
  `debug_logical_replication_streaming = immediate` forces every change to
  stream (do not use in production).

## What can and cannot be streamed

Streaming sends only changes that are **safely decodable before commit**. The
walsender holds back pieces that depend on future records:

- A change inside an incomplete **TOAST** sequence or **speculative insert**
  (`INSERT … ON CONFLICT`) is only released once complete.
- A transaction that has **catalog changes** (DDL) still streams, but the
  decoder needs the right snapshot; this works, it is just more work.
- **Sub-transactions** are streamed with their own xid and associated with the
  top-level transaction; a rolled-back savepoint is sent as a "stream abort"
  for that subxid only.
- If the transaction aborts, the walsender emits `STREAM ABORT` and the
  subscriber throws away the staged data — so wasted bandwidth is the price of
  early sending (and the reason the default for ordinary-size transactions is
  not to stream).

The plugin must implement the `stream_*` callbacks. `pgoutput` does. `wal2json`
and `test_decoding` support them behind options.

## Protocol version coupling

Streaming needs logical replication protocol ≥ 2 (14); parallel apply uses ≥ 4
(16). The subscriber asks for the version in `START_REPLICATION`:

```
START_REPLICATION SLOT "s" LOGICAL 0/0 (proto_version '4', streaming 'parallel', origin 'any', publication_names '"p"')
```

(captured from the 18.6 server log). A newer subscriber with an older
publisher will negotiate down; a subscriber asking for a feature the publisher
lacks fails with an explicit error.

## Interaction with other features

| Feature | Behaviour |
|---|---|
| `two_phase = true` | A *prepared* transaction can be decoded at `PREPARE` time (not only at commit) and sent early, then committed by `COMMIT PREPARED`. Streaming works with it via `stream_prepare`. |
| Row filters | Evaluated before the change is queued for sending; they don't reduce the ReorderBuffer's memory — the change is already in the buffer from decode. |
| `REPLICA IDENTITY FULL` | Old tuple is in WAL and in the buffer — memory use doubles for wide rows. |
| Truncate | Queued as a single change per transaction; always sent. |

## Operational guidance

1. **Monitor** `spill_*` and `stream_*` in `pg_stat_replication_slots`; reset with
   `pg_stat_reset_replication_slot('slot')`.
2. **Avoid huge single transactions** if you can: batch loads in chunks of
   10⁴–10⁵ rows. Smaller transactions mean lower latency for all consumers and
   less lag at once.
3. **Check disk** where `pg_replslot` lives (it is under `$PGDATA`): spill files
   consume space there, in addition to retained WAL.
4. If the replica falls behind by a big transaction, the lag looks stuck
   (no `confirmed_flush_lsn` movement) until that transaction's commit is
   applied; check `pg_stat_activity` on the subscriber for the apply worker
   instead of assuming it's hung.
5. `streaming = parallel` has a deadlock-prone corner (subscriber-side locks
   conflicting between the leader and parallel workers); the leader retries.
   See topic 11.

## Quick reference

```sql
-- how often do we spill / stream?
SELECT slot_name, spill_txns, spill_count, pg_size_pretty(spill_bytes) AS spilled,
       stream_txns, stream_count, pg_size_pretty(stream_bytes) AS streamed,
       total_txns, pg_size_pretty(total_bytes) AS total
FROM pg_stat_replication_slots;
```

```sql
-- subscription option
ALTER SUBSCRIPTION s SET (streaming = parallel);
```
