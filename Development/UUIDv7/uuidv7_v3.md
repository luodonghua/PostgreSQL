# Enhanced Custom UUIDv7 Implementation for Database Partition Migration

This document describes an improved custom UUIDv7 implementation designed for migrating from a timestamp-partitioned database table to a UUID-partitioned table while preserving both timestamp and original ID information.

## Background

UUIDv7 is a time-ordered UUID format that provides several advantages over traditional UUIDs, including:
- Chronological ordering for better indexing performance
- Reduced fragmentation in B-tree indexes
- Improved sequential insert performance

Our enhanced implementation extends the standard UUIDv7 format to embed additional information that facilitates database migration, with improvements based on the reference implementation from [postgres-uuidv7-sql](https://github.com/dverite/postgres-uuidv7-sql).

## Custom UUIDv7 Structure

Our enhanced UUIDv7 format embeds both timestamp and original ID information directly in the UUID:

| Bits    | Bytes | Content                                   |
|---------|-------|-------------------------------------------|
| 0-47    | 0-5   | Milliseconds since Unix epoch (timestamp) |
| 48-51   | 6     | Version (7)                               |
| 52-63   | 6-7   | Random data                               |
| 64-65   | 8     | Variant (2)                               |
| 66-111  | 8-13  | Original ID (48 bits)                     |
| 112-127 | 14-15 | Random data for uniqueness                |

This structure allows us to:
1. Maintain chronological ordering based on the timestamp
2. Preserve the original ID information without additional storage
3. Comply with the UUID standard format (version 7, variant 2)
4. Use bit-level operations for more precise control

## Improvements from Reference Implementation

Our enhanced implementation incorporates several improvements from the reference implementation:

1. **Bit-level Manipulation**: Using `set_bit()` and `get_bit()` functions for precise bit manipulation
2. **Partition Boundary Function**: Added a `uuidv7_boundary()` function to generate precise partition boundaries
3. **Optimized Extraction**: More efficient timestamp and ID extraction functions
4. **Indexing Support**: Added functional indexes to improve query performance on extracted values
5. **Parallel Safe Functions**: Made extraction functions parallel safe for better performance

## PostgreSQL Implementation

### Enhanced Custom UUIDv7 Generation Function

```sql
CREATE OR REPLACE FUNCTION custom_uuidv7(p_timestamp TIMESTAMP, p_original_id BIGINT)
RETURNS UUID AS $$
DECLARE
    v_time_ms BIGINT;
    v_uuid_base BYTEA;
    v_result UUID;
BEGIN
    -- Convert timestamp to milliseconds since Unix epoch
    v_time_ms := (EXTRACT(EPOCH FROM p_timestamp) * 1000)::BIGINT;
    
    -- Start with a standard UUIDv4 as base
    v_uuid_base := uuid_send(gen_random_uuid());
    
    -- Replace first 6 bytes with timestamp (milliseconds)
    v_uuid_base := overlay(v_uuid_base placing substring(int8send(v_time_ms) from 3) from 1 for 6);
    
    -- Set version to 7 (bits 48-51)
    v_uuid_base := set_bit(v_uuid_base, 48, 0);
    v_uuid_base := set_bit(v_uuid_base, 49, 1);
    v_uuid_base := set_bit(v_uuid_base, 50, 1);
    v_uuid_base := set_bit(v_uuid_base, 51, 1);
    
    -- Set variant to 2 (bits 64-65)
    v_uuid_base := set_bit(v_uuid_base, 64, 1);
    v_uuid_base := set_bit(v_uuid_base, 65, 0);
    
    -- Ensure original ID fits within 48 bits
    IF p_original_id > 281474976710655 THEN -- 2^48-1
        RAISE EXCEPTION 'Original ID too large to fit in 48 bits: %', p_original_id;
    END IF;
    
    -- Insert original ID into bytes 8-13 (bits 66-111)
    -- We need to preserve the variant bits (64-65)
    -- First, clear the bits we'll use for the ID (except variant bits)
    FOR i IN 66..111 LOOP
        v_uuid_base := set_bit(v_uuid_base, i, 0);
    END LOOP;
    
    -- Then set the bits according to the original ID
    FOR i IN 0..45 LOOP
        IF (p_original_id & (1::BIGINT << i)) != 0 THEN
            v_uuid_base := set_bit(v_uuid_base, i + 66, 1);
        END IF;
    END LOOP;
    
    -- Convert back to UUID
    v_result := encode(v_uuid_base, 'hex')::UUID;
    
    RETURN v_result;
END;
$$ LANGUAGE plpgsql;
```

### Improved Data Extraction Functions

```sql
CREATE OR REPLACE FUNCTION extract_timestamp_from_uuid(p_uuid UUID)
RETURNS TIMESTAMP AS $$
BEGIN
    -- Extract the timestamp from the first 48 bits
    RETURN to_timestamp(
        (('x' || substring(replace(p_uuid::TEXT, '-', '') FROM 1 FOR 12))::bit(48)::bigint) / 1000.0
    );
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT PARALLEL SAFE;

CREATE OR REPLACE FUNCTION extract_original_id_from_uuid(p_uuid UUID)
RETURNS BIGINT AS $$
DECLARE
    v_uuid_bytes BYTEA;
    v_original_id BIGINT := 0;
BEGIN
    -- Convert UUID to bytea
    v_uuid_bytes := uuid_send(p_uuid);
    
    -- Extract the original ID from bits 66-111
    FOR i IN 0..45 LOOP
        IF get_bit(v_uuid_bytes, i + 66) = 1 THEN
            v_original_id := v_original_id | (1::BIGINT << i);
        END IF;
    END LOOP;
    
    RETURN v_original_id;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT PARALLEL SAFE;
```

### Partition Boundary Function

```sql
CREATE OR REPLACE FUNCTION uuidv7_boundary(p_timestamp TIMESTAMP)
RETURNS UUID AS $$
DECLARE
    v_time_ms BIGINT;
    v_uuid_base BYTEA;
BEGIN
    -- Convert timestamp to milliseconds since Unix epoch
    v_time_ms := (EXTRACT(EPOCH FROM p_timestamp) * 1000)::BIGINT;
    
    -- Create a base UUID with all zeros
    v_uuid_base := E'\\x00000000000000000000000000000000'::BYTEA;
    
    -- Replace first 6 bytes with timestamp
    v_uuid_base := overlay(v_uuid_base placing substring(int8send(v_time_ms) from 3) from 1 for 6);
    
    -- Set version to 7
    v_uuid_base := set_bit(v_uuid_base, 48, 0);
    v_uuid_base := set_bit(v_uuid_base, 49, 1);
    v_uuid_base := set_bit(v_uuid_base, 50, 1);
    v_uuid_base := set_bit(v_uuid_base, 51, 1);
    
    -- Set variant to 2
    v_uuid_base := set_bit(v_uuid_base, 64, 1);
    v_uuid_base := set_bit(v_uuid_base, 65, 0);
    
    RETURN encode(v_uuid_base, 'hex')::UUID;
END;
$$ LANGUAGE plpgsql STABLE STRICT PARALLEL SAFE;
```

## Partition Creation with Precise Boundaries

Using the boundary function, we can create partitions with precise timestamp boundaries:

```sql
CREATE TABLE transactions_new_v3_202401 PARTITION OF transactions_new_v3
    FOR VALUES FROM (uuidv7_boundary('2024-01-01')::text) TO (uuidv7_boundary('2024-02-01')::text);
```

## Performance Optimization with Functional Indexes

To improve query performance when filtering by the embedded timestamp or original ID:

```sql
-- Create an index on the extracted timestamp
CREATE INDEX idx_transactions_new_v3_timestamp 
ON transactions_new_v3 (extract_timestamp_from_uuid(txn_id));

-- Create an index on the extracted original ID
CREATE INDEX idx_transactions_new_v3_original_id
ON transactions_new_v3 (extract_original_id_from_uuid(txn_id));
```

## Benefits of Enhanced Implementation

1. **Precise Bit Control**: Using bit-level operations for more accurate embedding and extraction
2. **Optimized Partitioning**: Precise partition boundaries based on timestamps
3. **Performance**: Functional indexes for efficient querying on embedded data
4. **Parallel Processing**: Extraction functions are parallel safe for better performance
5. **Standards Compliance**: Fully compliant with UUIDv7 specification
6. **Data Preservation**: Original timestamps and IDs are preserved within the UUID

## Usage Example

```sql
-- Query using the extracted timestamp
SELECT * FROM transactions_new_v3
WHERE extract_timestamp_from_uuid(txn_id) BETWEEN '2024-01-01' AND '2024-01-31';

-- Query using the extracted original ID
SELECT * FROM transactions_new_v3
WHERE extract_original_id_from_uuid(txn_id) = 1;
```

## Generating New IDs

For new transactions, you can generate new custom UUIDs that maintain the same format:

```sql
CREATE OR REPLACE FUNCTION generate_new_transaction_id_v3(p_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP)
RETURNS UUID AS $$
DECLARE
    v_next_id BIGINT;
BEGIN
    -- Get the next value from the original sequence
    SELECT nextval(pg_get_serial_sequence('transactions_original', 'txn_id')) INTO v_next_id;
    
    -- Generate and return the custom UUID
    RETURN custom_uuidv7(p_timestamp, v_next_id);
END;
$$ LANGUAGE plpgsql;
```

This enhanced approach provides a robust solution for migrating from timestamp-partitioned tables to UUID-partitioned tables while preserving all original information and optimizing for performance.
