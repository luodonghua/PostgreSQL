# UUIDv7 Implementation for Database Partition Migration

This document describes an improved UUIDv7 implementation designed for migrating from a timestamp-partitioned database table to a UUID-partitioned table.

## Background

UUIDv7 is a time-ordered UUID format that provides several advantages over traditional UUIDs, including:
- Chronological ordering for better indexing performance
- Reduced fragmentation in B-tree indexes
- Improved sequential insert performance

This implementation demonstrates a practical approach to using UUIDv7 for database partitioning.

## UUIDv7 Structure

The UUIDv7 format follows this structure:

| Bits    | Bytes | Content                                   |
|---------|-------|-------------------------------------------|
| 0-47    | 0-5   | Milliseconds since Unix epoch (timestamp) |
| 48-51   | 6     | Version (7)                               |
| 52-63   | 6-7   | Random data                               |
| 64-65   | 8     | Variant (2)                               |
| 66-127  | 8-15  | Random data for uniqueness                |

This structure allows for:
1. Chronological ordering based on the timestamp
2. Compliance with the UUID standard format (version 7, variant 2)
3. Sufficient randomness to ensure uniqueness

## PostgreSQL Implementation

### UUIDv7 Generation Functions

```sql
/* Main function to generate a uuidv7 value with millisecond precision */
CREATE FUNCTION uuidv7(timestamptz DEFAULT clock_timestamp()) RETURNS uuid
AS $$
  -- Replace the first 48 bits of a uuidv4 with the current
  -- number of milliseconds since 1970-01-01 UTC
  -- and set the "ver" field to 7 by setting additional bits
  select encode(
    set_bit(
      set_bit(
        overlay(uuid_send(gen_random_uuid()) placing
      substring(int8send((extract(epoch from $1)*1000)::bigint) from 3)
      from 1 for 6),
    52, 1),
      53, 1), 'hex')::uuid;
$$ LANGUAGE sql volatile parallel safe;

/* Function to generate UUIDv7 boundary values for partitioning */
CREATE FUNCTION uuidv7_boundary(timestamptz) RETURNS uuid
AS $$
  /* uuid fields: version=0b0111, variant=0b10 */
  select encode(
    overlay('\x00000000000070008000000000000000'::bytea
      placing substring(int8send(floor(extract(epoch from $1) * 1000)::bigint) from 3)
        from 1 for 6),
    'hex')::uuid;
$$ LANGUAGE sql stable strict parallel safe;
```

## Migration Process

The migration process involves:

1. Creating a new table with UUIDv7-based partitioning
2. Defining partitions based on precise timestamp boundaries using the `uuidv7_boundary` function
3. Migrating data from the original table to the new table with timestamp-aligned UUIDs
4. Maintaining a reference to the original ID

### Creating the New Table

```sql
CREATE TABLE IF NOT EXISTS transactions_new_v1 (
    txn_id UUID PRIMARY KEY DEFAULT uuidv7(),
    amount DECIMAL(15, 2) NOT NULL,
    description TEXT,
    customer_id INTEGER NOT NULL,
    updated_on TIMESTAMP NOT NULL,
    original_txn_id BIGINT -- To maintain reference to original ID
) PARTITION BY RANGE ((txn_id));
```

### Creating Partitions with UTC Timestamps

```sql
-- Create partitions for the new table using the boundary function
-- This ensures precise partition boundaries based on timestamps
CREATE TABLE transactions_new_v1_202401 PARTITION OF transactions_new_v1
    FOR VALUES FROM (uuidv7_boundary('2024-01-01 00:00:00+00')) TO (uuidv7_boundary('2024-02-01 00:00:00+00'));
    
CREATE TABLE transactions_new_v1_202402 PARTITION OF transactions_new_v1
    FOR VALUES FROM (uuidv7_boundary('2024-02-01 00:00:00+00')) TO (uuidv7_boundary('2024-03-01 00:00:00+00'));
    
CREATE TABLE transactions_new_v1_202403 PARTITION OF transactions_new_v1
    FOR VALUES FROM (uuidv7_boundary('2024-03-01 00:00:00+00')) TO (uuidv7_boundary('2024-04-01 00:00:00+00'));
```

### Migration Function

```sql
CREATE OR REPLACE FUNCTION migrate_transactions()
RETURNS INTEGER AS $$
DECLARE
    v_count INTEGER := 0;
    v_rec RECORD;
BEGIN
    FOR v_rec IN SELECT * FROM transactions_original ORDER BY txn_id
    LOOP
        INSERT INTO transactions_new_v1 (
            txn_id,    
            amount, 
            description, 
            customer_id, 
            updated_on, 
            original_txn_id
        ) VALUES (
            uuidv7(v_rec.updated_on),  -- Generate UUIDv7 based on the original timestamp
            v_rec.amount,
            v_rec.description,
            v_rec.customer_id,
            v_rec.updated_on,
            v_rec.txn_id
        );
        
        v_count := v_count + 1;
    END LOOP;
    
    RETURN v_count;
END;
$$ LANGUAGE plpgsql;
```

## Key Improvements

This implementation offers several advantages:

1. **Timestamp-Aligned UUIDs**: The `uuidv7(timestamptz)` function allows generating UUIDs based on specific timestamps
2. **Precise Partition Boundaries**: The `uuidv7_boundary()` function creates exact partition boundaries aligned with calendar dates
3. **Proper Data Distribution**: Records are distributed to partitions based on their original timestamps
4. **Simplified Partition Management**: Partition boundaries are defined using human-readable dates with explicit UTC timezone
5. **Better Performance**: Efficient UUID generation with binary operations

## Benefits

This UUIDv7 approach provides several benefits:

1. **Time-Ordered Keys**: UUIDs are ordered chronologically, improving index performance
2. **Partition Compatibility**: Works with range partitioning based on UUID values
3. **Original ID Preservation**: Maintains a reference to the original ID for backward compatibility
4. **No Sequence Dependencies**: Distributed systems can generate UUIDs without coordination
5. **Future-Proof**: Aligns with the emerging UUIDv7 standard
6. **Timestamp Preservation**: Original timestamps are embedded in the UUIDs

## ID Mapping

To facilitate the transition, a view is created to map between original and new IDs:

```sql
CREATE OR REPLACE VIEW transaction_id_mapping AS
SELECT 
    o.txn_id AS original_txn_id,
    n.txn_id AS new_txn_id,
    o.updated_on
FROM 
    transactions_original o
JOIN 
    transactions_new_v1 n ON o.txn_id = n.original_txn_id;
```

## Partition Inspection

To verify which partition each record is stored in:

```sql
SELECT
    txn_id,
    amount,
    updated_on,
    tableoid::regclass AS partition_name,
    original_txn_id
FROM
    transactions_new_v1
ORDER BY
    updated_on;
```

## Usage Example

```sql
-- Execute the migration
SELECT migrate_transactions();

-- Verify the migration
SELECT 'Original table count: ' || COUNT(*)::TEXT AS count FROM transactions_original;
SELECT 'New table count: ' || COUNT(*)::TEXT AS count FROM transactions_new_v1;

-- Sample query to show the data in both tables
SELECT 'Original' AS table_name, txn_id::TEXT, amount, updated_on FROM transactions_original
UNION ALL
SELECT 'New' AS table_name, txn_id::TEXT, amount, updated_on FROM transactions_new_v1
ORDER BY table_name, updated_on;

-- Query the mapping view
SELECT * FROM transaction_id_mapping;
```

This implementation provides a robust foundation for UUIDv7-based partitioning strategies in PostgreSQL databases.
