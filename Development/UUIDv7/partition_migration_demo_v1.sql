-- PostgreSQL Partition Migration Demo
-- Converting from time-based partitioning to UUIDv7-based partitioning

-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

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

-- Now, let's create a function to generate UUIDv7 values
-- UUIDv7 is time-ordered and provides better performance for indexing

/* Main function to generate a uuidv7 value with millisecond precision */
-- https://github.com/dverite/postgres-uuidv7-sql/blob/main/sql/uuidv7-sql--1.0.sql
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


CREATE FUNCTION uuidv7_boundary(timestamptz) RETURNS uuid
AS $$
  /* uuid fields: version=0b0111, variant=0b10 */
  select encode(
    overlay('\x00000000000070008000000000000000'::bytea
      placing substring(int8send(floor(extract(epoch from $1) * 1000)::bigint) from 3)
        from 1 for 6),
    'hex')::uuid;
$$ LANGUAGE sql stable strict parallel safe;

CREATE TABLE IF NOT EXISTS transactions_new_v1 (
    txn_id UUID PRIMARY KEY DEFAULT uuidv7(),
    amount DECIMAL(15, 2) NOT NULL,
    description TEXT,
    customer_id INTEGER NOT NULL,
    updated_on TIMESTAMP NOT NULL,
    original_txn_id BIGINT -- To maintain reference to original ID
) PARTITION BY RANGE ((txn_id));



-- DROP TABLE IF EXISTS transactions_new_202401;
-- DROP TABLE IF EXISTS transactions_new_202402;
-- DROP TABLE IF EXISTS transactions_new_202403;

-- Create partitions for the new table using the boundary function
-- This ensures precise partition boundaries based on timestamps
CREATE TABLE transactions_new_v1_202401 PARTITION OF transactions_new_v1
    FOR VALUES FROM (uuidv7_boundary('2024-01-01 00:00:00+00')) TO (uuidv7_boundary('2024-02-01 00:00:00+00'));
    
CREATE TABLE transactions_new_v1_202402 PARTITION OF transactions_new_v1
    FOR VALUES FROM (uuidv7_boundary('2024-02-01 00:00:00+00')) TO (uuidv7_boundary('2024-03-01 00:00:00+00'));
    
CREATE TABLE transactions_new_v1_202403 PARTITION OF transactions_new_v1
    FOR VALUES FROM (uuidv7_boundary('2024-03-01 00:00:00+00')) TO (uuidv7_boundary('2024-04-01 00:00:00+00'));

-- Add a default partition to catch any values outside these ranges
-- CREATE TABLE transactions_new_default PARTITION OF transactions_new DEFAULT;


-- Migration function to move data from original table to new table
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
            uuidv7(v_rec.updated_on),
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
SELECT 'New table count: ' || COUNT(*)::TEXT AS count FROM transactions_new_v1;

-- Sample query to show the data in both tables
SELECT 'Original' AS table_name, txn_id::TEXT, amount, updated_on FROM transactions_original
UNION ALL
SELECT 'New' AS table_name, txn_id::TEXT, amount, updated_on FROM transactions_new_v1
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
    transactions_new_v1 n ON o.txn_id = n.original_txn_id;

-- Query the mapping view
SELECT * FROM transaction_id_mapping;

-- To include the partition name in your query results, 
-- you can use the tableoid::regclass expression, 
-- which returns the name of the table where each row is stored.

SELECT
    txn_id,
    amount,
    updated_on,
    tableoid::regclass AS partition_name,
    original_txn_id,
FROM
    transactions_new_v1
ORDER BY
    updated_on;

