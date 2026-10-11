# UUIDv7 for Partition Migration

Generating [UUIDv7](https://www.rfc-editor.org/rfc/rfc9562) (time-ordered UUID)
values in PostgreSQL and using them to migrate a timestamp-partitioned table to
a UUID-partitioned one.

UUIDv7 encodes a millisecond Unix timestamp in its leading 48 bits, so values
sort chronologically. That gives time-ordered inserts the B-tree locality of a
sequence while keeping the uniqueness of a UUID — reducing index fragmentation
and improving sequential insert performance.

This note has two parts:

1. **Baseline** — a standard UUIDv7 generator and a partition-boundary helper.
2. **Advanced** — a `custom_uuidv7()` that also *embeds the original row ID* in
   the UUID, with binary ops, extraction functions, indexing, and a migration.

Runnable demos accompany each part (see [Files](#files)).

## UUIDv7 bit layout

Standard UUIDv7:

| Bits    | Bytes | Content                                   |
|---------|-------|-------------------------------------------|
| 0-47    | 0-5   | Milliseconds since Unix epoch (timestamp) |
| 48-51   | 6     | Version (7)                               |
| 52-63   | 6-7   | Random data                               |
| 64-65   | 8     | Variant (2)                               |
| 66-127  | 8-15  | Random data for uniqueness                |

The **advanced** variant repurposes part of the random tail to carry the source
row's ID:

| Bits    | Bytes | Content                              |
|---------|-------|--------------------------------------|
| 66-111  | 8-13  | Original ID (e.g. `bigserial` value) |
| 112-127 | 14-15 | Random data for uniqueness           |

## Part 1 — Baseline generation

Pure-SQL `uuidv7()` built on `gen_random_uuid()`, overlaying the timestamp into
the first 6 bytes and setting the version/variant bits, plus a
`uuidv7_boundary()` helper that computes the partition boundary UUID for a given
timestamp.

```sql
/* Generate a uuidv7 value with millisecond precision */
CREATE FUNCTION uuidv7(timestamptz DEFAULT clock_timestamp()) RETURNS uuid
AS $$
  -- Replace the first 48 bits of a uuidv4 with ms since 1970-01-01 UTC
  -- and set the version field to 7.
  select encode(
    set_bit(
      set_bit(
        overlay(uuid_send(gen_random_uuid()) placing
          substring(int8send((extract(epoch from $1)*1000)::bigint) from 3)
          from 1 for 6),
        52, 1),
      53, 1), 'hex')::uuid;
$$ LANGUAGE sql volatile parallel safe;

/* Partition boundary UUID for a timestamp (version=7, variant=2) */
CREATE FUNCTION uuidv7_boundary(timestamptz) RETURNS uuid
AS $$
  select encode(
    overlay('\x00000000000070008000000000000000'::bytea
      placing substring(int8send(floor(extract(epoch from $1) * 1000)::bigint) from 3)
      from 1 for 6),
    'hex')::uuid;
$$ LANGUAGE sql stable strict parallel safe;
```

### Migrate a table to UUIDv7 range partitions

```sql
CREATE TABLE IF NOT EXISTS transactions_new (
    txn_id UUID PRIMARY KEY DEFAULT uuidv7(),
    amount DECIMAL(15, 2) NOT NULL,
    description TEXT,
    customer_id INTEGER NOT NULL,
    updated_on TIMESTAMP NOT NULL,
    original_txn_id BIGINT          -- keep a reference to the original ID
) PARTITION BY RANGE ((txn_id));

-- Partitions bounded by calendar months, using the boundary helper
CREATE TABLE transactions_new_202401 PARTITION OF transactions_new
    FOR VALUES FROM (uuidv7_boundary('2024-01-01 00:00:00+00')) TO (uuidv7_boundary('2024-02-01 00:00:00+00'));
CREATE TABLE transactions_new_202402 PARTITION OF transactions_new
    FOR VALUES FROM (uuidv7_boundary('2024-02-01 00:00:00+00')) TO (uuidv7_boundary('2024-03-01 00:00:00+00'));
CREATE TABLE transactions_new_202403 PARTITION OF transactions_new
    FOR VALUES FROM (uuidv7_boundary('2024-03-01 00:00:00+00')) TO (uuidv7_boundary('2024-04-01 00:00:00+00'));
```

The migration generates each new UUID from the **original row's timestamp**
(`uuidv7(v_rec.updated_on)`) so rows land in the correct time-based partition,
while keeping `original_txn_id` for backward reference. A
`transaction_id_mapping` view then maps old ID ↔ new UUID, and
`tableoid::regclass` reveals which partition each row landed in.

## Part 2 — Advanced: embed the original ID in the UUID

`custom_uuidv7(timestamp, original_id)` keeps the timestamp in the first 48 bits
and writes the source `bigserial` ID into bits 66-111, so the original key is
recoverable directly from the UUID — no side table needed. Two implementations
are provided: a readable PL/pgSQL reference and a faster pure-SQL version.

```sql
-- Optimized SQL version (timestamp + optional embedded id)
CREATE OR REPLACE FUNCTION custom_uuidv7(
    p_timestamp TIMESTAMP DEFAULT clock_timestamp(),
    p_original_id BIGINT DEFAULT NULL)
RETURNS UUID AS $$
  WITH params AS (
    SELECT
      (EXTRACT(EPOCH FROM p_timestamp AT TIME ZONE 'UTC')*1000)::bigint AS ms,
      CASE
        WHEN p_original_id > 1099511627775 THEN 1099511627775::BIGINT  -- 2^40-1 cap
        WHEN p_original_id IS NULL THEN 0::BIGINT
        ELSE p_original_id
      END AS id
  ),
  parts AS (
    SELECT lpad(to_hex((SELECT ms FROM params)), 12, '0') AS time_hex,
           lpad(to_hex((SELECT id FROM params)), 10, '0') AS id_hex
  ),
  rand_parts AS (
    SELECT substring(encode(gen_random_bytes(10),'hex') FROM 1 FOR 3) AS rand1,
           substring(encode(gen_random_bytes(10),'hex') FROM 1 FOR 3) AS rand2,
           substring(encode(gen_random_bytes(10),'hex') FROM 1 FOR 2) AS rand3
  )
  SELECT (
    substring((SELECT time_hex FROM parts) FROM 1 FOR 8) || '-' ||
    substring((SELECT time_hex FROM parts) FROM 9 FOR 4) || '-' ||
    '7' || (SELECT rand1 FROM rand_parts) || '-' ||
    '8' || (SELECT rand2 FROM rand_parts) || '-' ||
    substring((SELECT id_hex FROM parts) FROM 1 FOR 10) ||
    (SELECT rand3 FROM rand_parts)
  )::UUID;
$$ LANGUAGE sql VOLATILE PARALLEL SAFE;
```

Extraction functions read the embedded values back out:

```sql
CREATE OR REPLACE FUNCTION extract_timestamp_from_uuid(p_uuid UUID)
RETURNS TIMESTAMP AS $$
  SELECT to_timestamp(
    (('x' || substring(replace(p_uuid::TEXT,'-','') FROM 1 FOR 12))::bit(48)::bigint) / 1000.0
  ) AT TIME ZONE 'UTC';
$$ LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE;

CREATE OR REPLACE FUNCTION extract_original_id_from_uuid(p_uuid UUID)
RETURNS BIGINT AS $$
  SELECT ('x' || substring(replace(p_uuid::TEXT,'-','') FROM 21 FOR 10))::bit(40)::bigint;
$$ LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE;
```

### Indexing and query optimization

Index the *extracted* values when you filter on them, and use UUID ranges for
partition elimination:

```sql
CREATE INDEX idx_txn_timestamp   ON transactions_new (extract_timestamp_from_uuid(txn_id));
CREATE INDEX idx_txn_original_id ON transactions_new (extract_original_id_from_uuid(txn_id));

-- Partition elimination by UUID range instead of scanning on an extracted value
SELECT * FROM transactions_new
WHERE txn_id BETWEEN
  custom_uuidv7('2024-01-01'::timestamp, 0) AND
  custom_uuidv7('2024-01-31 23:59:59.999'::timestamp, 1099511627775);
```

A `transaction_embedded_data` view exposes `extract_timestamp_from_uuid()` /
`extract_original_id_from_uuid()` as columns for easy inspection.

### Keeping the old table in sync during migration (CDC-style)

For a live cutover you can mirror writes from the source table into the new
UUID-partitioned table with a trigger that calls `custom_uuidv7(updated_on,
txn_id)`. See the sync scripts in [Files](#files).

## Key points

- **Time-ordered keys**: UUIDv7 sorts chronologically, giving sequence-like index locality without a central sequence.
- **Partition compatibility**: works directly with `PARTITION BY RANGE ((txn_id))` using `uuidv7_boundary()` for calendar-aligned boundaries.
- **Original ID preservation**: the advanced variant embeds the source ID (up to 2^40−1) so no mapping table is required; a mapping view is still handy during transition.
- **Timezone correctness**: timestamps are converted at UTC explicitly to keep boundaries and extraction consistent.

## Files

| File | What it is |
|---|---|
| [partition_migration_demo_v1.sql](partition_migration_demo_v1.sql) | Runnable demo for **Part 1** (baseline `uuidv7()` + boundary + migration) |
| [partition_migration_demo_v2.sql](partition_migration_demo_v2.sql) | Runnable demo for **Part 2** (`custom_uuidv7()` with embedded ID) |
| [generate_test_data_transactions.sql](generate_test_data_transactions.sql) | Generates test transactions across three monthly partitions |
| [transactions_sync_trigger_example.sql](transactions_sync_trigger_example.sql) | Trigger that mirrors INSERT/UPDATE/DELETE from the source table using `custom_uuidv7()` |

> Note: the earlier `partition_migration_demo_v3.sql` was byte-identical to v2
> and has been removed to avoid duplication.
