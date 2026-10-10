CREATE OR REPLACE FUNCTION appuser.generatetransferactivity(IN par_max_transactions NUMERIC)
RETURNS void
AS
$BODY$
DECLARE
    var_txn_count NUMERIC(10, 0) DEFAULT 0;
    var_min_tik_id NUMERIC(20, 0);
    var_max_tik_id NUMERIC(20, 0);
    var_tik_id NUMERIC(20, 0);
    var_max_p_id NUMERIC(10, 0);
    var_min_p_id NUMERIC(10, 0);
    var_person_id NUMERIC(10, 0);
    var_rand_p_max NUMERIC(10, 0);
    var_rand_max NUMERIC(20, 0);
    var_xfer_all NUMERIC(1, 0) DEFAULT 1;
    var_price NUMERIC(10, 4);
    var_price_multiplier NUMERIC(18, 0) DEFAULT 1;
BEGIN
    SELECT
        MIN(sporting_event_ticket_id), MAX(sporting_event_ticket_id)
        INTO var_min_tik_id, var_max_tik_id
        FROM appuser.ticket_purchase_hist;
    SELECT
        MIN(id), MAX(id)
        INTO var_min_p_id, var_max_p_id
        FROM appuser.person;

    WHILE var_txn_count < par_max_transactions LOOP
        /* find a random upper bound for ticket and person ids */
        var_rand_max := floor(random()*(var_max_tik_id-var_min_tik_id+var_min_tik_id))+var_min_tik_id;
        var_rand_p_max := floor(random()*(var_max_p_id-var_min_p_id+var_min_p_id))+var_min_p_id;
        SELECT
            MAX(sporting_event_ticket_id)
            INTO var_tik_id
            FROM appuser.ticket_purchase_hist
            WHERE sporting_event_ticket_id <= var_rand_max;
        SELECT
            MAX(id)
            INTO var_person_id
            FROM appuser.person
            WHERE id <= var_rand_p_max
       
        /* 30% of the time change the price by up to 20% in either direction */;

        IF random() < 0.3 THEN
            var_price_multiplier := random()*0.4+0.8; --original code: CAST ((floor(random()*(12-8+8))+8) AS NUMERIC(18, 0)) / 10;            
        END IF;
        SELECT
            var_price_multiplier * ticket_price
            INTO var_price
            FROM appuser.sporting_event_ticket
            WHERE id = var_tik_id;
        PERFORM appuser.transferticket(var_tik_id, var_person_id, var_xfer_all, var_price)
        /* reset some variables */;
        var_txn_count := (var_txn_count + 1)::INT;
        var_xfer_all := 1;
        var_price_multiplier := 1;
    END LOOP;
    EXCEPTION
        WHEN OTHERS THEN
            RAISE NOTICE '%', ('Sorry, no tickets are available for transfer.');
END;
$BODY$
LANGUAGE  plpgsql;
