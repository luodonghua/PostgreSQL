begin;

drop table if exists daily_equaity_volumes;

create table daily_equaity_volumes
(
  trade_date                date,
  nyse_type_a               text,
  nyse_arca_type_a          text,
  nyse_amer_type_a          text,
  nyse_national_type_a      text,
  nyse_chicago_type_a       text,
  consolidated_type_a       text,
  nyse_type_b               text,
  nyse_arca_type_b          text,
  nyse_amer_type_b          text,
  nyse_chicago_type_b       text,
  nyse_national_type_b      text,
  consolidated_type_b       text,
  nyse_type_c               text,
  nyse_arca_type_c          text,
  nyse_amer_type_c          text,
  nyse_national_type_c      text,
  nyse_chicago_type_c       text,
  consolidated_type_c       text
);

\copy daily_equaity_volumes from 'datasets/US_Equities_Volumes.csv' with CSV HEADER;

-- type a
alter table daily_equaity_volumes 
  alter nyse_type_a type numeric(8,2) 
  using replace(replace(nyse_type_a,',',''),'"','')::numeric;

alter table daily_equaity_volumes 
  alter nyse_arca_type_a type numeric(8,2) 
  using replace(replace(nyse_arca_type_a,',',''),'"','')::numeric;  

alter table daily_equaity_volumes 
  alter nyse_amer_type_a type numeric(8,2) 
  using replace(replace(nyse_amer_type_a,',',''),'"','')::numeric;  

alter table daily_equaity_volumes 
  alter nyse_national_type_a type numeric(8,2) 
  using replace(replace(nyse_national_type_a,',',''),'"','')::numeric;  

alter table daily_equaity_volumes 
  alter nyse_chicago_type_a type numeric(8,2) 
  using replace(replace(nyse_chicago_type_a,',',''),'"','')::numeric;  

alter table daily_equaity_volumes 
  alter consolidated_type_a type numeric(8,2) 
  using replace(replace(consolidated_type_a,',',''),'"','')::numeric;  

-- type b
alter table daily_equaity_volumes 
  alter nyse_type_b type numeric(8,2) 
  using replace(replace(nyse_type_b,',',''),'"','')::numeric;  

alter table daily_equaity_volumes 
  alter nyse_arca_type_b type numeric(8,2) 
  using replace(replace(nyse_arca_type_b,',',''),'"','')::numeric;  

alter table daily_equaity_volumes 
  alter nyse_amer_type_b type numeric(8,2) 
  using replace(replace(nyse_amer_type_b,',',''),'"','')::numeric;  

alter table daily_equaity_volumes 
  alter nyse_chicago_type_b type numeric(8,2) 
  using replace(replace(nyse_chicago_type_b,',',''),'"','')::numeric;  

alter table daily_equaity_volumes 
  alter nyse_national_type_b type numeric(8,2) 
  using replace(replace(nyse_national_type_b,',',''),'"','')::numeric;  

alter table daily_equaity_volumes 
  alter consolidated_type_b type numeric(8,2) 
  using replace(replace(consolidated_type_b,',',''),'"','')::numeric;  

--type c
alter table daily_equaity_volumes 
  alter nyse_type_c type numeric(8,2) 
  using replace(replace(nyse_type_c,',',''),'"','')::numeric;  

alter table daily_equaity_volumes 
  alter nyse_arca_type_c type numeric(8,2) 
  using replace(replace(nyse_arca_type_c,',',''),'"','')::numeric;  

alter table daily_equaity_volumes 
  alter nyse_amer_type_c type numeric(8,2) 
  using replace(replace(nyse_amer_type_c,',',''),'"','')::numeric;  

alter table daily_equaity_volumes 
  alter nyse_national_type_c type numeric(8,2) 
  using replace(replace(nyse_national_type_c,',',''),'"','')::numeric;  

alter table daily_equaity_volumes 
  alter nyse_chicago_type_c type numeric(8,2) 
  using replace(replace(nyse_chicago_type_c,',',''),'"','')::numeric;  

alter table daily_equaity_volumes 
  alter consolidated_type_c type numeric(8,2) 
  using replace(replace(consolidated_type_c,',',''),'"','')::numeric;  

commit;


