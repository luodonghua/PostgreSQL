-- PostgreSQL Partition Migration Demo V2
-- Converting from time-based partitioning to custom UUIDv7-based partitioning
-- This version embeds both timestamp and original ID information directly in the UUID

-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- First, let's create our original transaction table with monthly partitioning
CREATE TABLE IF NOT EXISTS transactions_original (
    txn_id BIGSERIAL,
    amount DECIMAL(15, 2) NOT NULL,
    description TEXT,
    customer_id INTEGER NOT NULL,
    updated_on TIMESTAMP NOT NULL,
    PRIMARY KEY (txn_id,updated_on)
) PARTITION BY RANGE (updated_on);


-- Create a few monthly partitions for the original table
CREATE TABLE transactions_original_202401 PARTITION OF transactions_original
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
    
CREATE TABLE transactions_original_202402 PARTITION OF transactions_original
    FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');
    
CREATE TABLE transactions_original_202403 PARTITION OF transactions_original
    FOR VALUES FROM ('2024-03-01') TO ('2024-04-01');

-- Insert some sample data into the original table
INSERT INTO transactions_original (amount, description, customer_id, updated_on)
VALUES 
    (100.50, 'Purchase A', 1001, '2024-01-15 10:30:00'),
    (200.75, 'Purchase B', 1002, '2024-01-20 11:45:00'),
    (150.25, 'Purchase C', 1003, '2024-02-05 09:15:00'),
    (300.00, 'Purchase D', 1001, '2024-02-18 14:20:00'),
    (175.50, 'Purchase E', 1002, '2024-03-03 16:10:00'),
    (225.25, 'Purchase F', 1003, '2024-03-22 13:05:00');

-- Now, let's create a custom UUIDv7 function that embeds both timestamp and original ID
-- Structure:
-- - First 48 bits (6 bytes): Milliseconds since Unix epoch from updated_on
-- - Next 16 bits (2 bytes): Version (7) and variant bits
-- - Next 48 bits (6 bytes): Original txn_id (bigserial) value
-- - Last 16 bits (2 bytes): Random data for uniqueness

-- Fixed custom_uuidv7 function that generates valid UUIDs
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

-- Function to generate UUIDv7 boundary values for partitioning
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

-- Updated function to extract timestamp from UUID with proper time zone handling
CREATE OR REPLACE FUNCTION extract_timestamp_from_uuid(p_uuid UUID)
RETURNS TIMESTAMP AS $$
  -- Extract the first 6 bytes (12 hex chars) from UUID
  -- Convert hex to bigint (milliseconds since epoch)
  -- Convert milliseconds to timestamp
  SELECT to_timestamp(
    ('x' || substring(replace(p_uuid::TEXT, '-', '') FROM 1 FOR 12))::bit(48)::bigint / 1000.0
  ) AT TIME ZONE 'UTC';  -- Add explicit time zone conversion
$$ LANGUAGE sql volatile parallel safe;

-- Updated function to extract original ID from UUID
CREATE OR REPLACE FUNCTION extract_original_id_from_uuid(p_uuid UUID)
RETURNS BIGINT AS $$
  -- Extract the original ID portion from UUID
  SELECT ('x' || substring(replace(p_uuid::TEXT, '-', '') FROM 21 FOR 10))::bit(40)::bigint;
$$ LANGUAGE sql volatile parallel safe;

-- Create the new transaction table with custom UUIDv7-based partitioning
CREATE TABLE IF NOT EXISTS transactions_new_v2 (
    txn_id UUID PRIMARY KEY,
    amount DECIMAL(15, 2) NOT NULL,
    description TEXT,
    customer_id INTEGER NOT NULL,
    updated_on TIMESTAMP NOT NULL
) PARTITION BY RANGE ((txn_id));


/*
You can use any of these formats to specify UTC:
• '2024-01-01 00:00:00+00' (explicit UTC offset)
• '2024-01-01 00:00:00Z' (Z suffix for UTC)
• '2024-01-01 00:00:00 UTC' (UTC timezone name)
**/

-- Create partitions for the new table
-- UUIDv7 is time-ordered, so we can create partitions that roughly correspond to months
-- For January 2024 (UUIDv7 range)

CREATE TABLE transactions_new_v2_202401 PARTITION OF transactions_new_v2
    FOR VALUES FROM (uuidv7_boundary('2024-01-01 00:00:00+00')) TO (uuidv7_boundary('2024-02-01 00:00:00+00'));
    
-- For February 2024 (UUIDv7 range)
CREATE TABLE transactions_new_v2_202402 PARTITION OF transactions_new_v2
    FOR VALUES FROM (uuidv7_boundary('2024-02-01 00:00:00+00')) TO (uuidv7_boundary('2024-03-01 00:00:00+00'));
    
-- For March 2024 (UUIDv7 range)
CREATE TABLE transactions_new_v2_202403 PARTITION OF transactions_new_v2
    FOR VALUES FROM (uuidv7_boundary('2024-03-01 00:00:00+00')) TO (uuidv7_boundary('2024-04-01 00:00:00+00'));


-- Migration function to move data from original table to new table
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

-- Execute the migration
SELECT migrate_transactions_v2();

-- Verify the migration
SELECT 'Original table count: ' || COUNT(*)::TEXT AS count FROM transactions_original;
SELECT 'New table count: ' || COUNT(*)::TEXT AS count FROM transactions_new_v2;

-- Sample query to show the data in both tables with extracted information
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
SELECT txn_id,embedded_original_id,embedded_timestamp,updated_on FROM transaction_embedded_data;

-- Test function to generate a new custom UUIDv7 for new transactions
CREATE OR REPLACE FUNCTION generate_new_transaction_id(p_timestamp TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP)
RETURNS UUID AS $$
DECLARE
    -- Get the next value from the original sequence
    v_next_id BIGINT;
BEGIN
    -- Get the next value from the original sequence
    SELECT nextval(pg_get_serial_sequence('transactions_original', 'txn_id')) INTO v_next_id;

    -- Generate and return the custom UUID
    -- Cast the timestamptz to timestamp to ensure consistent timezone handling
    RETURN custom_uuidv7(p_timestamp::TIMESTAMP, v_next_id);
END;
$$ LANGUAGE plpgsql;

-- Optimized SQL function to generate a new custom UUIDv7 for new transactions
CREATE OR REPLACE FUNCTION generate_new_transaction_id(p_timestamp TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP)
RETURNS UUID AS $$
  -- Get the next value from the original sequence and generate the UUID in a single SQL statement
  SELECT custom_uuidv7(
    p_timestamp::TIMESTAMP,
    nextval(pg_get_serial_sequence('transactions_original', 'txn_id'))
  );
$$ LANGUAGE sql volatile parallel safe;



-- For May 2025 (UUIDv7 range)
CREATE TABLE transactions_new_v2_202505 PARTITION OF transactions_new_v2
    FOR VALUES FROM (uuidv7_boundary('2025-05-01 00:00:00+00')) TO (uuidv7_boundary('2025-06-01 00:00:00+00'));


-- Example of inserting a new record with the custom UUID generator
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

-- max txn_id is 1099511627775
select extract_original_id_from_uuid(custom_uuidv7('2020-01-01 01:01:34'::timestamp,(2^40-1)::bigint)),2^40-1 as max_id;;
select extract_timestamp_from_uuid(custom_uuidv7('2020-01-01 01:01:34'::timestamp,(2^40-1)::bigint)),'2020-01-01 01:01:34'::timestamp as timestamp;;


