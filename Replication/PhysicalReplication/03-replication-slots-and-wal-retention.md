# 03 — Physical Replication Slots and WAL Retention

Level: L300. Tested on PostgreSQL 18.6 (scenarios A and B below were executed).
For logical slots see [logical topic 05](../LogicalReplication/05-replication-slots.md);
the slot columns and `wal_status` semantics are shared.

## The core question: how does the primary know a standby still needs old WAL?

The primary recycles WAL segments after a checkpoint once nothing needs them. A standby
that is slow or disconnected will ask for a segment that is gone. Three mechanisms keep WAL
alive for standbys, from crude to precise:

| Mechanism | Setting | Keeps | Risk |
|---|---|---|---|
| Fixed amount | `wal_keep_size` | The last N MB of WAL regardless of consumers | Too small → standby loses sync; too big → wasted disk |
| **Replication slot** | `pg_create_physical_replication_slot` / `primary_slot_name` | Everything since the slot's `restart_lsn` | **Unbounded disk growth** if the standby never returns |
| Archive | `archive_command` on primary + `restore_command` on standby | Everything in the archive | Needs archive infrastructure ([08](08-cascading-delayed-archive.md)) |

The recommended combination: **slot + a cap (`max_slot_wal_keep_size`) + an archive** as the last resort.

## Scenario A — no slot, the standby falls behind

Primary with `wal_keep_size = 0`, `max_wal_size = 64MB`, `checkpoint_timeout = 30s`. Standby stopped;
~120 MB of WAL generated with checkpoints; standby restarted:

```
FATAL:  could not receive data from WAL stream: ERROR:  requested WAL segment 000000010000000000000003 has already been removed
```

The primary kept only 3 WAL files. `pg_stat_replication` showed 0 connected standbys; the standby can't recover
by itself — you must rebuild it (new `pg_basebackup`) or provide the missing WAL from an archive.
This is the single most common physical-replication outage.

## Scenario B — a slot, and a cap

A physical slot is just a bookmark: a name and a `restart_lsn`.

```sql
SELECT pg_create_physical_replication_slot('s2');                  -- immediately_reserve defaults false
SELECT pg_create_physical_replication_slot('s1', true);            -- true = reserve WAL from now
```

and on the standby `primary_slot_name = 's2'`.
(`pg_basebackup -C -S name` creates it during the backup so there is no unprotected window.)

Primary configured with `max_slot_wal_keep_size = 48MB`. The standby was started once, stopped, then WAL was generated:

```
-- right after creating the slot, never used
 slot_name | active | wal_status | safe  | retained | invalidation_reason
 s2        | f      |            | 16 MB |          |              <- restart_lsn is NULL until first connection!

-- after ~40 MB of WAL (standby down)
 s2        | f      | reserved   | 20 MB | 44 MB    |

-- after ~60 MB more
 s2        | f      | lost       |       |          | wal_removed
```

Log on the primary:

```
LOG:  invalidating obsolete replication slot "s2"
DETAIL:  The slot's restart_lsn 0/3038460 exceeds the limit by 16546720 bytes.
```

Restarting the standby afterwards:

```
FATAL:  could not start WAL streaming: ERROR:  can no longer access replication slot "s2"
DETAIL:  This replication slot has been invalidated due to "wal_removed".
```

What to learn:

1. A slot created without `immediately_reserve` protects **nothing** until a standby connects (its
   `restart_lsn` is NULL). `-C` in `pg_basebackup` and `reserve_wal = true` avoid this.
2. Without `max_slot_wal_keep_size` (default `-1`, unlimited) the slot would have retained all ~110 MB and kept growing,
   until the primary's disk filled and the **primary** went down because of a dead standby.
3. With the cap, the primary survives and the slot is sacrificed. Then the standby must be re-created (or
   catch up from an archive if its `restore_command` can fetch the gap).
4. `safe_wal_size` shows the remaining headroom; `wal_status` goes
   `reserved → extended → unreserved → lost`.

### `wal_status` values

| Value | Meaning |
|---|---|
| `reserved` | Required WAL is within `max_wal_size` (or `wal_keep_size`) — normal |
| `extended` | Beyond `max_wal_size`, but retained because of the slot / `wal_keep_size` |
| `unreserved` | About to be removed at the next checkpoint (the cap is nearly hit); can still recover if the standby reconnects **now** |
| `lost` | Gone; `invalidation_reason` says why (`wal_removed`, `idle_timeout` with `idle_replication_slot_timeout` (18+), …) |

## `hot_standby_feedback` and the slot's `xmin`

If the standby sets `hot_standby_feedback = on`, it periodically reports its oldest running
transaction's xmin to the primary; vacuum on the primary then keeps the rows that standby
queries still need. For a physical slot this is stored in `pg_replication_slots.xmin` (and
`catalog_xmin` is NULL). Without a slot, the feedback is held while the connection lasts.

Cost: a long query on the standby can **bloat the primary**. Trade-off details in
[05](05-hot-standby-and-query-conflicts.md).

## Slot hygiene

```sql
-- retained WAL and whether anything is connected
SELECT slot_name, slot_type, active, active_pid, wal_status,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained,
       safe_wal_size, xmin, invalidation_reason
FROM pg_replication_slots
WHERE slot_type = 'physical'
ORDER BY pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) DESC NULLS LAST;
```

| Rule | Why |
|---|---|
| Set `max_slot_wal_keep_size` (e.g. ≤ 50–70 % of free WAL disk) | Protect the primary |
| Alert on inactive slots and on `retained` | Early warning (topic [06](06-monitoring-and-lag.md)) |
| Drop slots of decommissioned standbys (`pg_drop_replication_slot`) | They pin WAL forever |
| One slot per standby (a slot can have only one active consumer) | Otherwise "replication slot is active for PID …" |
| Use `idle_replication_slot_timeout` (18+) | Auto-invalidate forgotten slots |
| Combine with WAL archiving | A `lost` slot becomes recoverable from the archive |
| Cascading standby: slot lives on its **upstream** standby | Not on the primary ([08](08-cascading-delayed-archive.md)) |
| Mind `max_replication_slots` | Includes logical and temporary slots |

## Slots vs. `wal_keep_size` vs. archive, decision table

| Situation | Choice |
|---|---|
| Single, reliable standby in the same DC | Slot + cap |
| Many standbys / lossy network | Slot + cap + archive |
| You cannot tolerate any chance of the primary filling its disk | `wal_keep_size` + archive, no slot; or slot with a small cap |
| Third-party tool that streams WAL (`pg_receivewal`, Barman) | Dedicated slot per tool; `pg_receivewal -S` |
| Short planned standby downtime | Temporarily raise the cap, or use the archive |

## Temporary slots and tools

- `pg_create_physical_replication_slot('x', false, true)` makes a slot that disappears
  at session end — handy for `pg_basebackup` (it creates one automatically when `-X stream`
  and no `-S` is given).
- `pg_receivewal --slot=archive1 --create-slot` streams WAL to a directory with no
  standby (a "streaming archive") and, by using a slot, gives a no-gap archive.
- `pg_replication_slot_advance()` for physical slots moves `restart_lsn` forward
  (dangerous: any consumer behind it loses its WAL).

## Related parameters, in one table

| Parameter | Default | Role |
|---|---|---|
| `wal_keep_size` | 0 | Always keep this much WAL for standbys |
| `max_slot_wal_keep_size` | -1 (unlimited) | Cap on WAL a slot may retain |
| `idle_replication_slot_timeout` | 0 (off), 18+ | Invalidate slots idle for too long |
| `max_wal_size` / `min_wal_size` | 1GB / 80MB | Checkpoint pacing; `wal_status` thresholds |
| `wal_sender_timeout` | 60 s | Primary drops dead connections |
| `wal_receiver_timeout` | 60 s | Standby drops dead connections |
| `wal_retrieve_retry_interval` | 5 s | Standby retry interval after losing the stream |
| `hot_standby_feedback` | off | Feed xmin to the primary |
| `max_replication_slots`, `max_wal_senders` | 10 / 10 | Capacity |
