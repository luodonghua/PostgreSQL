
-- setup using postgres user (Session 1)

create schema s;

create table s.t1 (i int);

create or replace procedure s.p1 () as $$
begin
  raise notice 'I am in p1!';
end;
$$ language plpgsql;

create or replace procedure p2 () as $$
begin
  raise notice 'I am in p2!';
end;
$$ language plpgsql;

CREATE USER user1 WITH PASSWORD 'xxxxxx';


/*
-- psql with user1 (Session 2)


% psql -h database-1.cluster-c76zsnxguzb3.us-east-1.rds.amazonaws.com -U user1  -d mytest
Password for user user1: 
psql (13.4)
SSL connection (protocol: TLSv1.3, cipher: TLS_AES_256_GCM_SHA384, bits: 256, compression: off)
Type "help" for help.


mytest=> \df s.*
                       List of functions
 Schema | Name | Result data type | Argument data types | Type 
--------+------+------------------+---------------------+------
 s      | p1   |                  |                     | proc
(1 row)

mytest=> \dt s.*
        List of relations
 Schema | Name | Type  |  Owner   
--------+------+-------+----------
 s      | t1   | table | postgres
(1 row)


mytest=> select * from s.t1;
ERROR:  permission denied for schema s
LINE 1: select * from s.t1;
                      ^
mytest=> call s.p1();
ERROR:  permission denied for schema s
LINE 1: call s.p1();
             ^

-- grant using postgres user (Session 1)
mytest=> grant usage on schema s to user1;
GRANT

-- psql with user1 (Session 2)
mytest=> select * from s.t1; 
ERROR:  permission denied for table t1
mytest=> 

-- psql with user1 (Session 2)
mytest=> call s.p1();
NOTICE:  I am in p1!
CALL

-- grant using postgres user (Session 1)
mytest=> grant select on s.t1 to user1;
GRANT


-- psql with user1 (Session 2)
mytest=> select * from s.t1;
 i 
---
(0 rows)
*/

