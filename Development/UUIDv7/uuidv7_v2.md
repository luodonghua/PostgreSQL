# Enhanced UUIDv7 Implementation with Embedded Original ID

This document describes an enhanced UUIDv7 implementation that embeds both timestamp and original ID information directly in the UUID structure, providing a more comprehensive solution for database partition migration.

## Background

While standard UUIDv7 provides time-ordered UUIDs, this enhanced implementation goes further by embedding the original record ID directly in the UUID structure. This approach eliminates the need for a separate column to store the original ID reference and allows direct extraction of both timestamp and original ID from the UUID itself.

## Enhanced UUIDv7 Structure

The enhanced UUIDv7 format follows this structure:

| Bits    | Bytes | Content                                   |
|---------|-------|-------------------------------------------|
| 0-47    | 0-5   | Milliseconds since Unix epoch (timestamp) |
| 48-63   | 6-7   | Version (7) and variant bits              |
| 64-103  | 8-12  | Original ID (e.g., bigserial value)       |
| 104-127 | 13-15 | Random data for uniqueness                |

This structure allows for:
1. Chronological ordering based on the timestamp
2. Compliance with the UUID standard format (version 7, variant 2)
3. Direct embedding of the original ID (up to 40 bits, supporting values up to 2^40-1)
4. Sufficient randomness to ensure uniqueness

## PostgreSQL Implementation

### Custom UUIDv7 Generation Function

```sql
CREATE OR REPLACE FUNCTION custom_uuidv7(p_timestamp TIMESTAMP, p_original_id BIGINT)
RETURNS UUID AS $$
  -- First, convert the timestamp to milliseconds since epoch
  WITH base_uuid AS (
    SELECT gen_random_uuid() AS uuid
  ),
  time_ms AS (
    SELECT (EXTRACT(EPOCH FROM p_timestamp AT TIME ZONE 'UTC') * 1000)::BIGINT AS ms
  ),
  -- Format the timestamp and ID parts
  parts AS (
    SELECT
      lpad(to_hex((SELECT ms FROM time_ms)), 12, '0') AS time_hex,
      lpad(to_hex(p_original_id), 10, '0') AS id_hex
  )
  -- Construct the final UUID with the correct format
  SELECT (
    substring((SELECT time_hex FROM parts) FROM 1 FOR 8) || '-' ||
    substring((SELECT time_hex FROM parts) FROM 9 FOR 4) || '-' ||
    '7' || substring(replace((SELECT uuid FROM base_uuid)::text, '-', '') FROM 14 FOR 3) || '-' ||
    '8' || substring(replace((SELECT uuid FROM base_uuid)::text, '-', '') FROM 18 FOR 3) || '-' ||
    substring((SELECT id_hex FROM parts) FROM 1 FOR 10) ||
    substring(replace((SELECT uuid FROM base_uuid)::text, '-', '') FROM 30 FOR 2)
  )::UUID;
$$ LANGUAGE sql volatile parallel safe;
```

### Extraction Functions

```sql
-- Extract timestamp from UUID
CREATE OR REPLACE FUNCTION extract_timestamp_from_uuid(p_uuid UUID)
RETURNS TIMESTAMP AS $$
  -- Extract the first 6 bytes (12 hex chars) from UUID
  -- Convert hex to bigint (milliseconds since epoch)
  -- Convert milliseconds to timestamp
  SELECT to_timestamp(
    ('x' || substring(replace(p_uuid::TEXT, '-', '') FROM 1 FOR 12))::bit(48)::bigint / 1000.0
  ) AT TIME ZONE 'UTC';  -- Add explicit time zone conversion
$$ LANGUAGE sql volatile parallel safe;

-- Extract original ID from UUID
CREATE OR REPLACE FUNCTION extract_original_id_from_uuid(p_uuid UUID)
RETURNS BIGINT AS $$
  -- Extract the original ID portion from UUID
  SELECT ('x' || substring(replace(p_uuid::TEXT, '-', '') FROM 21 FOR 10))::bit(40)::bigint;
$$ LANGUAGE sql volatile parallel safe;
```

### Boundary Function for Partitioning

```sql
CREATE OR REPLACE FUNCTION uuidv7_boundary(timestamptz) RETURNS uuid
AS $$
  /*
   * uuid fields: version=0b0111, variant=0b10
   * Note: extract(epoch from timestamptz) always returns UTC seconds
   */
  select encode(
    overlay('\x00000000000070008000000000000000'::bytea
      placing substring(int8send(floor(extract(epoch from $1) * 1000)::bigint) from 3)
        from 1 for 6),
    'hex')::uuid;
$$ LANGUAGE sql stable strict parallel safe;
```

## Migration Process

The migration process involves:

1. Creating a new table with custom UUIDv7-based partitioning
2. Defining partitions based on precise timestamp boundaries using the `uuidv7_boundary` function
3. Migrating data from the original table to the new table with embedded information
4. No need for a separate column to store the original ID reference

### Creating the New Table

```sql
CREATE TABLE IF NOT EXISTS transactions_new_v2 (
    txn_id UUID PRIMARY KEY,
    amount DECIMAL(15, 2) NOT NULL,
    description TEXT,
    customer_id INTEGER NOT NULL,
    updated_on TIMESTAMP NOT NULL
) PARTITION BY RANGE ((txn_id));
```

### Creating Partitions with UTC Timestamps

```sql
CREATE TABLE transactions_new_v2_202401 PARTITION OF transactions_new_v2
    FOR VALUES FROM (uuidv7_boundary('2024-01-01 00:00:00+00')) TO (uuidv7_boundary('2024-02-01 00:00:00+00'));
    
CREATE TABLE transactions_new_v2_202402 PARTITION OF transactions_new_v2
    FOR VALUES FROM (uuidv7_boundary('2024-02-01 00:00:00+00')) TO (uuidv7_boundary('2024-03-01 00:00:00+00'));
    
CREATE TABLE transactions_new_v2_202403 PARTITION OF transactions_new_v2
    FOR VALUES FROM (uuidv7_boundary('2024-03-01 00:00:00+00')) TO (uuidv7_boundary('2024-04-01 00:00:00+00'));
```

### Migration Function

```sql
CREATE OR REPLACE FUNCTION migrate_transactions_v2()
RETURNS INTEGER AS $$
DECLARE
    v_count INTEGER := 0;
    v_rec RECORD;
    v_new_id UUID;
BEGIN
    FOR v_rec IN SELECT * FROM transactions_original ORDER BY txn_id
    LOOP
        -- Generate custom UUID from timestamp and original ID
        v_new_id := custom_uuidv7(v_rec.updated_on, v_rec.txn_id);
        
        INSERT INTO transactions_new_v2 (
            txn_id,
            amount, 
            description, 
            customer_id, 
            updated_on
        ) VALUES (
            v_new_id,
            v_rec.amount,
            v_rec.description,
            v_rec.customer_id,
            v_rec.updated_on
        );
        
        v_count := v_count + 1;
    END LOOP;
    
    RETURN v_count;
END;
$$ LANGUAGE plpgsql;
```

## Key Improvements

This enhanced implementation offers several advantages over the standard UUIDv7 approach:

1. **Embedded Original ID**: The original ID is directly embedded in the UUID structure
2. **No Additional Column**: No need for a separate column to store the original ID reference
3. **Direct Extraction**: Both timestamp and original ID can be extracted directly from the UUID
4. **Simplified Joins**: No need for additional joins to map between old and new IDs
5. **Space Efficiency**: More efficient storage by eliminating the need for an additional column
6. **Timezone Awareness**: Proper handling of timezones with explicit UTC conversion
7. **SQL Implementation**: Uses SQL language for better performance

## Data Verification

To verify the embedded data is correct:

```sql
SELECT 
    o.txn_id AS original_txn_id,
    o.updated_on AS original_updated_on,
    n.txn_id AS new_txn_id,
    extract_timestamp_from_uuid(n.txn_id) AS extracted_timestamp,
    extract_original_id_from_uuid(n.txn_id) AS extracted_original_id,
    CASE 
        WHEN o.txn_id = extract_original_id_from_uuid(n.txn_id) THEN 'MATCH'
        ELSE 'MISMATCH'
    END AS id_verification,
    CASE 
        WHEN date_trunc('second', o.updated_on) = date_trunc('second', extract_timestamp_from_uuid(n.txn_id)) THEN 'MATCH'
        ELSE 'MISMATCH'
    END AS timestamp_verification
FROM 
    transactions_original o
JOIN 
    transactions_new_v2 n ON n.updated_on = o.updated_on AND n.amount = o.amount
ORDER BY 
    o.txn_id;
```

## Embedded Data View

For easy access to the embedded information:

```sql
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
```

## Generating New IDs

For generating new IDs that maintain the sequence from the original table:

```sql
-- Optimized SQL function to generate a new custom UUIDv7 for new transactions
CREATE OR REPLACE FUNCTION generate_new_transaction_id(p_timestamp TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP)
RETURNS UUID AS $$
  -- Get the next value from the original sequence and generate the UUID in a single SQL statement
  SELECT custom_uuidv7(
    p_timestamp::TIMESTAMP,
    nextval(pg_get_serial_sequence('transactions_original', 'txn_id'))
  );
$$ LANGUAGE sql volatile parallel safe;
```

## Usage Example

```sql
-- Insert a new record with the custom UUID generator
INSERT INTO transactions_new_v2 (
    txn_id,
    amount,
    description,
    customer_id,
    updated_on
) VALUES (
    generate_new_transaction_id(),
    500.00,
    'New Purchase with Custom UUID',
    1005,
    CURRENT_TIMESTAMP
);

-- Verify the new record and extract its embedded data
SELECT 
    txn_id,
    embedded_timestamp,
    embedded_original_id,
    amount,
    description,
    updated_on
FROM 
    transaction_embedded_data
WHERE 
    description = 'New Purchase with Custom UUID';
```

## Testing and Validation

```sql
-- Function to test UUID embedding and extraction
CREATE OR REPLACE FUNCTION test_uuid_embedding()
RETURNS TABLE(original_id BIGINT, embedded_uuid UUID, extracted_id BIGINT) AS $$
BEGIN
  FOR i IN 1..10 LOOP
    RETURN QUERY
    SELECT 
      i::BIGINT AS original_id,
      custom_uuidv7(CURRENT_TIMESTAMP::timestamp, i) AS embedded_uuid,
      extract_original_id_from_uuid(custom_uuidv7(CURRENT_TIMESTAMP::timestamp, i)) AS extracted_id;
  END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Test the embedding and extraction
SELECT * FROM test_uuid_embedding();

-- Test maximum ID support
SELECT extract_original_id_from_uuid(custom_uuidv7('2020-01-01 01:01:34'::timestamp,(2^40-1)::bigint)),2^40-1 as max_id;
```

This enhanced implementation provides a comprehensive solution for migrating from traditional sequential IDs to UUIDv7 while maintaining all the original information directly within the UUID structure.
