create table t1 (id int);
create table t2 (id int) with (oids=true);

insert into t1 values(1);
insert into t2 values(1);
select oid,* from t2;
select * from t2 where oid=16408;
select attrelid,attname from pg_attribute where attrelid = 't1'::regclass;
select attrelid,attname from pg_attribute where attrelid = 't2'::regclass;


/*

mytest=> create table t1 (id int);
CREATE TABLE
mytest=> create table t2 (id int) with (oids=true);
CREATE TABLE


mytest=> \d+ t1
                                    Table "public.t1"
 Column |  Type   | Collation | Nullable | Default | Storage | Stats target | Description 
--------+---------+-----------+----------+---------+---------+--------------+-------------
 id     | integer |           |          |         | plain   |              | 



mytest=> \d+ t2
                                    Table "public.t2"
 Column |  Type   | Collation | Nullable | Default | Storage | Stats target | Description 
--------+---------+-----------+----------+---------+---------+--------------+-------------
 id     | integer |           |          |         | plain   |              | 
Has OIDs: yes


mytest=> insert into t1 values(1);
INSERT 0 1

mytest=> insert into t2 values(1);
INSERT 16408 1


mytest=> select oid,* from t1;
ERROR:  column "oid" does not exist
LINE 1: select oid,* from t1;
               ^
HINT:  Perhaps you meant to reference the column "t1.id".


mytest=> select oid,* from t2;
  oid  | id 
-------+----
 16408 |  1
(1 row)

mytest=> 



mytest=> SELECT attrelid,attname FROM pg_attribute WHERE attrelid = 't1'::regclass;
 attrelid | attname  
----------+----------
    16402 | cmax
    16402 | cmin
    16402 | ctid
    16402 | id
    16402 | tableoid
    16402 | xmax
    16402 | xmin
(7 rows)

mytest=> SELECT attrelid,attname FROM pg_attribute WHERE attrelid = 't2'::regclass;
 attrelid | attname  
----------+----------
    16405 | cmax
    16405 | cmin
    16405 | ctid
    16405 | id
    16405 | oid
    16405 | tableoid
    16405 | xmax
    16405 | xmin
(8 rows)

mytest=> select * from t2 where oid=16408;
 id 
----
  1
(1 row)



mytest=> create table t1 (id int);
CREATE TABLE
-- in PG 13.4. (OID desupported in PG12)
mytest=> create table t2 (id int) with (oids=true);
ERROR:  tables declared WITH OIDS are not supported

*/

