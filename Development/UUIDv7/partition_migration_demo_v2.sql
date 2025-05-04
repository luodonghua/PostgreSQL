-- PostgreSQL Partition Migration Demo V2
-- Converting from time-based partitioning to custom UUIDv7-based partitioning
-- This version embeds both timestamp and original ID information directly in the UUID

-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- First, let's create our original transaction table with monthly partitioning
CREATE TABLE IF NOT EXISTS transactions_original (
    txn_id BIGSERIAL PRIMARY KEY,
    amount DECIMAL(15, 2) NOT NULL,
    description TEXT,
    customer_id INTEGER NOT NULL,
    updated_on TIMESTAMP NOT NULL
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
    -- Version 7 is set in the 13th hex digit (first digit of 7th byte)
    -- Variant 2 is set in the 17th hex digit (first digit of 9th byte)
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

-- Create functions to extract information from our custom UUID
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

CREATE OR REPLACE FUNCTION extract_original_id_from_uuid(p_uuid UUID)
RETURNS BIGINT AS $$
DECLARE
    v_hex TEXT;
    v_original_id BIGINT;
BEGIN
    -- Extract bytes 9-14 (original ID portion) from UUID
    -- This skips the first 8 bytes (16 hex chars) and takes the next 6 bytes (12 hex chars)
    v_hex := substring(replace(p_uuid::TEXT, '-', '') FROM 17 FOR 10);
    
    -- Add leading zeros to make it 12 hex chars (6 bytes)
    v_hex := '00' || v_hex;
    
    -- Convert hex to bigint
    v_original_id := ('x' || v_hex)::bit(48)::bigint;
    
    RETURN v_original_id;
END;
$$ LANGUAGE plpgsql;

-- Create the new transaction table with custom UUIDv7-based partitioning
CREATE TABLE IF NOT EXISTS transactions_new_v2 (
    txn_id UUID PRIMARY KEY,
    amount DECIMAL(15, 2) NOT NULL,
    description TEXT,
    customer_id INTEGER NOT NULL,
    updated_on TIMESTAMP NOT NULL
) PARTITION BY RANGE ((txn_id::text));

-- Create partitions for the new table
-- UUIDv7 is time-ordered, so we can create partitions that roughly correspond to months
-- For January 2024 (approximate UUIDv7 range)
CREATE TABLE transactions_new_v2_202401 PARTITION OF transactions_new_v2
    FOR VALUES FROM ('017aa000-0000-7000-8000-000000000000') TO ('017b1000-0000-7000-8000-000000000000');
    
-- For February 2024 (approximate UUIDv7 range)
CREATE TABLE transactions_new_v2_202402 PARTITION OF transactions_new_v2
    FOR VALUES FROM ('017b1000-0000-7000-8000-000000000000') TO ('017b8000-0000-7000-8000-000000000000');
    
-- For March 2024 (approximate UUIDv7 range)
CREATE TABLE transactions_new_v2_202403 PARTITION OF transactions_new_v2
    FOR VALUES FROM ('017b8000-0000-7000-8000-000000000000') TO ('017bf000-0000-7000-8000-000000000000');

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
        WHEN date_trunc('millisecond', o.updated_on) = date_trunc('millisecond', extract_timestamp_from_uuid(n.txn_id)) THEN 'MATCH'
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
SELECT * FROM transaction_embedded_data;

-- Test function to generate a new custom UUIDv7 for new transactions
CREATE OR REPLACE FUNCTION generate_new_transaction_id(p_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP)
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
    description
FROM 
    transaction_embedded_data
WHERE 
    description = 'New Purchase with Custom UUID';
