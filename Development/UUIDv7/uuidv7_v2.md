# Custom UUIDv7 Implementation for Database Partition Migration

This document describes a custom UUIDv7 implementation designed for migrating from a timestamp-partitioned database table to a UUID-partitioned table while preserving both timestamp and original ID information.

## Background

UUIDv7 is a time-ordered UUID format that provides several advantages over traditional UUIDs, including:
- Chronological ordering for better indexing performance
- Reduced fragmentation in B-tree indexes
- Improved sequential insert performance

Our custom implementation extends the standard UUIDv7 format to embed additional information that facilitates database migration.

## Custom UUIDv7 Structure

Our custom UUIDv7 format embeds both timestamp and original ID information directly in the UUID:

| Bits    | Bytes | Content                                   |
|---------|-------|-------------------------------------------|
| 0-47    | 0-5   | Milliseconds since Unix epoch (timestamp) |
| 48-63   | 6-7   | Version (7) and random data               |
| 64-79   | 8-9   | Variant (2) and original ID (start)       |
| 80-111  | 10-13 | Original ID (continued)                   |
| 112-127 | 14-15 | Random data for uniqueness                |

This structure allows us to:
1. Maintain chronological ordering based on the timestamp
2. Preserve the original ID information without additional storage
3. Comply with the UUID standard format (version 7, variant 2)

## PostgreSQL Implementation

### Custom UUIDv7 Generation Function

```sql
CREATE OR REPLACE FUNCTION custom_uuidv7(p_timestamp TIMESTAMP, p_original_id BIGINT)
RETURNS UUID AS $$
DECLARE
    v_time_ms BIGINT;
    v_time_bytes BYTEA;
    v_id_bytes BYTEA;
    v_random_bytes BYTEA;
    v_result UUID;
BEGIN
    -- Convert timestamp to milliseconds since Unix epoch
    v_time_ms := (EXTRACT(EPOCH FROM p_timestamp) * 1000)::BIGINT;
    
    -- Convert time_ms to 6 bytes (48 bits)
    v_time_bytes := E'\\x' || lpad(to_hex(v_time_ms), 12, '0');
    
    -- Convert original ID to 6 bytes (48 bits)
    -- Ensure it fits within 48 bits (max value 2^48-1)
    IF p_original_id > 281474976710655 THEN -- 2^48-1
        RAISE EXCEPTION 'Original ID too large to fit in 48 bits: %', p_original_id;
    END IF;
    v_id_bytes := E'\\x' || lpad(to_hex(p_original_id), 12, '0');
    
    -- Generate 2 random bytes for the last part
    v_random_bytes := gen_random_bytes(2);
    
    -- Combine all parts with version (7) and variant (2) bits
    v_result := (
        v_time_bytes ||                                                -- 6 bytes: timestamp
        E'\\x70' ||                                                    -- 1 byte: version 7 (0111xxxx)
        E'\\x' || lpad(to_hex((get_byte(gen_random_bytes(1), 0) & 15)), 2, '0') || -- 1 byte: random with version bits
        E'\\x' || lpad(to_hex((get_byte(gen_random_bytes(1), 0) & 63) | 128), 2, '0') || -- 1 byte: variant 2 (10xxxxxx)
        substring(v_id_bytes FROM 3 FOR 5) ||                          -- 5 bytes: original ID (bytes 2-6)
        v_random_bytes                                                 -- 2 bytes: random data
    )::UUID;
    
    RETURN v_result;
END;
$$ LANGUAGE plpgsql;
```

### Data Extraction Functions

To extract the embedded information from the custom UUID:

```sql
-- Extract timestamp from custom UUID
CREATE OR REPLACE FUNCTION extract_timestamp_from_uuid(p_uuid UUID)
RETURNS TIMESTAMP AS $$
DECLARE
    v_hex TEXT;
    v_time_ms BIGINT;
BEGIN
    -- Extract the first 6 bytes (12 hex chars) from UUID
    v_hex := substring(replace(p_uuid::TEXT, '-', '') FROM 1 FOR 12);
    
    -- Convert hex to bigint (milliseconds since epoch)
    v_time_ms := ('x' || v_hex)::bit(48)::bigint;
    
    -- Convert milliseconds to timestamp
    RETURN to_timestamp(v_time_ms / 1000.0);
END;
$$ LANGUAGE plpgsql;

-- Extract original ID from custom UUID
CREATE OR REPLACE FUNCTION extract_original_id_from_uuid(p_uuid UUID)
RETURNS BIGINT AS $$
DECLARE
    v_hex TEXT;
    v_original_id BIGINT;
BEGIN
    -- Extract bytes 9-14 (original ID portion) from UUID
    v_hex := substring(replace(p_uuid::TEXT, '-', '') FROM 17 FOR 10);
    
    -- Add leading zeros to make it 12 hex chars (6 bytes)
    v_hex := '00' || v_hex;
    
    -- Convert hex to bigint
    v_original_id := ('x' || v_hex)::bit(48)::bigint;
    
    RETURN v_original_id;
END;
$$ LANGUAGE plpgsql;
```

## Migration Process

The migration process involves:

1. Creating the new UUID-partitioned table
2. Converting each record's timestamp and ID into the custom UUID format
3. Inserting the data with the new UUID as the primary key
4. Verifying the extraction functions work correctly

## Benefits

This custom UUIDv7 approach provides several benefits:

1. **Data Preservation**: Original timestamps and IDs are preserved within the UUID
2. **Storage Efficiency**: No need for additional columns to store original IDs
3. **Performance**: Maintains chronological ordering for efficient indexing
4. **Compatibility**: Works with UUID-based partitioning schemes
5. **Seamless Migration**: Applications can be updated to use extraction functions
6. **Future-Proof**: New transactions can use the same UUID format

## Limitations

- Original IDs must fit within 48 bits (max value: 2^48-1 or approximately 281 trillion)
- Timestamp precision is limited to milliseconds
- Extraction requires additional function calls

## Usage Example

```sql
-- Create a view that provides easy access to the embedded information
CREATE OR REPLACE VIEW transaction_embedded_data AS
SELECT 
    txn_id,
    extract_timestamp_from_uuid(txn_id) AS embedded_timestamp,
    extract_original_id_from_uuid(txn_id) AS embedded_original_id,
    amount,
    description,
    customer_id,
    updated_on
FROM 
    transactions_new_v2;

-- Query the view to see the embedded data
SELECT * FROM transaction_embedded_data;
```

## Generating New IDs

For new transactions, you can generate new custom UUIDs that maintain the same format:

```sql
CREATE OR REPLACE FUNCTION generate_new_transaction_id(p_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP)
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

This approach ensures a smooth transition from the original ID system to the new UUID-based system while preserving all the original information.
