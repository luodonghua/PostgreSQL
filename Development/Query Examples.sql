select * from t_oil limit 1;
select * from t_oil fetch first 1 rows only;
table t_oil limit 1;

/*

mytest=> select * from t_oil limit 1;
    region     | country | year | production | consumption 
---------------+---------+------+------------+-------------
 North America | USA     | 1965 |       9014 |       11522
(1 row)

mytest=> select * from t_oil fetch first 1 rows only;
    region     | country | year | production | consumption 
---------------+---------+------+------------+-------------
 North America | USA     | 1965 |       9014 |       11522
(1 row)

mytest=> table t_oil limit 1;
    region     | country | year | production | consumption 
---------------+---------+------+------------+-------------
 North America | USA     | 1965 |       9014 |       11522
(1 row)
*/

select 
  format('[%s] %s',region, country) as region_country1,
 '['||region||'] '||country as region_country2,
  region, country
 from t_oil limit 1;

/*
mytest=>  select 
mytest->   format('[%s] %s',region, country) as region_country1,
mytest->  '['||region||'] '||country as region_country2,
mytest->   region, country
mytest->  from t_oil limit 1;
   region_country1   |   region_country2   |    region     | country 
---------------------+---------------------+---------------+---------
 [North America] USA | [North America] USA | North America | USA
*/


select date::date,
  extract('isodow' from date) as dow, 
  to_char(date, 'dy') as day, 
  extract('isoyear' from date) as "iso year", 
  extract('week' from date) as week, 
  extract('day' from (date + interval '2 month - 1 day')) as feb,
  extract('year' from date) as year,
  extract('day' from (date + interval '2 month - 1 day') ) = 29 as leap
from generate_series(date '2000-01-01', date '2010-01-01', interval '1 year')
as t(date); 

/*
mytest=> select date::date,
mytest->   extract('isodow' from date) as dow, 
mytest->   to_char(date, 'dy') as day, 
mytest->   extract('isoyear' from date) as "iso year", 
mytest->   extract('week' from date) as week, 
mytest->   extract('day' from (date + interval '2 month - 1 day')) as feb,
mytest->   extract('year' from date) as year,
mytest->   extract('day' from (date + interval '2 month - 1 day') ) = 29 as leap
mytest-> from generate_series(date '2000-01-01', date '2010-01-01', interval '1 year')
mytest-> as t(date); 
    date    | dow | day | iso year | week | feb | year | leap 
------------+-----+-----+----------+------+-----+------+------
 2000-01-01 |   6 | sat |     1999 |   52 |  29 | 2000 | t
 2001-01-01 |   1 | mon |     2001 |    1 |  28 | 2001 | f
 2002-01-01 |   2 | tue |     2002 |    1 |  28 | 2002 | f
 2003-01-01 |   3 | wed |     2003 |    1 |  28 | 2003 | f
 2004-01-01 |   4 | thu |     2004 |    1 |  29 | 2004 | t
 2005-01-01 |   6 | sat |     2004 |   53 |  28 | 2005 | f
 2006-01-01 |   7 | sun |     2005 |   52 |  28 | 2006 | f
 2007-01-01 |   1 | mon |     2007 |    1 |  28 | 2007 | f
 2008-01-01 |   2 | tue |     2008 |    1 |  29 | 2008 | t
 2009-01-01 |   4 | thu |     2009 |    1 |  28 | 2009 | f
 2010-01-01 |   5 | fri |     2009 |   53 |  28 | 2010 | f
(11 rows)
*/

select x from generate_series (1,5) as t(x) where x not in (1,2,3);
select x from generate_series (1,5) as t(x) where x not in (null);
select x from generate_series (1,5) as t(x) where x in (null);
select x from generate_series (1,5) as t(x) where x not in (coalesce(null,-1));

/*
mytest=> select x from generate_series (1,5) as t(x) where x not in (1,2,3);
 x 
---
 4
 5
(2 rows)

mytest=> select x from generate_series (1,5) as t(x) where x not in (null);
 x 
---
(0 rows)

mytest=> select x from generate_series (1,5) as t(x) where x in (null);
 x 
---
(0 rows)

mytest=> select x from generate_series (1,5) as t(x) where x not in (coalesce(null,-1));
 x 
---
 1
 2
 3
 4
 5
(5 rows)
*/

select * from t_oil order by year desc limit 1;

/*
mytest=> select * from t_oil order by year desc limit 1;
    region     | country | year | production | consumption 
---------------+---------+------+------------+-------------
 North America | USA     | 2010 |       7513 |       19180
(1 row)
*/

select a::text, 
       b::text, 
       (a=b)::text as "a=b", 
       format('%s = %s', coalesce(a::text, 'null'), coalesce(b::text, 'null')) as op, 
       format('is %s', coalesce((a=b)::text, 'null')) as result 
from       (values(true), (false), (null)) v1(a) 
cross join (values(true), (false), (null)) v2(b);


/*mytest=> select a::text, 
mytest->        b::text, 
mytest->        (a=b)::text as "a=b", 
mytest->        format('%s = %s', coalesce(a::text, 'null'), coalesce(b::text, 'null')) as op, 
mytest->        format('is %s', coalesce((a=b)::text, 'null')) as result 
mytest-> from       (values(true), (false), (null)) v1(a) 
mytest-> cross join (values(true), (false), (null)) v2(b);
   a   |   b   |  a=b  |      op       |  result  
-------+-------+-------+---------------+----------
 true  | true  | true  | true = true   | is true
 true  | false | false | true = false  | is false
 true  |       |       | true = null   | is null
 false | true  | false | false = true  | is false
 false | false | true  | false = false | is true
 false |       |       | false = null  | is null
       | true  |       | null = true   | is null
       | false |       | null = false  | is null
       |       |       | null = null   | is null
(9 rows)
*/


select a::text as left, 
       b::text as right,
       (a = b)::text as "=",
       (a <> b)::text as "<>",
       (a is distinct from b)::text as "is distinct",
       (a is not distinct from b)::text as "is not distinct from"
from       (values(true), (false), (null)) v1(a) 
cross join (values(true), (false), (null)) v2(b);

/*
mytest=> select a::text as left, 
mytest->        b::text as right,
mytest->        (a = b)::text as "=",
mytest->        (a <> b)::text as "<>",
mytest->        (a is distinct from b)::text as "is distinct",
mytest->        (a is not distinct from b)::text as "is not distinct from"
mytest-> from       (values(true), (false), (null)) v1(a) 
mytest-> cross join (values(true), (false), (null)) v2(b);
 left  | right |   =   |  <>   | is distinct | is not distinct from 
-------+-------+-------+-------+-------------+----------------------
 true  | true  | true  | false | false       | true
 true  | false | false | true  | true        | false
 true  |       |       |       | true        | false
 false | true  | false | true  | true        | false
 false | false | true  | false | false       | true
 false |       |       |       | true        | false
       | true  |       |       | true        | false
       | false |       |       | true        | false
       |       |       |       | false       | true
(9 rows)
*/

select (null is null) as is_null, (null is not null) as is_not_null;

/*
mytest=> select (null is null) as is_null, (null is not null) as is_not_null;
 is_null | is_not_null 
---------+-------------
 t       | f
(1 row)
*/

select x, array_agg(x) over (order by x)
from generate_series(1, 3) as t(x);

/*
mytest=> select x, array_agg(x) over (order by x)
mytest-> from generate_series(1, 3) as t(x);
 x | array_agg 
---+-----------
 1 | {1}
 2 | {1,2}
 3 | {1,2,3}
(3 rows)
*/

select row_number() over (partition by country order by year desc), * 
from t_oil where country in ('USA','Israel') order by year desc limit 10;

/*
mytest=> select row_number() over (partition by country order by year desc), * 
mytest-> from t_oil where country in ('USA','Israel') order by year desc limit 10;
 row_number |    region     | country | year | production | consumption 
------------+---------------+---------+------+------------+-------------
          1 | North America | USA     | 2010 |       7513 |       19180
          1 | Middle East   | Israel  | 2010 |            |         234
          2 | Middle East   | Israel  | 2009 |            |         237
          2 | North America | USA     | 2009 |       7271 |       18771
          3 | Middle East   | Israel  | 2008 |            |         252
          3 | North America | USA     | 2008 |       6734 |       19490
          4 | North America | USA     | 2007 |       6847 |       20680
          4 | Middle East   | Israel  | 2007 |            |         257
          5 | Middle East   | Israel  | 2006 |            |         249
          5 | North America | USA     | 2006 |       6841 |       20687
(10 rows)
*/




