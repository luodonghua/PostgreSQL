# UUIDv7 for Partition Migration

Scripts and notes for generating [UUIDv7](https://www.rfc-editor.org/rfc/rfc9562)
(time-ordered UUID) values in PostgreSQL and using them to migrate a
timestamp-partitioned table to a UUID-partitioned one.

UUIDv7 encodes a millisecond Unix timestamp in its leading 48 bits, so values
sort chronologically. That gives time-ordered inserts the B-tree locality of a
sequence while keeping the uniqueness of a UUID — reducing index fragmentation
and improving sequential insert performance.

## Versions

The folder captures three iterations of the approach. Each `uuidv7_vN.md` is the
write-up; each `partition_migration_demo_vN.sql` is the runnable demo.

### v1 — baseline SQL generation
- [uuidv7_v1.md](uuidv7_v1.md) · [partition_migration_demo_v1.sql](partition_migration_demo_v1.sql)
- Pure-SQL `uuidv7()` built on `gen_random_uuid()`, overlaying the timestamp
  into the first 6 bytes and setting the version/variant bits.
- Adds a `uuidv7_boundary()` helper to compute partition boundary UUIDs from a
  timestamp.
- Standard UUIDv7 layout: timestamp + random data.

### v2 — binary operations + embedded original ID
- [uuidv7_v2.md](uuidv7_v2.md) · [partition_migration_demo_v2.sql](partition_migration_demo_v2.sql)
- `custom_uuidv7(timestamp, original_id)` embeds the source row's `bigserial`
  ID (bits 66-111) alongside the timestamp, so the original key is recoverable
  from the UUID.
- Provides both a PL/pgSQL reference implementation and a faster SQL version,
  plus indexing strategies for the extracted values and explicit UTC handling.

### v3 — same design as v2, with CDC-style sync demo
- [uuidv7_v3.md](uuidv7_v3.md) · [partition_migration_demo_v3.sql](partition_migration_demo_v3.sql)
- The v3 write-up and migration demo are identical to v2; v3 adds two extra
  scripts that show how to keep an old table in sync with the new
  UUID-partitioned one during a migration:
  - [generate_test_data_transactions_new_v3.sql](generate_test_data_transactions_new_v3.sql)
    — generates test transactions across three monthly partitions.
  - [transactions_new_v3_trigger_example.sql](transactions_new_v3_trigger_example.sql)
    — a trigger that calls `custom_uuidv7(updated_on, txn_id)` to mirror
    INSERT/UPDATE/DELETE from the source table into `transactions_new_v3`.

## Suggested reading order

Start with v1 to understand the UUIDv7 bit layout, move to v2 for the
production-oriented implementation that embeds the original ID, then v3 for the
live-sync trigger pattern used during an actual migration.
