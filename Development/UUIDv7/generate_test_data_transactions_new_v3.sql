-- Create a function to generate test data across the three partitions
CREATE OR REPLACE FUNCTION generate_test_data(p_records_per_partition INT DEFAULT 1000)
RETURNS VOID AS $$
DECLARE
    v_start_date TIMESTAMP;
    v_end_date TIMESTAMP;
    v_current_date TIMESTAMP;
    v_interval INTERVAL;
    v_amount DECIMAL(15,2);
    v_customer_id INT;
    v_description TEXT;
    v_uuid UUID;
    v_counter INT := 0;
BEGIN
    -- January 2024 partition
    v_start_date := '2024-01-01 00:00:00'::TIMESTAMP;
    v_end_date := '2024-01-31 23:59:59'::TIMESTAMP;
    v_interval := (v_end_date - v_start_date) / p_records_per_partition;

    FOR i IN 1..p_records_per_partition LOOP
        v_counter := v_counter + 1;
        v_current_date := v_start_date + (v_interval * (i - 1));
        v_amount := (random() * 1000)::DECIMAL(15,2);
        v_customer_id := 1000 + (random() * 1000)::INT;
        v_description := 'Test Transaction ' || v_counter;
        v_uuid := custom_uuidv7(v_current_date, v_counter);

        INSERT INTO transactions_new_v3 (txn_id, amount, description, customer_id, updated_on)
        VALUES (v_uuid, v_amount, v_description, v_customer_id, v_current_date);
    END LOOP;

    -- February 2024 partition
    v_start_date := '2024-02-01 00:00:00'::TIMESTAMP;
    v_end_date := '2024-02-29 23:59:59'::TIMESTAMP;
    v_interval := (v_end_date - v_start_date) / p_records_per_partition;

    FOR i IN 1..p_records_per_partition LOOP
        v_counter := v_counter + 1;
        v_current_date := v_start_date + (v_interval * (i - 1));
        v_amount := (random() * 1000)::DECIMAL(15,2);
        v_customer_id := 1000 + (random() * 1000)::INT;
        v_description := 'Test Transaction ' || v_counter;
        v_uuid := custom_uuidv7(v_current_date, v_counter);

        INSERT INTO transactions_new_v3 (txn_id, amount, description, customer_id, updated_on)
        VALUES (v_uuid, v_amount, v_description, v_customer_id, v_current_date);
    END LOOP;

    -- March 2024 partition
    v_start_date := '2024-03-01 00:00:00'::TIMESTAMP;
    v_end_date := '2024-03-31 23:59:59'::TIMESTAMP;
    v_interval := (v_end_date - v_start_date) / p_records_per_partition;

    FOR i IN 1..p_records_per_partition LOOP
        v_counter := v_counter + 1;
        v_current_date := v_start_date + (v_interval * (i - 1));
        v_amount := (random() * 1000)::DECIMAL(15,2);
        v_customer_id := 1000 + (random() * 1000)::INT;
        v_description := 'Test Transaction ' || v_counter;
        v_uuid := custom_uuidv7(v_current_date, v_counter);

        INSERT INTO transactions_new_v3 (txn_id, amount, description, customer_id, updated_on)
        VALUES (v_uuid, v_amount, v_description, v_customer_id, v_current_date);
    END LOOP;

    RAISE NOTICE 'Generated % records across 3 partitions', v_counter;
END;
$$ LANGUAGE plpgsql;

-- Execute the function to generate 3000 records (1000 per partition)
SELECT generate_test_data(1000);

-- Verify the data distribution
SELECT
    tableoid::regclass AS partition_name,
    COUNT(*) AS record_count,
    MIN(extract_timestamp_from_uuid(txn_id)) AS min_date,
    MAX(extract_timestamp_from_uuid(txn_id)) AS max_date
FROM
    transactions_new_v3
GROUP BY
    tableoid
ORDER BY
    min_date;
