
mytest=> show timezone;
 TimeZone 
----------
 UTC
(1 row)

mytest=> select * from pg_timezone_names where name like '%Singapore%' or name like '%Sydney%';
       name       | abbrev | utc_offset | is_dst 
------------------+--------+------------+--------
 Australia/Sydney | AEDT   | 11:00:00   | t
 Singapore        | +08    | 08:00:00   | f
 Asia/Singapore   | +08    | 08:00:00   | f
(3 rows)

create table t (timezone varchar(20),ts timestamp, tstz timestamp with time zone);

mytest=> create table t (timezone varchar(20),ts timestamp, tstz timestamp with time zone);
CREATE TABLE


insert into t values ('UTC', '2021-11-01 08:00:00'::timestamp,'2021-11-01 08:00:00'::timestamp);
insert into t values ('UTC', '2021-10-01 08:00:00'::timestamp,'2021-10-01 08:00:00'::timestamp);

mytest=> insert into t values ('UTC', '2021-11-01 08:00:00'::timestamp,'2021-11-01 08:00:00'::timestamp);
INSERT 0 1
mytest=> insert into t values ('UTC', '2021-10-01 08:00:00'::timestamp,'2021-10-01 08:00:00'::timestamp);
INSERT 0 1

set timezone='Australia/Sydney';

insert into t values ('Sydney', '2021-11-01 08:00:00'::timestamp,'2021-11-01 08:00:00'::timestamp);
insert into t values ('Sydney', '2021-10-01 08:00:00'::timestamp,'2021-10-01 08:00:00'::timestamp);

mytest=> set timezone='Australia/Sydney';
SET
mytest=> insert into t values ('Sydney', '2021-11-01 08:00:00'::timestamp,'2021-11-01 08:00:00'::timestamp);
INSERT 0 1
mytest=> insert into t values ('Sydney', '2021-10-01 08:00:00'::timestamp,'2021-10-01 08:00:00'::timestamp);
INSERT 0 1


set timezone='Asia/Singapore';

insert into t values ('Singapore', '2021-11-01 08:00:00'::timestamp,'2021-11-01 08:00:00'::timestamp);
insert into t values ('Singapore', '2021-10-01 08:00:00'::timestamp,'2021-10-01 08:00:00'::timestamp);


mytest=> set timezone='UTC';
SET
mytest=> select * from t;
 timezone  |         ts          |          tstz          
-----------+---------------------+------------------------
 UTC       | 2021-11-01 08:00:00 | 2021-11-01 08:00:00+00
 UTC       | 2021-10-01 08:00:00 | 2021-10-01 08:00:00+00
 Sydney    | 2021-11-01 08:00:00 | 2021-10-31 21:00:00+00
 Sydney    | 2021-10-01 08:00:00 | 2021-09-30 22:00:00+00
 Singapore | 2021-11-01 08:00:00 | 2021-11-01 00:00:00+00
 Singapore | 2021-10-01 08:00:00 | 2021-10-01 00:00:00+00
(6 rows)


mytest=> set timezone='Australia/Sydney';
SET
mytest=> select * from t;
 timezone  |         ts          |          tstz          
-----------+---------------------+------------------------
 UTC       | 2021-11-01 08:00:00 | 2021-11-01 19:00:00+11
 UTC       | 2021-10-01 08:00:00 | 2021-10-01 18:00:00+10
 Sydney    | 2021-11-01 08:00:00 | 2021-11-01 08:00:00+11
 Sydney    | 2021-10-01 08:00:00 | 2021-10-01 08:00:00+10
 Singapore | 2021-11-01 08:00:00 | 2021-11-01 11:00:00+11
 Singapore | 2021-10-01 08:00:00 | 2021-10-01 10:00:00+10
(6 rows)


mytest=> set timezone='Asia/Singapore';
SET
mytest=> select * from t;
 timezone  |         ts          |          tstz          
-----------+---------------------+------------------------
 UTC       | 2021-11-01 08:00:00 | 2021-11-01 16:00:00+08
 UTC       | 2021-10-01 08:00:00 | 2021-10-01 16:00:00+08
 Sydney    | 2021-11-01 08:00:00 | 2021-11-01 05:00:00+08
 Sydney    | 2021-10-01 08:00:00 | 2021-10-01 06:00:00+08
 Singapore | 2021-11-01 08:00:00 | 2021-11-01 08:00:00+08
 Singapore | 2021-10-01 08:00:00 | 2021-10-01 08:00:00+08
(6 rows)

mytest=> select timezone, pg_column_size(ts) ts_size, pg_column_size(tstz) tstz_size from t;
 timezone  | ts_size | tstz_size 
-----------+---------+-----------
 UTC       |       8 |         8
 UTC       |       8 |         8
 Sydney    |       8 |         8
 Sydney    |       8 |         8
 Singapore |       8 |         8
 Singapore |       8 |         8
(6 rows)

