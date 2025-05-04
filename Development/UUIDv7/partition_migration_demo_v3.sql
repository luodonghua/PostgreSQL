-- PostgreSQL Partition Migration Demo V3
-- Converting from time-based partitioning to custom UUIDv7-based partitioning
-- This version embeds both timestamp and original ID information directly in the UUID
-- Improved based on reference implementation from https://github.com/dverite/postgres-uuidv7-sql

-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- First, let's create our original transaction table with monthly partitioning
CREATE TABLE IF NOT EXISTS transactions_original (
    txn_id BIGSERIAL PRIMARY KEY,
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

/*PL/pgSQL version for reference only, find below SQL Server version for performant implementation */

-- Now, let's create an improved custom UUIDv7 function that embeds both timestamp and original ID
-- Structure:
-- - First 48 bits (6 bytes): Milliseconds since Unix epoch from updated_on
-- - Next 12 bits: Version (7) and variant bits (2) as per UUID spec
-- - Next 4 bits: Reserved for future use (set to 0)
-- - Next 48 bits (6 bytes): Original txn_id (bigserial) value
-- - Last 16 bits (2 bytes): Random data for uniqueness

CREATE OR REPLACE FUNCTION custom_uuidv7(p_timestamp TIMESTAMP, p_original_id BIGINT)
RETURNS UUID AS $$
DECLARE
    v_time_ms BIGINT;
    v_uuid_base BYTEA;
    v_result UUID;
BEGIN
    -- Convert timestamp to milliseconds since Unix epoch
    v_time_ms := (EXTRACT(EPOCH FROM p_timestamp AT TIME ZONE 'UTC') * 1000)::BIGINT;
    
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
    
    -- Insert original ID into bytes 8-13 (bits 64-111)
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





-- Function to generate partition boundary UUIDs based on timestamp
-- This is useful for creating partition boundaries
CREATE OR REPLACE FUNCTION uuidv7_boundary(p_timestamp TIMESTAMP)
RETURNS UUID AS $$
DECLARE
    v_time_ms BIGINT;
    v_uuid_base BYTEA;
BEGIN
    -- Convert timestamp to milliseconds since Unix epoch
    -- No need to convert to UTC, as this is simple boundary setting regardless of TZ
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




-- Create functions to extract information from our custom UUID
CREATE OR REPLACE FUNCTION extract_timestamp_from_uuid(p_uuid UUID)
RETURNS TIMESTAMP AS $$
BEGIN
    -- Extract the timestamp from the first 48 bits
    RETURN to_timestamp(
        (('x' || substring(replace(p_uuid::TEXT, '-', '') FROM 1 FOR 12))::bit(48)::bigint) / 1000.0
    ) AT TIME ZONE 'UTC';
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



/*SQL Sversion */


CREATE OR REPLACE FUNCTION custom_uuidv7(p_timestamp TIMESTAMP DEFAULT clock_timestamp(), p_original_id BIGINT DEFAULT NULL)
RETURNS UUID AS $$
  -- Generate a UUIDv7 with embedded timestamp and original ID
  WITH params AS (
    SELECT
      (EXTRACT(EPOCH FROM p_timestamp AT TIME ZONE 'UTC')*1000)::bigint AS ms,
      CASE
        WHEN p_original_id > 1099511627775 THEN 1099511627775::BIGINT  -- 2^40-1
        WHEN p_original_id IS NULL THEN 0::BIGINT
        ELSE p_original_id
      END AS id,
      p_original_id IS NOT NULL AS has_id
  ),
  -- Format the timestamp and ID parts as hex strings
  parts AS (
    SELECT
      lpad(to_hex((SELECT ms FROM params)), 12, '0') AS time_hex,
      lpad(to_hex((SELECT id FROM params)), 10, '0') AS id_hex
  ),
  -- Generate random parts for the UUID
  rand_parts AS (
    SELECT
      substring(encode(gen_random_bytes(10), 'hex') FROM 1 FOR 3) AS rand1,
      substring(encode(gen_random_bytes(10), 'hex') FROM 1 FOR 3) AS rand2,
      substring(encode(gen_random_bytes(10), 'hex') FROM 1 FOR 2) AS rand3
  )
  -- Construct the final UUID with the correct format
  SELECT (
    substring((SELECT time_hex FROM parts) FROM 1 FOR 8) || '-' ||
    substring((SELECT time_hex FROM parts) FROM 9 FOR 4) || '-' ||
    '7' || (SELECT rand1 FROM rand_parts) || '-' ||
    '8' || (SELECT rand2 FROM rand_parts) || '-' ||
    substring((SELECT id_hex FROM parts) FROM 1 FOR 10) ||
    (SELECT rand3 FROM rand_parts)
  )::UUID;
$$ LANGUAGE sql VOLATILE PARALLEL SAFE;



-- Function to generate partition boundary UUIDs based on timestamp
-- This is useful for creating partition boundaries
CREATE OR REPLACE FUNCTION uuidv7_boundary(p_timestamp TIMESTAMP)
RETURNS UUID AS $$
  WITH params AS (
    -- Convert timestamp to milliseconds since Unix epoch
    -- No need to convert to UTC, as this is simple boundary setting regardless of TZ
    SELECT (EXTRACT(EPOCH FROM p_timestamp) * 1000)::BIGINT AS ms
  ),
  base_uuid AS (
    -- Create a base UUID with all zeros
    SELECT E'\\x00000000000000000000000000000000'::BYTEA AS bytes
  ),
  timestamp_uuid AS (
    -- Replace first 6 bytes with timestamp
    SELECT overlay(
      (SELECT bytes FROM base_uuid)
      placing substring(int8send((SELECT ms FROM params)) from 3)
      from 1 for 6
    ) AS bytes
  ),
  version_uuid AS (
    -- Set version to 7 (bits 48-51)
    SELECT
      set_bit(
        set_bit(
          set_bit(
            set_bit(
              (SELECT bytes FROM timestamp_uuid),
              48, 0
            ),
            49, 1
          ),
          50, 1
        ),
        51, 1
      ) AS bytes
  ),
  variant_uuid AS (
    -- Set variant to 2 (bits 64-65)
    SELECT
      set_bit(
        set_bit(
          (SELECT bytes FROM version_uuid),
          64, 1
        ),
        65, 0
      ) AS bytes
  )
  -- Convert to UUID
  SELECT encode((SELECT bytes FROM variant_uuid), 'hex')::uuid;
$$ LANGUAGE sql STABLE STRICT PARALLEL SAFE;


-- Extract timestamp from UUID (SQL version)
CREATE OR REPLACE FUNCTION extract_timestamp_from_uuid(p_uuid UUID)
RETURNS TIMESTAMP AS $$
  -- Extract the timestamp from the first 48 bits
  SELECT to_timestamp(
    (('x' || substring(replace(p_uuid::TEXT, '-', '') FROM 1 FOR 12))::bit(48)::bigint) / 1000.0
  ) AT TIME ZONE 'UTC';  -- Add explicit time zone conversion;
$$ LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE;

-- Extract original ID from UUID (SQL version)
CREATE OR REPLACE FUNCTION extract_original_id_from_uuid(p_uuid UUID)
RETURNS BIGINT AS $$
  -- Extract the original ID from bytes 9-13 (bits 72-112)
  -- This is a simplified approach that works for the way we're embedding the ID
  SELECT ('x' || substring(replace(p_uuid::TEXT, '-', '') FROM 21 FOR 10))::bit(40)::bigint;
$$ LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE;



-- Create the new transaction table with custom UUIDv7-based partitioning
CREATE TABLE IF NOT EXISTS transactions_new_v3 (
    txn_id UUID PRIMARY KEY,
    amount DECIMAL(15, 2) NOT NULL,
    description TEXT,
    customer_id INTEGER NOT NULL,
    updated_on TIMESTAMP NOT NULL
) PARTITION BY RANGE ((txn_id));

-- Create partitions for the new table using the boundary function
-- This ensures precise partition boundaries based on timestamps
CREATE TABLE transactions_new_v3_202401 PARTITION OF transactions_new_v3
    FOR VALUES FROM (uuidv7_boundary('2024-01-01 00:00:00+00')) TO (uuidv7_boundary('2024-02-01 00:00:00+00'));
    
CREATE TABLE transactions_new_v3_202402 PARTITION OF transactions_new_v3
    FOR VALUES FROM (uuidv7_boundary('2024-02-01 00:00:00+00')) TO (uuidv7_boundary('2024-03-01 00:00:00+00'));
    
CREATE TABLE transactions_new_v3_202403 PARTITION OF transactions_new_v3
    FOR VALUES FROM (uuidv7_boundary('2024-03-01 00:00:00+00')) TO (uuidv7_boundary('2024-04-01 00:00:00+00'));

-- Migration function to move data from original table to new table
CREATE OR REPLACE FUNCTION migrate_transactions_v3()
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
        
        INSERT INTO transactions_new_v3 (
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
SELECT migrate_transactions_v3();

-- Verify the migration
SELECT 'Original table count: ' || COUNT(*)::TEXT AS count FROM transactions_original;
SELECT 'New table count: ' || COUNT(*)::TEXT AS count FROM transactions_new_v3;

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
        WHEN date_trunc('millisecond', o.updated_on) = date_trunc('millisecond', extract_timestamp_from_uuid(n.txn_id)) THEN 'MATCH'
        ELSE 'MISMATCH'
    END AS timestamp_verification
FROM 
    transactions_original o
JOIN 
    transactions_new_v3 n ON n.updated_on = o.updated_on AND n.amount = o.amount
ORDER BY 
    o.txn_id;

-- Create a view that provides easy access to the embedded information
CREATE OR REPLACE VIEW transaction_embedded_data_v3 AS
SELECT 
    txn_id,
    extract_timestamp_from_uuid(txn_id) AS embedded_timestamp,
    extract_original_id_from_uuid(txn_id) AS embedded_original_id,
    amount,
    description,
    customer_id,
    updated_on
FROM 
    transactions_new_v3;

-- Query the view to see the embedded data
SELECT * FROM transaction_embedded_data_v3;

-- Query rows and partition name
SELECT
    txn_id,
    amount,
    updated_on,
    extract_timestamp_from_uuid(txn_id) AS embedded_timestamp,
    extract_original_id_from_uuid(txn_id) AS embedded_original_id,
    tableoid::regclass AS partition_name
FROM
    transactions_new_v3
ORDER BY
    updated_on;



-- Test function to generate a new custom UUIDv7 for new transactions
CREATE OR REPLACE FUNCTION generate_new_transaction_id_v3(p_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP)
RETURNS UUID AS $$
DECLARE
    -- Get the next value from the original sequence
    v_next_id BIGINT;
BEGIN
    -- Get the next value from the original sequence
    SELECT nextval(pg_get_serial_sequence('transactions_original', 'txn_id')) INTO v_next_id;
    
    -- Generate and return the custom UUID
    RETURN custom_uuidv7(p_timestamp, v_next_id);
END;
$$ LANGUAGE plpgsql;

-- Optimized SQL function to generate a new custom UUIDv7 for new transactions
CREATE OR REPLACE FUNCTION generate_new_transaction_id_v3(p_timestamp TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP)
RETURNS UUID AS $$
  -- Get the next value from the original sequence and generate the UUID in a single SQL statement
  SELECT custom_uuidv7(
    p_timestamp::TIMESTAMP,
    nextval(pg_get_serial_sequence('transactions_original', 'txn_id'))
  );
$$ LANGUAGE sql volatile parallel safe;


-- For May 2025 (UUIDv7 range)
CREATE TABLE transactions_new_v3_202505 PARTITION OF transactions_new_v3
    FOR VALUES FROM (uuidv7_boundary('2025-05-01 00:00:00+00')) TO (uuidv7_boundary('2025-06-01 00:00:00+00'));




-- Example of inserting a new record with the custom UUID generator
INSERT INTO transactions_new_v3 (
    txn_id,
    amount,
    description,
    customer_id,
    updated_on
) VALUES (
    generate_new_transaction_id_v3(),
    500.00,
    'New Purchase with Custom UUID V3',
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
    transaction_embedded_data_v3
WHERE 
    description = 'New Purchase with Custom UUID V3';

-- Create an index on the extracted timestamp to improve query performance
CREATE INDEX idx_transactions_new_v3_timestamp 
ON transactions_new_v3 (extract_timestamp_from_uuid(txn_id));

-- Create an index on the extracted original ID to improve query performance
CREATE INDEX idx_transactions_new_v3_original_id
ON transactions_new_v3 (extract_original_id_from_uuid(txn_id));

-- Example query using the extracted timestamp for filtering
EXPLAIN ANALYZE
SELECT * FROM transactions_new_v3
WHERE extract_timestamp_from_uuid(txn_id) BETWEEN '2024-01-01' AND '2024-01-31';

-- Example query using the extracted original ID for filtering
EXPLAIN ANALYZE
SELECT * FROM transactions_new_v3
WHERE extract_original_id_from_uuid(txn_id) = 1;

explain analyze SELECT * FROM transactions_new_v3
WHERE txn_id BETWEEN
custom_uuidv7('2024-01-01'::timestamp, 0) AND
custom_uuidv7('2024-01-31 23:59:59.999'::timestamp, 1099511627775);

explain analyze SELECT * FROM transactions_new_v3
WHERE txn_id BETWEEN '018cc251-f400-785f-8ed9-0000000000bf' AND '018d61f7-17ff-7509-80b7-ffffffffff36';
