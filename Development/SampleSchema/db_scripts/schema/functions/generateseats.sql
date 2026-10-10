CREATE OR REPLACE FUNCTION appuser.generateseats()
RETURNS void
AS
$BODY$
DECLARE
    var_done VARCHAR(50) DEFAULT FALSE;
    var_v_sport_location_id INTEGER;
    var_v_seating_capacity INTEGER;
    var_v_levels INTEGER;
    var_v_sections INTEGER;
    var_v_seat_type VARCHAR(15);
    var_v_rowCt INTEGER;
    var_i INTEGER;
    var_j INTEGER;
    var_k INTEGER;
    var_l INTEGER;
    var_v_tot_seats INTEGER;
    var_v_rows INTEGER;
    var_v_seats INTEGER;
    var_v_seat_count INTEGER;
    var_v_seat_idx INTEGER;
    var_v_max_rows_per_section INTEGER DEFAULT 15; -- original vlaue is 25
    var_v_min_rows_per_section INTEGER DEFAULT 5; -- original vlaue is 15
    var_s_ref VARCHAR(30) DEFAULT 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    loc_cur CURSOR FOR
    SELECT
        id, seating_capacity, levels, sections
        FROM appuser.sport_location;

    var_seat_reserved_rate NUMERIC(3,2) DEFAULT 0.98;

BEGIN
    DROP TABLE IF EXISTS seat_tab;
    DROP TABLE IF EXISTS seat_type_tab;
    CREATE TEMPORARY TABLE seat_tab as select sport_location_id, seat_level, seat_section, seat_row, seat, seat_type from seat where 1=2;

    CREATE TEMPORARY TABLE seat_type_tab
    (id INTEGER PRIMARY KEY,
        name VARCHAR(15));
    var_v_rowCt := 0::INTEGER;

    
    WHILE var_v_rowCt < 100::INTEGER LOOP
        var_v_rowCt := (var_v_rowCt::NUMERIC + 1::NUMERIC)::INTEGER;

        IF var_v_rowCt <= 5::INTEGER THEN
            var_v_seat_type := 'luxury'::VARCHAR(15);
        END IF;

        IF 5 < var_v_rowCt::NUMERIC(10, 0) AND var_v_rowCt <= 35::INTEGER THEN
            var_v_seat_type := 'premium'::VARCHAR(15);
        END IF;

        IF 35 < var_v_rowCt::NUMERIC(10, 0) AND var_v_rowCt <= 89::INTEGER THEN
            var_v_seat_type := 'standard'::VARCHAR(15);
        END IF;

        IF 89 < var_v_rowCt::NUMERIC(10, 0) AND var_v_rowCt <= 99::INTEGER THEN
            var_v_seat_type := 'sub-standard'::VARCHAR(15);
        END IF;

        IF var_v_rowCt = 100::INTEGER THEN
            var_v_seat_type := 'obstructed'::VARCHAR(15);
        END IF;
        INSERT INTO seat_type_tab (id, name)
        VALUES (var_v_rowCt, var_v_seat_type);
    END LOOP;
    OPEN loc_cur;

    <<read_loop>>
    LOOP
        FETCH FROM loc_cur INTO var_v_sport_location_id, var_v_seating_capacity, var_v_levels, var_v_sections;

        IF NOT FOUND THEN
            EXIT read_loop;
        END IF;

        -- Currently total 3565082 seats in all sports location, 
        -- use "var_seat_reserved_rate" to adjust how many tickets can be sold
        -- var_seat_reserved_rate = 0.7, which is 1,069,500 seats in total
        var_v_seating_capacity = FLOOR(var_v_seating_capacity * (1 - var_seat_reserved_rate));

        var_v_seat_count := 0;
        var_v_tot_seats := 0;
        var_v_rows := (FLOOR((RANDOM() * (var_v_max_rows_per_section::NUMERIC - var_v_min_rows_per_section::NUMERIC + 1::NUMERIC))::NUMERIC) + var_v_min_rows_per_section::NUMERIC)::INTEGER;
        var_v_seats := TRUNC((var_v_seating_capacity::NUMERIC / (var_v_levels::NUMERIC * var_v_sections::NUMERIC * var_v_rows::NUMERIC) + 1::NUMERIC)::NUMERIC, (0)::INT)::INTEGER;
        -- RAISE NOTICE 'location_id: %, level: %, section: %, row: %, seats: %, max: %', var_v_sport_location_id, var_v_levels, var_v_sections, var_v_rows,var_v_seats,var_v_seating_capacity;
        var_i := 1;
        var_j := 1;
        var_k := 1;
        var_l := 1;

        WHILE var_i <= var_v_levels LOOP
            var_i := var_i + 1;

            WHILE var_j <= var_v_sections LOOP
                var_j := var_j + 1;

                WHILE var_k <= var_v_rows LOOP
                    var_k := var_k + 1;

                    WHILE var_l <= var_v_seats LOOP
                        var_l := var_l + 1;
                        var_v_tot_seats := var_v_tot_seats + 1;

                        IF var_v_tot_seats <= var_v_seating_capacity THEN
                            var_v_seat_idx := (FLOOR(RANDOM() * 100 + 1))::INTEGER;
                            SELECT
                                name
                                INTO var_v_seat_type
                                FROM seat_type_tab
                                WHERE id = var_v_seat_idx;
                            INSERT INTO seat_tab (sport_location_id, seat_level, seat_section, seat_row, seat, seat_type)
                            VALUES (var_v_sport_location_id, var_i, var_j, esubstr(var_s_ref::VARCHAR, var_k::INT, 1::INT), var_l, var_v_seat_type);
                            var_v_seat_count := var_v_seat_count + 1;
                            -- RAISE NOTICE 'location_id: %, var_i: %, var_j: %, var_k: %, var_l: %, var_v_seat_type: %', var_v_sport_location_id, var_i, var_j, var_k,var_l,var_v_seat_type;
                            -- RAISE NOTICE 'batch commit: location_id: %, var_v_seat_count: %', var_v_sport_location_id,var_v_seat_count;
                            IF var_v_seat_count > 1000 THEN
                                -- RAISE NOTICE 'batch commit: location_id: %, var_v_tot_seats: %', var_v_sport_location_id, var_v_tot_seats;
                                INSERT INTO appuser.seat (sport_location_id, seat_level, seat_section, seat_row, seat, seat_type)
                                SELECT
                                    var_v_sport_location_id, seat_level, seat_section, seat_row, seat, var_v_seat_type
                                    FROM seat_tab;
                                DELETE FROM seat_tab;
                                var_v_seat_count := 1;
                            END IF;
                        END IF;
                    END LOOP;
                    -- RAISE NOTICE 'location_id: %, var_l: %',var_v_sport_location_id,var_l;
                    var_l := 0;
                END LOOP;
                -- RAISE NOTICE 'location_id: %, var_k: %',var_v_sport_location_id,var_k;
                var_k := 0;
            END LOOP;
            -- RAISE NOTICE 'location_id: %, var_j: %',var_v_sport_location_id,var_j;
            var_j := 0;
        END LOOP;
        INSERT INTO appuser.seat (sport_location_id, seat_level, seat_section, seat_row, seat, seat_type)
        SELECT
            var_v_sport_location_id, seat_level, seat_section, seat_row, seat, var_v_seat_type
            FROM seat_tab;
        DELETE FROM seat_tab;
        var_v_tot_seats := 1;
    END LOOP;
        -- RAISE NOTICE 'location_id: %, var_i: %',var_v_sport_location_id,var_i;
    CLOSE loc_cur;
END;
$BODY$
LANGUAGE  plpgsql;
