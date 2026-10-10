
\timing

-- Sample PostgreSQL database for Database Migration Service testing

-- Creating schema and tables
select null as "Setting appropriate search path";
set search_path = appuser;
select null as "Creating the tables";
\i ./schema/create-table.sql
select null as "Creating required indexes";
\i ./schema/create-index.sql
select null as "Creating appuser user:";
\i ./user/create-user.sql

-- Copying base data
select null as "Copying base data into tables";
\copy mlb_data from './data/csv/mlb_data.csv' DELIMITER ',' CSV HEADER;
\copy name_data from './data/csv/name_data.csv' DELIMITER ',' CSV HEADER;
\copy nfl_data from './data/csv/nfl_data.csv' DELIMITER ',' CSV HEADER;
\copy nfl_stadium_data from './data/csv/nfl_stadium_data.csv' DELIMITER ',' CSV HEADER;
\copy seat_type from './data/csv/seat_type.csv' DELIMITER ',' CSV HEADER;
\copy sport_location from './data/csv/sport_location.csv' DELIMITER ',' CSV HEADER;
\copy sport_division from './data/csv/sport_division.csv' DELIMITER ',' CSV HEADER;
\copy sport_league from './data/csv/sport_league.csv' DELIMITER ',' CSV HEADER;
INSERT INTO person(id, full_name, last_name, first_name)
SELECT row_number() OVER() as rownum
       ,first.name || ' ' || last.name
       ,last.name
       ,first.name 
FROM   name_data first, name_data last
WHERE  first.name_type != 'LAST'
AND    last.name_type  = 'LAST';

-- loading NFL and MLB teams
select null as "Loading NFL and MLB teams";
\i ./schema/functions/loadmlbteams.sql
\i ./schema/functions/loadnflteams.sql
select loadmlbteams();
select loadnflteams();
\i ./schema/functions/set_mlb_team_home_field.sql
\i ./schema/functions/set_nfl_homefield.sql
select setnflteamhomefield();

-- generating seats
select null as "Generating game seats";
\i ./schema/functions/esubstr.sql
\i ./schema/functions/generateseats.sql
select generateseats();

-- loading mlb and nfl players
select null as "Creating players";
\i ./schema/functions/loadmlbplayers.sql
\i ./schema/functions/loadnflplayers.sql
select loadmlbplayers();
select loadnflplayers();

-- generating mlb and nfl seasons
select null as "Creating the MLB and NFL seasons";
\i ./schema/functions/generatemlbseason.sql
select generatemlbseason();

\i ./schema/functions/generatenflseason.sql
select generatenflseason();

-- generate data for last 3 year historical events
\i ./schema/functions/generatelast3yearseasons.sql

-- generating tickets for game events
select null as "Generating game tickets for MLB and NFL";
\i ./schema/functions/generatesporttickets.sql


-- Sell tickets and generating ticket activities
select null as "Creating functions to sell and transfer tickets";
\i ./schema/functions/generateticketactivity.sql
-- generating some initial ticket purchases
select generateticketactivity(5000);

-- Generating transfer activity procedures and views
\i ./schema/functions/transferticket.sql
\i ./schema/functions/generatetransferactivity.sql
select generatetransferactivity(100000);

-- update transaction_date_time to make it historical data for these past events

update appuser.ticket_purchase_hist h 
set transaction_date_time =  e.start_date_time + trunc(random()*7*24*60 ) * '1 minute'::interval
from 
appuser.sporting_event_ticket t,
appuser.sporting_event e
where h.sporting_event_ticket_id = t.id
and t.sporting_event_id = e.id
and e.start_date_time < current_date;


-- adding Foreign Keys
\i ./schema/foreign-keys.sql

-- creating required views
\i ./schema/create-view.sql
