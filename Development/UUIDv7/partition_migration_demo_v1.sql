-- PostgreSQL Partition Migration Demo
-- Converting from time-based partitioning to UUIDv7-based partitioning

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

-- Now, let's create a function to generate UUIDv7 values
-- UUIDv7 is time-ordered and provides better performance for indexing
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

-- Create the new transaction table with UUIDv7-based partitioning
CREATE TABLE IF NOT EXISTS transactions_new (
    txn_id UUID PRIMARY KEY DEFAULT gen_uuidv7(),
    amount DECIMAL(15, 2) NOT NULL,
    description TEXT,
    customer_id INTEGER NOT NULL,
    updated_on TIMESTAMP NOT NULL,
    original_txn_id BIGINT -- To maintain reference to original ID
) PARTITION BY RANGE ((txn_id::text));

-- Create partitions for the new table
-- UUIDv7 is time-ordered, so we can create partitions that roughly correspond to months
-- For January 2024 (approximate UUIDv7 range)
CREATE TABLE transactions_new_202401 PARTITION OF transactions_new
    FOR VALUES FROM ('017aa000-0000-7000-8000-000000000000') TO ('017b1000-0000-7000-8000-000000000000');
    
-- For February 2024 (approximate UUIDv7 range)
CREATE TABLE transactions_new_202402 PARTITION OF transactions_new
    FOR VALUES FROM ('017b1000-0000-7000-8000-000000000000') TO ('017b8000-0000-7000-8000-000000000000');
    
-- For March 2024 (approximate UUIDv7 range)
CREATE TABLE transactions_new_202403 PARTITION OF transactions_new
    FOR VALUES FROM ('017b8000-0000-7000-8000-000000000000') TO ('017bf000-0000-7000-8000-000000000000');

-- Migration function to move data from original table to new table
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

-- Create a view that maps between the old and new IDs
CREATE OR REPLACE VIEW transaction_id_mapping AS
SELECT 
    o.txn_id AS original_txn_id,
    n.txn_id AS new_txn_id,
    o.updated_on
FROM 
    transactions_original o
JOIN 
    transactions_new n ON o.txn_id = n.original_txn_id;

-- Query the mapping view
SELECT * FROM transaction_id_mapping;
