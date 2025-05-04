# Basic UUIDv7 Implementation for Database Partition Migration

This document describes a basic UUIDv7 implementation designed for migrating from a timestamp-partitioned database table to a UUID-partitioned table.

## Background

UUIDv7 is a time-ordered UUID format that provides several advantages over traditional UUIDs, including:
- Chronological ordering for better indexing performance
- Reduced fragmentation in B-tree indexes
- Improved sequential insert performance

This implementation demonstrates a basic approach to using UUIDv7 for database partitioning.

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

### Basic UUIDv7 Generation Function

```sql
CREATE OR REPLACE FUNCTION gen_uuidv7()
RETURNS UUID AS $$
DECLARE
    v_time BYTEA;
    v_random BYTEA;
    v_result UUID;
BEGIN
    -- Get current timestamp in milliseconds since Unix epoch
    v_time := E'\\x' || lpad(to_hex((extract(epoch FROM clock_timestamp()) * 1000)::bigint), 16, '0');
    
    -- Generate 10 random bytes
    v_random := gen_random_bytes(10);
    
    -- Combine with version bits (7) and variant bits (2)
    v_result := (
        v_time ||
        E'\\x70' || -- Set version to 7
        substring(v_random FROM 1 FOR 9) ||
        E'\\x' || lpad(to_hex((get_byte(v_random, 9) & 63) | 128), 2, '0') -- Set variant to 2
    )::UUID;
    
    RETURN v_result;
END;
$$ LANGUAGE plpgsql;
```

## Migration Process

The migration process involves:

1. Creating a new table with UUIDv7-based partitioning
2. Defining partitions based on approximate UUIDv7 ranges
3. Migrating data from the original table to the new table
4. Maintaining a reference to the original ID

### Creating the New Table

```sql
CREATE TABLE IF NOT EXISTS transactions_new (
    txn_id UUID PRIMARY KEY DEFAULT gen_uuidv7(),
    amount DECIMAL(15, 2) NOT NULL,
    description TEXT,
    customer_id INTEGER NOT NULL,
    updated_on TIMESTAMP NOT NULL,
    original_txn_id BIGINT -- To maintain reference to original ID
) PARTITION BY RANGE ((txn_id::text));
```

### Creating Partitions

Since UUIDv7 is time-ordered, we can create partitions that roughly correspond to time periods:

```sql
-- For January 2024 (approximate UUIDv7 range)
CREATE TABLE transactions_new_202401 PARTITION OF transactions_new
    FOR VALUES FROM ('017aa000-0000-7000-8000-000000000000') TO ('017b1000-0000-7000-8000-000000000000');
    
-- For February 2024 (approximate UUIDv7 range)
CREATE TABLE transactions_new_202402 PARTITION OF transactions_new
    FOR VALUES FROM ('017b1000-0000-7000-8000-000000000000') TO ('017b8000-0000-7000-8000-000000000000');
    
-- For March 2024 (approximate UUIDv7 range)
CREATE TABLE transactions_new_202403 PARTITION OF transactions_new
    FOR VALUES FROM ('017b8000-0000-7000-8000-000000000000') TO ('017bf000-0000-7000-8000-000000000000');
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
        INSERT INTO transactions_new (
            amount, 
            description, 
            customer_id, 
            updated_on, 
            original_txn_id
        ) VALUES (
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

## Benefits

This basic UUIDv7 approach provides several benefits:

1. **Time-Ordered Keys**: UUIDs are ordered chronologically, improving index performance
2. **Partition Compatibility**: Works with range partitioning based on UUID text representation
3. **Original ID Preservation**: Maintains a reference to the original ID for backward compatibility
4. **No Sequence Dependencies**: Distributed systems can generate UUIDs without coordination
5. **Future-Proof**: Aligns with the emerging UUIDv7 standard

## Limitations

- Partition boundaries are approximate and may need adjustment
- Original ID is stored as a separate column, requiring additional storage
- No direct embedding of timestamp or original ID in the UUID structure
- Manual mapping required between original and new IDs

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
    transactions_new n ON o.txn_id = n.original_txn_id;
```

## Usage Example

```sql
-- Execute the migration
SELECT migrate_transactions();

-- Verify the migration
SELECT 'Original table count: ' || COUNT(*)::TEXT AS count FROM transactions_original;
SELECT 'New table count: ' || COUNT(*)::TEXT AS count FROM transactions_new;

-- Sample query to show the data in both tables
SELECT 'Original' AS table_name, txn_id, amount, updated_on FROM transactions_original
UNION ALL
SELECT 'New' AS table_name, txn_id::TEXT, amount, updated_on FROM transactions_new
ORDER BY table_name, updated_on;

-- Query the mapping view
SELECT * FROM transaction_id_mapping;
```

This basic implementation serves as a foundation for more advanced UUIDv7-based partitioning strategies, which are explored in subsequent versions.
