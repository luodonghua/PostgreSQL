# UUIDv7 for Partition Migration

Generating [UUIDv7](https://www.rfc-editor.org/rfc/rfc9562) (time-ordered UUID)
values in PostgreSQL and using them to migrate a timestamp-partitioned table to
a UUID-partitioned one. UUIDv7 encodes a millisecond Unix timestamp in its
leading 48 bits, so values sort chronologically — giving time-ordered inserts
B-tree locality while keeping UUID uniqueness.

## Contents

- [uuidv7.md](uuidv7.md) — the write-up: UUIDv7 bit layout, a baseline `uuidv7()` generator + `uuidv7_boundary()` for partitioning, and an advanced `custom_uuidv7()` that embeds the original row ID (with extraction functions, indexing, and query optimization).

### Runnable demo scripts

- [partition_migration_demo_v1.sql](partition_migration_demo_v1.sql) — baseline `uuidv7()` + boundary + migration.
- [partition_migration_demo_v2.sql](partition_migration_demo_v2.sql) — advanced `custom_uuidv7()` with embedded original ID.
- [generate_test_data_transactions.sql](generate_test_data_transactions.sql) — generates test transactions across three monthly partitions.
- [transactions_sync_trigger_example.sql](transactions_sync_trigger_example.sql) — trigger that mirrors INSERT/UPDATE/DELETE from the source table into the UUID-partitioned table using `custom_uuidv7()`.

## Conventions

The explanatory write-up lives in `uuidv7.md`; the `.sql` files are runnable
demos you can execute directly.
