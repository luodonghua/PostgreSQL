
-- generate sports ticket for baseball
WITH constants AS (
SELECT 
       ROUND(((RANDOM()::NUMERIC * (50 - 30)) + 30), 2)::NUMERIC(6, 2)
       AS var_v_standard_price
       )
INSERT INTO appuser.sporting_event_ticket (
sporting_event_id, 
sport_location_id, 
seat_level, 
seat_section, 
seat_row, 
seat, 
ticket_price
)
SELECT
sporting_event.id, 
seat.sport_location_id, 
seat.seat_level, 
seat.seat_section, 
seat.seat_row, 
seat.seat, 
(CASE
WHEN seat.seat_type = 'luxury'
THEN 3 * var_v_standard_price
WHEN seat.seat_type = 'premium'
THEN 2 * var_v_standard_price
WHEN seat.seat_type = 'standard'
THEN var_v_standard_price
WHEN seat.seat_type = 'sub-standard'
THEN 0.8 * var_v_standard_price
WHEN seat.seat_type = 'obstructed'
THEN 0.5 * var_v_standard_price
WHEN seat.seat_type = 'standing'
THEN 0.5 * var_v_standard_price
END) AS ticket_price
FROM constants, appuser.sporting_event, appuser.seat
WHERE sporting_event.location_id = seat.sport_location_id
AND sporting_event.sport_type_name= 'baseball';

-- generate sports ticket for football
WITH constants AS (
SELECT 
       ROUND(((RANDOM()::NUMERIC * (50 - 30)) + 30), 2)::NUMERIC(6, 2)
       AS var_v_standard_price
       )
INSERT INTO appuser.sporting_event_ticket (
sporting_event_id, 
sport_location_id, 
seat_level, 
seat_section, 
seat_row, 
seat, 
ticket_price
)
SELECT
sporting_event.id, 
seat.sport_location_id, 
seat.seat_level, 
seat.seat_section, 
seat.seat_row, 
seat.seat, 
(CASE
WHEN seat.seat_type = 'luxury'
THEN 3 * var_v_standard_price
WHEN seat.seat_type = 'premium'
THEN 2 * var_v_standard_price
WHEN seat.seat_type = 'standard'
THEN var_v_standard_price
WHEN seat.seat_type = 'sub-standard'
THEN 0.8 * var_v_standard_price
WHEN seat.seat_type = 'obstructed'
THEN 0.5 * var_v_standard_price
WHEN seat.seat_type = 'standing'
THEN 0.5 * var_v_standard_price
END) AS ticket_price
FROM constants, appuser.sporting_event, appuser.seat
WHERE sporting_event.location_id = seat.sport_location_id
AND sporting_event.sport_type_name= 'football';

