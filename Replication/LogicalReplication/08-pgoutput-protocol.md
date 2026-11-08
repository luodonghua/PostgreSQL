# 08 — The `pgoutput` Wire Protocol

Level: L300 → L400. Tested on PostgreSQL 18.6: raw messages captured with
`pg_logical_slot_peek_binary_changes` and decoded by hand below. Source:
`replication/pgoutput/pgoutput.c`, `replication/logical/proto.c`.

You do not need to speak this protocol to use logical replication, but
knowing its shape explains replica identity, column lists, why `Relation`
messages appear when they do, and what Debezium or a custom client receives.

## Framing

A subscriber opens a normal connection with the **replication protocol** (a
`dbname=` is given, so it's a *logical* walsender) and issues:

```
START_REPLICATION SLOT "s" LOGICAL 0/0
   (proto_version '4', streaming 'parallel', origin 'any', publication_names '"p"')
```

The server answers with a COPY-BOTH stream. Inside it:

| Outer tag | Direction | Content |
|---|---|---|
| `w` | server → client | **XLogData**: start LSN, end LSN, send time, then one pgoutput message |
| `k` | server → client | **Keepalive**: current WAL end, time, "reply requested?" flag |
| `r` | client → server | **Standby status update**: written / flushed / applied LSN, time, "reply requested?" — this is how `confirmed_flush_lsn` advances |

`wal_sender_timeout` / `wal_receiver_timeout` (default 60 s) are enforced
through the `k` / `r` exchange.

## Protocol versions

| `proto_version` | PG | Adds |
|---|---|---|
| 1 | 10 | Begin, Commit, Origin, Relation, Type, Insert, Update, Delete, Truncate (11), Message (14) |
| 2 | 14 | Streaming of in-progress transactions: Stream Start/Stop/Commit/Abort |
| 3 | 15 | Two-phase: Begin Prepare, Prepare, Commit Prepared, Rollback Prepared, Stream Prepare |
| 4 | 16 | Parallel apply support (streamed abort carries extra LSN/timestamp info so a parallel worker can finish correctly) |

## Message catalogue (first byte)

| Byte | Message | Meaning |
|---|---|---|
| `B` | Begin | final LSN of txn, commit timestamp, xid |
| `C` | Commit | flags, commit LSN, end LSN, commit timestamp |
| `O` | Origin | the transaction came from another replication origin (carries the origin name) |
| `R` | Relation | schema of a table: oid, namespace, name, replica identity, columns |
| `Y` | Type | name of a user-defined type used by a column |
| `I` | Insert | new tuple |
| `U` | Update | optional old key (`K`) or old full row (`O`), then new tuple (`N`) |
| `D` | Delete | old key (`K`) or old full row (`O`) |
| `T` | Truncate | option flags, list of relation oids |
| `M` | Message | `pg_logical_emit_message` payload (needs `messages` option) |
| `S`/`E`/`c`/`A` | Stream Start / Stop / Commit / Abort | in-progress transaction framing |
| `b`/`P`/`K`/`r`/`p` | Begin Prepare / Prepare / Commit Prepared / Rollback Prepared / Stream Prepare | two-phase |

(`O` as a top-level message is "Origin"; inside an Update/Delete it is the
"old row" tuple tag. Context disambiguates.)

## Decoded bytes — real capture

Table `t(id int primary key, v text)` in publication `p`, then:
`INSERT (1,'ab')`, `UPDATE v='cd'`, `UPDATE id=2` (key change), `DELETE id=2`, `TRUNCATE`.

Message order returned (types): `B R I C  B U C  B U C  B D C  B R T C`.

Notice **`R` appears before the first change** of a table in a decoding
session. It showed up a second time in the last transaction (the `TRUNCATE`).
My reading of `pgoutput.c` is that the walsender caches "relation already
sent" state per session and re-sends `R` after that cache entry is invalidated;
`TRUNCATE` rewrites the relfilenode, which invalidates it. I did not prove
this separately. Whatever the trigger, a client must treat every `R` as
authoritative and cache it to decode the tuples that follow.

### `B` Begin

```
42  0000000001 79a358  000302ac3bd1d805  000002f2
B   final LSN (8)      commit ts (8)     xid (4) = 754
```

### `R` Relation

```
52 00004000 7075626c696300 7400 64 0002
R  relid=16384 "public\0"  "t\0" 'd' = replica identity DEFAULT, 2 columns
   01 696400 00000017 ffffffff     col 1: flags=1 (part of key), "id", type oid 23 (int4), typmod -1
   00 7600   00000019 ffffffff     col 2: flags=0,                "v",  type oid 25 (text), typmod -1
```

- Replica identity byte: `d` default, `n` nothing, `f` full, `i` index.
- Column flag `1` = column is part of the replica identity key.
- With **column lists**, only listed columns appear here. With
  `REPLICA IDENTITY FULL` every column has flag `1` (verified: `66` = `f`, both
  columns `01`).

### `I` Insert

```
49 00004000 4e 0002 74 00000001 31   74 00000002 6162
I  relid    N  2 cols: 't'ext len=1 "1"; 't'ext len=2 "ab"
```

Per-column kind byte: `n` NULL, `u` unchanged TOASTed value (not sent), `t` text
representation, `b` binary representation (when `binary = true`).

### `U` Update

Three shapes, all observed:

| Shape | Bytes | Meaning |
|---|---|---|
| Only new tuple | `55 00004000 4e 0002 …` | key unchanged: no old row sent |
| Old key + new | `55 00004000 4b 0002 74 1 "1" 6e  4e 0002 74 "2" 74 "cd"` | key changed (`K` + NULL `n` for non-key col, then `N`) |
| Old full row + new | `55 00004000 4f 0002 74 "5" 74 "x"  4e 0002 74 "5" 74 "y"` | identity FULL (`O` + `N`) |

### `D` Delete

```
44 00004000 4b 0002 74 00000001 32 6e
D  relid    K  old key tuple: id='2', v=NULL (non-key columns are `n`)
```

### `T` Truncate

```
54 00000001 00 00004000
T  1 relation, option flags 0 (bit 1 = CASCADE, bit 2 = RESTART IDENTITY), relid
```

### `C` Commit

```
43 00 0000000001 79a358  0000000001 79a388  000302ac3bd1d805
C  flags, commit LSN (0/179A358 = the B message's final LSN), end LSN (0/179A388), commit ts
```

## What decides what's in a message

| Concern | Where it's applied | Visible as |
|---|---|---|
| Which tables | `publication_names` → `pg_publication_tables` | only those relids appear in `R` |
| Which operations | publication `publish` | missing `U`/`D`/`T` messages |
| Row filter | `pgoutput_row_filter` per change | filtered rows skipped; UPDATE may become `I`/`D` |
| Column list | `R` message lists fewer columns; tuples have fewer | |
| Generated columns | `publish_generated_columns` (18) | included/excluded from `R` |
| Origin filter | `origin = none` | changes with a replication origin are skipped on the publisher |
| Partition root | `publish_via_partition_root` | relid in `R` is the root's |
| Binary | `binary = true` | column kind `b` instead of `t` |
| Streaming | `streaming` | `S … E` framed groups, final `c` or `A` |

## Why this matters in practice

1. **Debezium/other clients**: they must cache `R` messages and handle type
   OIDs themselves; schema changes surface as a new `R`, not as a DDL event.
2. **Delete/update rows depend on identity**: this is exactly the data in the
   `K`/`O` tuple. Without identity you cannot build a correct downstream key.
3. **Text vs binary**: text is portable across versions/architectures; binary
   is faster but requires matching type send/receive formats — mismatch
   produces apply errors like `incorrect binary data format`.
4. **Unchanged TOAST** (`u`): the subscriber keeps its stored value. If the
   subscriber's value differs (it diverged), the divergence persists silently.
5. **No schema in the stream beyond names/oids/typmods**: constraints, defaults,
   indexes are not conveyed — they are the subscriber's own business.

## Doing this yourself

```sql
SELECT pg_create_logical_replication_slot('po','pgoutput');
-- DML …
SELECT encode(data,'hex')
FROM pg_logical_slot_peek_binary_changes('po', NULL, NULL,
       'proto_version','1', 'publication_names','p');
```

The publication named in `publication_names` must exist at the WAL position
being decoded; otherwise: `WARNING: skipped loading publication "p"` /
`DETAIL: The publication does not exist at this point in the WAL.` (seen when I
created the slot before the publication).
