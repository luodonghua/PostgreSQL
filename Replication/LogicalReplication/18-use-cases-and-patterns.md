# 18 — Use Cases and Patterns

Level: L400. Native PostgreSQL only; tested on 18.6. Anything newer than PG 18 is
marked ⚠️ non-GA. Amazon RDS / Aurora specifics (privileges, parameters, failover and DR
measured on AWS) are in [topic 20](20-amazon-rds-and-aurora.md). Moving tables between
subscriptions (split/merge) is in [topic 03](03-subscriptions.md#moving-a-table-between-subscriptions-without-re-copying-split-and-merge).

## 1. Use cases, and which features they need

| Use case | Shape | Key features | Watch out for |
|---|---|---|---|
| **Zero-downtime upgrade / migration** | Old → new cluster | pub/sub, `copy_data`, sequences at cut-over | [17](17-upgrades-and-migrations.md) |
| **Reporting / analytics replica** | Prod → separate, indexed differently | Subscriber may have **extra indexes, extra columns, partitioning** | Apply speed; subscriber-only unique indexes |
| **Selective replication** (some tables, some columns/rows) | Prod → edge/partner | Row filters, column lists | Identity columns must be in the lists ([02](02-publications.md)) |
| **Data consolidation** | N sources → one warehouse DB | One subscription per source, distinct schemas | Name clash; PK collisions → use per-source schemas |
| **Multi-region read copies** | Primary region → others | Async; `streaming=parallel` | WAN lag; slot retention on WAN outage |
| **CDC to Kafka/streams** | PG → Debezium/other | `pgoutput` or `wal2json`, slot per connector | Idle-DB slot lag; schema evolution (below) |
| **Cache/search invalidation** | PG → worker | `pg_recvlogical` or logical messages | At-least-once delivery → idempotent consumers |
| **Audit / event capture** | PG → log | `pg_logical_emit_message`, `test_decoding` | Not a security audit log |
| **Bidirectional / active-active (limited)** | A ⇄ B | `origin = none`, disjoint keys | [17](17-upgrades-and-migrations.md), [12](12-conflicts-and-error-handling.md) |
| **Blue/green deployments** | Blue → green | Logical replication under the hood on managed services | [Topic 20 §10](20-amazon-rds-and-aurora.md#10-bluegreen-deployments) |
| **Online table rewrite / repartition** | Same cluster or new cluster | Different subscriber layout | Cut-over per table |

## 2. CDC with external consumers (Debezium and friends)

External consumers are not the built-in subscriber; they consume the slot with
the streaming protocol (`pg_recvlogical` style) and carry their own offsets.

Key points:

- **Plugin**: `pgoutput` (built-in, no extension needed, supports publications and
  row filters/column lists) is the default choice for modern Debezium.
  `wal2json` outputs JSON but is an extra package that not all managed services
  provide ([06](06-logical-decoding.md)).
- **One slot per connector**; the connector owns it. If you delete the connector,
  delete the slot.
- **Schema evolution** arrives as a new `Relation` message
  ([08](08-pgoutput-protocol.md)) — the connector derives the new schema from it. It
  does not receive DDL text. Columns dropped/added show up in the next event.
- **Delivery is at-least-once.** After a reconnect you can see events again from
  `confirmed_flush_lsn`; consumers must be idempotent (use LSN + xid + key).
- **Deletes and old values**: set `REPLICA IDENTITY FULL` (or use the PK) depending on whether
  consumers need "before" images ([09](09-replica-identity.md)).
- **Initial snapshot**: connectors read the table with a consistent snapshot of the slot, then
  stream — the same mechanism as [tablesync](10-initial-sync-tablesync.md).
- **Large transactions**: connectors that don't support streaming in-progress transactions
  see the whole transaction only at commit; spill costs apply ([07](07-reorderbuffer-and-large-transactions.md)).
- **Logical messages** (`pg_logical_emit_message(true, 'outbox', payload)`) let you
  implement the **transactional outbox pattern** without an outbox table: the message
  commits atomically with your business change and appears in the stream at that position
  (verified in `test_decoding` output, [06](06-logical-decoding.md)). Needs the consumer to enable
  messages (`messages=true` for pgoutput).

### The idle-database trap (tested, 18.6)

A slot belongs to **one database**, but WAL is cluster-wide. If the slot's database is
quiet while another database on the same cluster is busy, an external consumer that only
confirms positions when it receives *changes for its own database* never advances.

Experiment: databases `quiet` (published table) and `busy` (120 000 junk rows inserted);
a built-in subscription and a raw slot (`raw`, nobody reading) both on `quiet`:

| Time | Slot | `retained` WAL | `unconfirmed` |
|---|---|---|---|
| t+0 | `s` (built-in subscription) | 65 MB | 13 MB |
| t+0 | `raw` (no consumer) | 65 MB | 65 MB |
| t+20 s | `s` | **56 bytes** | 0 |
| t+20 s | `raw` | **65 MB** | 65 MB |
| after `pg_replication_slot_advance('raw', pg_current_wal_lsn())` + checkpoint | `raw` | 264 bytes | 0 |

- The built-in subscriber recovers on its own: the walsender sends keepalives with the
  current WAL position and the apply worker confirms them (the lag cleared once
  the next running-transactions record arrived, within ~15–20 s).
- A consumer that **never reads/confirms** (a forgotten slot, or a connector that only
  confirms on data events) pins WAL indefinitely.
- Cure for external consumers: a **heartbeat** — periodically write a row to a table in
  the slot's database (Debezium: `heartbeat.interval.ms` plus a heartbeat action query)
  so there is always a recent change to confirm, or ensure the client sends standby status
  updates for keepalive positions. Alert on `unconfirmed` bytes per slot ([14](14-monitoring-and-troubleshooting.md)).

## 3. Reference patterns

### 3.1 Reporting replica with different indexes

```sql
-- subscriber: same table, extra index and a derived column kept by the app/trigger
CREATE INDEX orders_created_idx ON orders (created_at);
ALTER TABLE orders ADD COLUMN created_date date GENERATED ALWAYS AS (created_at::date) STORED;
```

Replicated columns are matched by name; extra columns/indexes are fine ([13](13-limitations.md)).
Keep subscriber indexes lean (single apply worker).

### 3.2 Sharded consolidation

Source DB `eu` and `us` each publish `orders`. Subscriber table names must match the
publisher's schema-qualified names, so two sources with the same `public.orders` cannot
land in one table of one database without clashing. Options: replicate each source into a
**separate target database** and union with `postgres_fdw`/views, or give each source distinct
table names/schemas at the origin, or use `publish_via_partition_root` with a partitioned
target whose partition key includes a source id ([02](02-publications.md)).

### 3.3 Fan-out with filters

One publisher, many subscribers, each with its own publication and row filter
(`WHERE (tenant_id IN (…))`): each subscriber has its own slot ([05](05-replication-slots.md))
and each walsender decodes independently — CPU on the publisher scales with
the number of subscribers.

### 3.4 Delayed replica

Not built in: `min_apply_delay` is **not** a subscription option in 18.6 (tested: `ERROR: unrecognized
subscription parameter: "min_apply_delay"`) and it is absent from the 20devel source I read. Options:
pause with `ALTER SUBSCRIPTION … DISABLE` (WAL accumulates in the slot — watch disk), or use
a physical standby with `recovery_min_apply_delay` for a delayed copy.

## 4. When *not* to use logical replication

- You need an identical hot standby → physical replication.
- You need DDL, sequences, large objects, roles replicated automatically → physical or a
  tool that does it.
- Strict cross-table atomic visibility on the replica → single subscription or physical.
- Heavy conflict-prone multi-writer workloads with automatic resolution → a purpose-built
  multi-master product.
- Very high-rate small transactions into one subscription where one apply worker is the
  bottleneck and cannot be split.
