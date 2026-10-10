create table t1 (id int, c_char char(10),c_varchar varchar(10), c_text text);
insert into t1 values(1,'a','a','a');
insert into t1 values(2,'a  ','a  ','a  ');

mytest=> \d t1
                         Table "public.t1"
  Column   |         Type          | Collation | Nullable | Default 
-----------+-----------------------+-----------+----------+---------
 id        | integer               |           |          | 
 c_char    | character(10)         |           |          | 
 c_varchar | character varying(10) |           |          | 
 c_text    | text                  |           |          | 


mytest=> select a.id aid,b.id bid from t1 a, t1 b where a.c_char=b.c_char;
 aid | bid 
-----+-----
   1 |   2
   1 |   1
   2 |   2
   2 |   1
(4 rows)


mytest=> explain
mytest-> select a.id aid,b.id bid from t1 a, t1 b where a.c_char=b.c_char;
                             QUERY PLAN                             
--------------------------------------------------------------------
 Hash Join  (cost=22.38..92.18 rows=1512 width=8)
   Hash Cond: (a.c_char = b.c_char)
   ->  Seq Scan on t1 a  (cost=0.00..15.50 rows=550 width=48)
   ->  Hash  (cost=15.50..15.50 rows=550 width=48)
         ->  Seq Scan on t1 b  (cost=0.00..15.50 rows=550 width=48)


mytest=> select a.id aid,b.id bid from t1 a, t1 b where a.c_char=b.c_varchar;
 aid | bid 
-----+-----
   1 |   2
   1 |   1
   2 |   2
   2 |   1
(4 rows)

mytest=> explain
mytest-> select a.id aid,b.id bid from t1 a, t1 b where a.c_char=b.c_varchar;
                             QUERY PLAN                             
--------------------------------------------------------------------
 Hash Join  (cost=22.38..92.18 rows=1512 width=8)
   Hash Cond: (a.c_char = (b.c_varchar)::bpchar)
   ->  Seq Scan on t1 a  (cost=0.00..15.50 rows=550 width=48)
   ->  Hash  (cost=15.50..15.50 rows=550 width=42)
         ->  Seq Scan on t1 b  (cost=0.00..15.50 rows=550 width=42)
(5 rows)

mytest=> select a.id aid,b.id bid from t1 a, t1 b where a.c_char=b.c_text;
 aid | bid 
-----+-----
   1 |   1
   2 |   1
(2 rows)

mytest=> explain
mytest-> select a.id aid,b.id bid from t1 a, t1 b where a.c_char=b.c_text;
                             QUERY PLAN                             
--------------------------------------------------------------------
 Merge Join  (cost=81.07..111.65 rows=1512 width=8)
   Merge Cond: (((a.c_char)::text) = b.c_text)
   ->  Sort  (cost=40.53..41.91 rows=550 width=48)
         Sort Key: ((a.c_char)::text)
         ->  Seq Scan on t1 a  (cost=0.00..15.50 rows=550 width=48)
   ->  Sort  (cost=40.53..41.91 rows=550 width=36)
         Sort Key: b.c_text
         ->  Seq Scan on t1 b  (cost=0.00..15.50 rows=550 width=36)
(8 rows)

mytest=> select a.id aid,b.id bid from t1 a, t1 b where a.c_varchar=b.c_varchar;
 aid | bid 
-----+-----
   1 |   1
   2 |   2
(2 rows)

mytest=> explain
mytest-> select a.id aid,b.id bid from t1 a, t1 b where a.c_varchar=b.c_varchar;
                             QUERY PLAN                             
--------------------------------------------------------------------
 Hash Join  (cost=22.38..92.18 rows=1512 width=8)
   Hash Cond: ((a.c_varchar)::text = (b.c_varchar)::text)
   ->  Seq Scan on t1 a  (cost=0.00..15.50 rows=550 width=42)
   ->  Hash  (cost=15.50..15.50 rows=550 width=42)
         ->  Seq Scan on t1 b  (cost=0.00..15.50 rows=550 width=42)
(5 rows)


mytest=> select a.id aid,b.id bid from t1 a, t1 b where a.c_varchar=b.c_text;
 aid | bid 
-----+-----
   1 |   1
   2 |   2
(2 rows)

mytest=> explain
select a.id aid,b.id bid from t1 a, t1 b where a.c_varchar=b.c_text;
                             QUERY PLAN                             
--------------------------------------------------------------------
 Hash Join  (cost=22.38..92.18 rows=1512 width=8)
   Hash Cond: ((a.c_varchar)::text = b.c_text)
   ->  Seq Scan on t1 a  (cost=0.00..15.50 rows=550 width=42)
   ->  Hash  (cost=15.50..15.50 rows=550 width=36)
         ->  Seq Scan on t1 b  (cost=0.00..15.50 rows=550 width=36)
(5 rows)


mytest=> select a.id aid,b.id bid from t1 a, t1 b where a.c_text=b.c_text;
 aid | bid 
-----+-----
   1 |   1
   2 |   2
(2 rows)

mytest=> explain
select a.id aid,b.id bid from t1 a, t1 b where a.c_text=b.c_text;
                             QUERY PLAN                             
--------------------------------------------------------------------
 Hash Join  (cost=22.38..92.18 rows=1512 width=8)
   Hash Cond: (a.c_text = b.c_text)
   ->  Seq Scan on t1 a  (cost=0.00..15.50 rows=550 width=36)
   ->  Hash  (cost=15.50..15.50 rows=550 width=36)
         ->  Seq Scan on t1 b  (cost=0.00..15.50 rows=550 width=36)
(5 rows)


