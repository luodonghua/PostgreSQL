-- generate previous 3 year for baseball
insert into sporting_event (sport_type_name, home_team_id, away_team_id, location_id, start_date_time, start_date)
select sport_type_name, home_team_id, away_team_id, location_id, start_date_time - interval '1 year', start_date - interval '1 year'  
from sporting_event where date_part('year',start_date) = date_part('year', current_date) and sport_type_name='baseball';

insert into sporting_event (sport_type_name, home_team_id, away_team_id, location_id, start_date_time, start_date)
select sport_type_name, home_team_id, away_team_id, location_id, start_date_time - interval '2 year', start_date - interval '2 year'  
from sporting_event where date_part('year',start_date) = date_part('year', current_date) and sport_type_name='baseball';

insert into sporting_event (sport_type_name, home_team_id, away_team_id, location_id, start_date_time, start_date)
select sport_type_name, home_team_id, away_team_id, location_id, start_date_time - interval '2 year', start_date - interval '2 year'  
from sporting_event where date_part('year',start_date) = date_part('year', current_date) and sport_type_name='baseball';

-- generate previous 3 year for football
insert into sporting_event (sport_type_name, home_team_id, away_team_id, location_id, start_date_time, start_date)
select sport_type_name, home_team_id, away_team_id, location_id, start_date_time - interval '1 year', start_date - interval '1 year'  
from sporting_event where date_part('year',start_date) = date_part('year', current_date) and sport_type_name='football';

insert into sporting_event (sport_type_name, home_team_id, away_team_id, location_id, start_date_time, start_date)
select sport_type_name, home_team_id, away_team_id, location_id, start_date_time - interval '2 year', start_date - interval '2 year'  
from sporting_event where date_part('year',start_date) = date_part('year', current_date) and sport_type_name='football';

insert into sporting_event (sport_type_name, home_team_id, away_team_id, location_id, start_date_time, start_date)
select sport_type_name, home_team_id, away_team_id, location_id, start_date_time - interval '2 year', start_date - interval '2 year'  
from sporting_event where date_part('year',start_date) = date_part('year', current_date) and sport_type_name='football';
