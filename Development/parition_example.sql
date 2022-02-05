create table sales (
  id bigserial,
  sales_date date not null,
  sales_amount money,
  constraint sales_pk primary key(id,sales_date)
) partition by range(sales_date);

create table sales_p_2020 partition of sales 
  for values from ('2020-01-01') to ('2021-01-01');
create table sales_p_2021 partition of sales 
  for values from ('2021-01-01') to ('2022-01-01');

mytest=> \d+ sales
                                            Partitioned table "public.sales"
   Column    |  Type  | Collation | Nullable |              Default              | Storage | Stats target | Description
-------------+--------+-----------+----------+-----------------------------------+---------+--------------+-------------
 id          | bigint |           | not null | nextval('sales_id_seq'::regclass) | plain   |              |
 sales_date  | date   |           | not null |                                   | plain   |              |
 sales_amount| money  |           |          |                                   | plain   |              |
Partition key: RANGE (sales_date)
Indexes:
    "sales_pk" PRIMARY KEY, btree (id, sales_date)
Partitions: sales_p_2020 FOR VALUES FROM ('2020-01-01') TO ('2021-01-01'),
            sales_p_2021 FOR VALUES FROM ('2021-01-01') TO ('2022-01-01')




create table sales_p_2022 partition of sales 
  for values from ('2022-01-01') to ('2023-01-01') partition by range(sales_date);

create table sales_p_2022_jan partition of sales_p_2022 
  for values from ('2022-01-01') to ('2022-02-01');
create table sales_p_2022_feb partition of sales_p_2022 
  for values from ('2022-02-01') to ('2022-03-01');
create table sales_p_2022_mar partition of sales_p_2022 
  for values from ('2022-03-01') to ('2022-04-01');



mytest=> \d+ sales
                                            Partitioned table "public.sales"
   Column    |  Type  | Collation | Nullable |              Default              | Storage | Stats target | Description
-------------+--------+-----------+----------+-----------------------------------+---------+--------------+-------------
 id          | bigint |           | not null | nextval('sales_id_seq'::regclass) | plain   |              |
 sales_date  | date   |           | not null |                                   | plain   |              |
 sales_amount | money |           |          |                                   | plain   |              |
Partition key: RANGE (sales_date)
Indexes:
    "sales_pk" PRIMARY KEY, btree (id, sales_date)
Partitions: sales_p_2020 FOR VALUES FROM ('2020-01-01') TO ('2021-01-01'),
            sales_p_2021 FOR VALUES FROM ('2021-01-01') TO ('2022-01-01'),
            sales_p_2022 FOR VALUES FROM ('2022-01-01') TO ('2023-01-01'), PARTITIONED

SELECT nmsp_parent.nspname AS parent_schema,
       parent.relname AS parent,
       nmsp_child.nspname AS child_schema,
       child.relname AS child
FROM pg_inherits
JOIN pg_class parent ON pg_inherits.inhparent = parent.oid
JOIN pg_class child ON pg_inherits.inhrelid = child.oid
JOIN pg_namespace nmsp_parent ON nmsp_parent.oid = parent.relnamespace
JOIN pg_namespace nmsp_child ON nmsp_child.oid = child.relnamespace
WHERE parent.relname='sales' ;

 parent_schema | parent | child_schema |    child
---------------+--------+--------------+--------------
 public        | sales  | public       | sales_p_2020
 public        | sales  | public       | sales_p_2021
 public        | sales  | public       | sales_p_2022
(3 rows)


SELECT * FROM pg_partition_tree('sales');

mytest=> SELECT * FROM pg_partition_tree('sales');
      relid       | parentrelid  | isleaf | level
------------------+--------------+--------+-------
 sales            |              | f      |     0
 sales_p_2020     | sales        | t      |     1
 sales_p_2021     | sales        | t      |     1
 sales_p_2022     | sales        | f      |     1
 sales_p_2022_jan | sales_p_2022 | t      |     2
 sales_p_2022_feb | sales_p_2022 | t      |     2
 sales_p_2022_mar | sales_p_2022 | t      |     2
(7 rows)

with v as (
  select '2020-01-01'::date+(random()*(365*2+90))::int as sales_date, random()*10000::money as sales_amount
  from generate_series(1,2700000))
insert into sales(sales_date,sales_amount) select * from v;





mytest=> explain analyze verbose
mytest-> select sum(sales_amount) from sales where sales_date='2022-02-01'::date;
                                                              QUERY PLAN
--------------------------------------------------------------------------------------------------------------------------------------
 Aggregate  (cost=1760.18..1760.19 rows=1 width=8) (actual time=8.463..8.464 rows=1 loops=1)
   Output: sum(sales.sales_amount)
   ->  Seq Scan on public.sales_p_2022_feb sales  (cost=0.00..1752.24 rows=3178 width=8) (actual time=0.008..8.203 rows=3244 loops=1)
         Output: sales.sales_amount
         Filter: (sales.sales_date = '2022-02-01'::date)
         Rows Removed by Filter: 89575
 Planning Time: 0.767 ms
 Execution Time: 8.522 ms
(8 rows)

Time: 289.688 ms
mytest=> select tableoid::regclass as partition, count(*) from sales group by partition;
    partition     |  count
------------------+---------
 sales_p_2020     | 1203782
 sales_p_2021     | 1201342
 sales_p_2022_jan |  101849
 sales_p_2022_feb |   92819
 sales_p_2022_mar |  100208
(5 rows)

Time: 824.771 ms
mytest=> drop table sales_p_2020;
DROP TABLE
Time: 264.490 ms
mytest=>


mytest=> alter table sales detach partition sales_p_2021;
ALTER TABLE
Time: 245.083 ms
mytest=> select tableoid::regclass as partition, count(*) from sales group by partition;
    partition     | count
------------------+--------
 sales_p_2022_jan | 101849
 sales_p_2022_feb |  92819
 sales_p_2022_mar | 100208
(3 rows)

Time: 286.817 ms
mytest=> select count(*) from sales_p_2021;
  count
---------
 1201342
(1 row)

Time: 335.229 ms
mytest=> alter table sales detach partition sales_p_2022;
ALTER TABLE
Time: 305.249 ms
mytest=> select tableoid::regclass as partition, count(*) from sales group by partition;
 partition | count
-----------+-------
(0 rows)

Time: 241.910 ms
mytest=> select tableoid::regclass as partition, count(*) from sales_p_2022 group by partition;
    partition     | count
------------------+--------
 sales_p_2022_jan | 101849
 sales_p_2022_feb |  92819
 sales_p_2022_mar | 100208
(3 rows)

mytest=> create table sales_2021 (like sales including defaults including constraints);
CREATE TABLE
Time: 248.808 ms

mytest=> insert into sales_2021 select * from sales_p_2021;
INSERT 0 1201342
Time: 1251.018 ms (00:01.251)



alter table sales attach partition sales_2021 
  for values from ('2021-01-01') to ('2022-01-01');

mytest=> alter table sales attach partition sales_2021
mytest->   for values from ('2021-01-01') to ('2022-01-01');

ALTER TABLE
Time: 2312.191 ms (00:02.312)


create table sales_p_2022 partition of sales 
  for values from ('2022-01-01') to ('2023-01-01') partition by range(sales_date);

create table sales_p_2022_jan partition of sales_p_2022 
  for values from ('2022-01-01') to ('2022-02-01');

create table t1 (id int,amount numeric);
-- create partition with 1000 subpartitions
create table t2 (id int,amount numeric) partition by range(id);
/****
-- bash script to generate subpartitions
for i in {1..1000}
do
echo "create table t2_p_${i} partition of t2 for values from ($i) to ($((i+1)));"
done
***/
create table t2_p_1 partition of t2 for values from (1) to (2);
create table t2_p_2 partition of t2 for values from (2) to (3);
create table t2_p_3 partition of t2 for values from (3) to (4);
create table t2_p_4 partition of t2 for values from (4) to (5);
...
create table t2_p_997 partition of t2 for values from (997) to (998);
create table t2_p_998 partition of t2 for values from (998) to (999);
create table t2_p_999 partition of t2 for values from (999) to (1000);
create table t2_p_1000 partition of t2 for values from (1000) to (1001);



-- create partition with 1000 level of subpartitions
create table t3 (id int,amount numeric) partition by range(id);
create table t3_p_1 partition of t3 for values from (1) to (1001) partition by range(id);
/****
-- bash script to generate subpartitions
for i in {2..999}
do
echo "create table t3_p_${i} partition of t3_p_$((i-1)) for values from ($i) to (1001) partition by range(id);"
done
****/

create table t3_p_2 partition of t3_p_1 for values from (2) to (1001) partition by range(id);
create table t3_p_3 partition of t3_p_2 for values from (3) to (1001) partition by range(id);
create table t3_p_4 partition of t3_p_3 for values from (4) to (1001) partition by range(id);
create table t3_p_5 partition of t3_p_4 for values from (5) to (1001) partition by range(id);
create table t3_p_6 partition of t3_p_5 for values from (6) to (1001) partition by range(id);
...
create table t3_p_996 partition of t3_p_995 for values from (996) to (1001) partition by range(id);
create table t3_p_997 partition of t3_p_996 for values from (997) to (1001) partition by range(id);
create table t3_p_998 partition of t3_p_997 for values from (998) to (1001) partition by range(id);
create table t3_p_999 partition of t3_p_998 for values from (999) to (1001) partition by range(id);
create table t3_p_1000 partition of t3_p_999 for values from (1000) to (1001);


mytest=> explain analyze verbose insert into t1 values (1000,0);
                                            QUERY PLAN
--------------------------------------------------------------------------------------------------
 Insert on public.t1  (cost=0.00..0.01 rows=1 width=36) (actual time=0.069..0.070 rows=0 loops=1)
   ->  Result  (cost=0.00..0.01 rows=1 width=36) (actual time=0.002..0.002 rows=1 loops=1)
         Output: 1000, '0'::numeric
 Planning Time: 0.022 ms
 Execution Time: 0.108 ms
(5 rows)


mytest=> explain analyze verbose insert into t2 values (1000,0);
                                            QUERY PLAN
--------------------------------------------------------------------------------------------------
 Insert on public.t2  (cost=0.00..0.01 rows=1 width=36) (actual time=0.297..0.297 rows=0 loops=1)
   ->  Result  (cost=0.00..0.01 rows=1 width=36) (actual time=0.003..0.003 rows=1 loops=1)
         Output: 1000, '0'::numeric
 Planning Time: 0.028 ms
 Execution Time: 4.936 ms
(5 rows)


mytest=> explain analyze verbose insert into t3 values (1000,0);
                                              QUERY PLAN
------------------------------------------------------------------------------------------------------
 Insert on public.t3  (cost=0.00..0.01 rows=1 width=36) (actual time=780.102..780.103 rows=0 loops=1)
   ->  Result  (cost=0.00..0.01 rows=1 width=36) (actual time=0.001..0.003 rows=1 loops=1)
         Output: 1000, '0'::numeric
 Planning Time: 0.029 ms
 Execution Time: 780.885 ms
(5 rows)


mytest=> explain analyze verbose select * from t1 where id=1000;
                                             QUERY PLAN
-----------------------------------------------------------------------------------------------------
 Seq Scan on public.t1  (cost=0.00..25.88 rows=6 width=36) (actual time=0.011..0.012 rows=1 loops=1)
   Output: id, amount
   Filter: (t1.id = 1000)
 Planning Time: 0.055 ms
 Execution Time: 0.057 ms
(5 rows)


mytest=> explain analyze verbose select * from t2 where id=1000;
                                                  QUERY PLAN
---------------------------------------------------------------------------------------------------------------
 Seq Scan on public.t2_p_1000 t2  (cost=0.00..25.88 rows=6 width=36) (actual time=0.011..0.012 rows=1 loops=1)
   Output: t2.id, t2.amount
   Filter: (t2.id = 1000)
 Planning Time: 0.067 ms
 Execution Time: 0.065 ms
(5 rows)


mytest=> explain analyze verbose select * from t3 where id=1000;
                                                  QUERY PLAN
---------------------------------------------------------------------------------------------------------------
 Seq Scan on public.t3_p_1000 t3  (cost=0.00..25.88 rows=6 width=36) (actual time=0.036..0.037 rows=1 loops=1)
   Output: t3.id, t3.amount
   Filter: (t3.id = 1000)
 Planning Time: 723.508 ms
 Execution Time: 0.607 ms
(5 rows)


mytest=> explain analyze verbose update t1 set amount=1 where id=1000;
                                                QUERY PLAN
-----------------------------------------------------------------------------------------------------------
 Update on public.t1  (cost=0.00..25.88 rows=6 width=42) (actual time=0.031..0.031 rows=0 loops=1)
   ->  Seq Scan on public.t1  (cost=0.00..25.88 rows=6 width=42) (actual time=0.014..0.015 rows=1 loops=1)
         Output: id, '1'::numeric, ctid
         Filter: (t1.id = 1000)
 Planning Time: 0.047 ms
 Execution Time: 0.091 ms
(6 rows)


mytest=> explain analyze verbose update t2 set amount=1 where id=1000;
                                                      QUERY PLAN
-----------------------------------------------------------------------------------------------------------------------
 Update on public.t2  (cost=0.00..25.88 rows=6 width=42) (actual time=0.037..0.037 rows=0 loops=1)
   Update on public.t2_p_1000 t2_1
   ->  Seq Scan on public.t2_p_1000 t2_1  (cost=0.00..25.88 rows=6 width=42) (actual time=0.013..0.014 rows=1 loops=1)
         Output: t2_1.id, '1'::numeric, t2_1.ctid
         Filter: (t2_1.id = 1000)
 Planning Time: 0.080 ms
 Execution Time: 0.095 ms
(7 rows)


mytest=> explain analyze verbose update t3 set amount=1 where id=1000;
                                                      QUERY PLAN
-----------------------------------------------------------------------------------------------------------------------
 Update on public.t3  (cost=0.00..25.88 rows=6 width=42) (actual time=2.761..2.762 rows=0 loops=1)
   Update on public.t3_p_1000 t3_1
   ->  Seq Scan on public.t3_p_1000 t3_1  (cost=0.00..25.88 rows=6 width=42) (actual time=0.006..0.008 rows=1 loops=1)
         Output: t3_1.id, '1'::numeric, t3_1.ctid
         Filter: (t3_1.id = 1000)
 Planning Time: 630.994 ms
 Execution Time: 9.249 ms
(7 rows)


mytest=> insert into t1 select 1000,0.0 from generate_series(1,1000);
INSERT 0 1000
Time: 234.954 ms
mytest=> insert into t2 select 1000,0.0 from generate_series(1,1000);
INSERT 0 1000
Time: 292.273 ms
mytest=> insert into t3 select 1000,0.0 from generate_series(1,1000);
INSERT 0 1000
Time: 568.590 ms



do 
$$
begin
  for i in 1..1000 loop
    insert into t3 values(1000,i::numeric);
  end loop;
end; 
$$;



mytest=> do
mytest-> $$
mytest$> begin
mytest$>   for i in 1..1000 loop
mytest$>     insert into t1 values(1000,i::numeric);
mytest$>   end loop;
mytest$> end;
mytest$> $$;
DO
Time: 250.741 ms

mytest=> do
mytest-> $$
mytest$> begin
mytest$>   for i in 1..1000 loop
mytest$>     insert into t2 values(1000,i::numeric);
mytest$>   end loop;
mytest$> end;
mytest$> $$;
DO
Time: 255.405 ms

mytest=> do
mytest-> $$
mytest$> begin
mytest$>   for i in 1..1000 loop
mytest$>     insert into t3 values(1000,i::numeric);
mytest$>   end loop;
mytest$> end;
mytest$> $$;
DO
Time: 129140.941 ms (02:09.141)


