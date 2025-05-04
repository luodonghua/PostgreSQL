-- Create the trigger function
CREATE OR REPLACE FUNCTION sync_transactions_trigger_function()
RETURNS TRIGGER AS $$
DECLARE
    v_new_id UUID;
BEGIN
    -- Handle different operations (INSERT, UPDATE, DELETE)
    IF (TG_OP = 'INSERT') THEN
        -- Generate custom UUID from timestamp and original ID
        v_new_id := custom_uuidv7(NEW.updated_on, NEW.txn_id);

        -- Insert the new record into transactions_new_v3
        INSERT INTO transactions_new_v3 (
            txn_id,
            amount,
            description,
            customer_id,
            updated_on
        ) VALUES (
            v_new_id,
            NEW.amount,
            NEW.description,
            NEW.customer_id,
            NEW.updated_on
        );

    ELSIF (TG_OP = 'UPDATE') THEN
        -- Find and delete the old record in transactions_new_v3
        DELETE FROM transactions_new_v3
        WHERE extract_original_id_from_uuid(txn_id) = OLD.txn_id;

        -- Generate custom UUID from timestamp and original ID
        v_new_id := custom_uuidv7(NEW.updated_on, NEW.txn_id);

        -- Insert the updated record into transactions_new_v3
        INSERT INTO transactions_new_v3 (
            txn_id,
            amount,
            description,
            customer_id,
            updated_on
        ) VALUES (
            v_new_id,
            NEW.amount,
            NEW.description,
            NEW.customer_id,
            NEW.updated_on
        );

    ELSIF (TG_OP = 'DELETE') THEN
        -- Delete the corresponding record from transactions_new_v3
        DELETE FROM transactions_new_v3
        WHERE extract_original_id_from_uuid(txn_id) = OLD.txn_id;
    END IF;

    RETURN NULL; -- For AFTER triggers
END;
$$ LANGUAGE plpgsql;

-- Create the trigger on transactions_original
CREATE TRIGGER sync_transactions_trigger
AFTER INSERT OR UPDATE OR DELETE ON transactions_original
FOR EACH ROW EXECUTE FUNCTION sync_transactions_trigger_function();

/** 

insert into transactions_original (amount, description, customer_id, updated_on)
values  (12.50, 'Purchase A', 1001, '2024-01-15 10:30:00');
update 	transactions_original set amount=12.6, updated_on='2024-03-01' where txn_id=1;
delete from transactions_original where txn_id=1;

**/
