create database d1 encoding 'SQL_ASCII' lc_collate 'POSIX' lc_ctype 'POSIX' template 'template0';

/*
template2=> create database d1 encoding 'SQL_ASCII' lc_collate 'POSIX' lc_ctype 'POSIX' template 'template0';
CREATE DATABASE

template2=> create database d2 encoding 'SQL_ASCII' lc_collate 'POSIX' lc_ctype 'POSIX' template 'template1';
ERROR:  new encoding (SQL_ASCII) is incompatible with the encoding of the template database (UTF8)
HINT:  Use the same encoding as in the template database, or use template0 as template.

*/

create database d3 with connection limit 10;

create database d4 with allow_connections = false;

drop database d3;

alter database d4 rename to d3;

alter database d3 with connection limit=20 allow_connections=true;

/*
template2=> \l+ d3
                                                List of databases
 Name |  Owner   | Encoding |   Collate   |    Ctype    | Access privileges |  Size   | Tablespace | Description 
------+----------+----------+-------------+-------------+-------------------+---------+------------+-------------
 d3   | postgres | UTF8     | en_US.UTF-8 | en_US.UTF-8 |                   | 8189 kB | pg_default | 
(1 row)

template2=> \x
Expanded display is on.
template2=> select * from pg_database where datname='d3';
-[ RECORD 1 ]-+------------
oid           | 16422
datname       | d3
datdba        | 16395
encoding      | 6
datcollate    | en_US.UTF-8
datctype      | en_US.UTF-8
datistemplate | f
datallowconn  | t
datconnlimit  | 20
datlastsysoid | 14300
datfrozenxid  | 479
datminmxid    | 1
dattablespace | 1663
datacl        | 
*/

alter database d2 owner to postgres;
alter database d2 owner to current_user;


/*
  In PostgreSQL, a schema is a namespace that contains named database objects. 
  With schemas, users can group objects together in a database. 
  It is a logical collection of objects. 
*/
create schema schemaA;

create schema schemaB
  create table accounts(id serial, name text)
  create index idx_accounts_id on accounts (id);

/*
template2=> create schema schemaA;
CREATE SCHEMA

template2=> create schema schemaB
  create table accounts(id serial, name text)
  create index idx_accounts_id on accounts (id);
CREATE SCHEMA

template2=> \dt schemaB.accounts
           List of relations
 Schema  |   Name   | Type  |  Owner   
---------+----------+-------+----------
 schemab | accounts | table | postgres
(1 row)
*/

alter schema schemaA rename to schemaC;

/*
template2=> alter schema schemaA rename to schemaC;
ALTER SCHEMA

template2=> \dn
  List of schemas
  Name   |  Owner   
---------+----------
 public  | postgres
 schemab | postgres
 schemac | postgres
(3 rows)
*/

drop schema schemaB;
drop schema schemaB cascade;

/*
template2=> drop schema schemaB;
ERROR:  cannot drop schema schemab because other objects depend on it
DETAIL:  table schemab.accounts depends on schema schemab
HINT:  Use DROP ... CASCADE to drop the dependent objects too.

template2=> drop schema schemaB cascade;
NOTICE:  drop cascades to table schemab.accounts
DROP SCHEMA
*/

show search_path;
set search_path=schemaA,"$user",public;

/*

template2=> show search_path;
   search_path   
-----------------
 "$user", public
(1 row)

template2=> set search_path=schemaA,"$user",public;
SET

template2=> show search_path;
       search_path        
--------------------------
 schemaa, "$user", public


template2=> create schema postgres;
CREATE SCHEMA

template2=> create table postgres.a(id int);
CREATE TABLE

template2=> create table public.a(name text);
CREATE TABLE

template2=> \d a
                Table "postgres.a"
 Column |  Type   | Collation | Nullable | Default 
--------+---------+-----------+----------+---------
 id     | integer |           |          | 
                     ^
template2=> create schema schemaA;
CREATE SCHEMA

template2=> create table schemaa.a(a int);
CREATE TABLE

template2=> \d a
                 Table "schemaa.a"
 Column |  Type   | Collation | Nullable | Default 
--------+---------+-----------+----------+---------
 a      | integer |           |          | 

-- create table without schema will be placed in first schema in search_path
template2=> create table b(id int);
CREATE TABLE
template2=> \d b
                 Table "schemaa.b"
 Column |  Type   | Collation | Nullable | Default 
--------+---------+-----------+----------+---------
 id     | integer |           |          | 

*/
-- role level search path take precedence of database level setting
alter role postgres set search_path to schemaA,"$user",public;
select rolconfig from pg_roles where rolname='postgres';

/*

template2=> select rolconfig from pg_roles where rolname='postgres';
                 rolconfig                  
--------------------------------------------
 {"search_path=schemaa, \"$user\", public"}
(1 row)

*/

alter database d2 set search_path to schemaA,public;
select d.datname,dr.setconfig 
from pg_db_role_setting dr 
	join pg_database d on dr.setdatabase=d.oid 
where d.datname='d2';

/*
template2=> select d.datname,dr.setconfig
from pg_db_role_setting dr join pg_database d
on dr.setdatabase=d.oid where d.datname='d2';
 datname |            setconfig            
---------+---------------------------------
 d2      | {"search_path=schemaa, public"}
(1 row)
*/

/* 
   Users, groups, and roles are held at the instance level, not inside the database, 
   because of the specific things that users and groups can access.
*/

create role john login valid until '2021-12-31'

/*	

d2=> \du+ john
                                   List of roles
 Role name |                 Attributes                  | Member of | Description 
-----------+---------------------------------------------+-----------+-------------
 john      | 5 connections                              +| {}        | 
           | Password valid until 2021-12-31 00:00:00+00 |           | 

*/


create role ana login password 'password';

--> ana in admin, admin in bob
create role admin with createdb createrole role ana in role bob;

/*
d2=> create role admin with createdb createrole role ana in role bob;
CREATE ROLE
d
2=> \du ana
           List of roles
 Role name | Attributes | Member of 
-----------+------------+-----------
 ana       |            | {admin}

d2=> \du admin
                        List of roles
 Role name |              Attributes              | Member of 
-----------+--------------------------------------+-----------
 admin     | Create role, Create DB, Cannot login | {bob}

d2=> \du bob
           List of roles
 Role name | Attributes | Member of 
-----------+------------+-----------
 bob       |            | {}

*/

-- CREATE USER is alias for CREATE ROLE, with LOGIN as default.
create user johnd password 'PostgreSQL';
create user johnd_dba createdb createrole;
create user johnd_temp valid until '2021-12-31';

-- CREATE GROUP is alias for CREATE ROLE, group can own database objects
-- when users becomes a member of group, they assume the permission of the group
create group dba_group with user johnd_dba;
create group temp_user;

/*

mytest=> \du+ dba_group;
                   List of roles
 Role name |  Attributes  | Member of | Description 
-----------+--------------+-----------+-------------
 dba_group | Cannot login | {}        | 

mytest=> \du+ johnd_dba;
                         List of roles
 Role name |       Attributes       |  Member of  | Description 
-----------+------------------------+-------------+-------------
 johnd_dba | Create role, Create DB | {dba_group} | 
*/

create table warehouse(id serial, location text);
create table accounts(id serial, name text)


grant update,delete on warehouse to johnd;
grant all on accounts to group temp_user;
revoke update,delete on warehouse from johnd;
grant usage on schema schemaB to johnd;
    

-- cancel / stop transaction based on pid
\x auto
select pid,datname,usename,application_name,client_addr,backend_start,
  xact_start,query_start,wait_event,state,query 
from pg_stat_activity where state in ('active','idle in transaction');

select pg_cancel_backend(17867);
select pg_terminate_backend(16266);

/*


mytest=> select pid,datname,usename,application_name,client_addr,backend_start,
  xact_start,query_start,wait_event,state,query
from pg_stat_activity where state in ('active','idle in transaction');
-[ RECORD 1 ]----+-----------------------------------------------------------------------
pid              | 17867
datname          | mytest
usename          | postgres
application_name | psql
client_addr      | 116.14.204.216
backend_start    | 2021-10-30 02:04:21.910769+00
xact_start       | 2021-10-30 02:07:07.468905+00
query_start      | 2021-10-30 02:07:18.456009+00
wait_event       | transactionid
state            | active
query            | update accounts set name='c' where id=1;
-[ RECORD 2 ]----+-----------------------------------------------------------------------
pid              | 16266
datname          | mytest
usename          | postgres
application_name | psql
client_addr      | 116.14.204.216
backend_start    | 2021-10-30 02:02:58.405224+00
xact_start       | 2021-10-30 02:05:48.296386+00
query_start      | 2021-10-30 02:05:52.194889+00
wait_event       | ClientRead
state            | idle in transaction
query            | update accounts set name='b' where id=1;
-[ RECORD 3 ]----+-----------------------------------------------------------------------
pid              | 30806
datname          | mytest
usename          | postgres
application_name | psql
client_addr      | 116.14.204.216
backend_start    | 2021-10-30 01:47:15.365937+00
xact_start       | 2021-10-30 02:07:22.000924+00
query_start      | 2021-10-30 02:07:22.000924+00
wait_event       | 
state            | active
query            | select pid,datname,usename,application_name,client_addr,backend_start,+
                 |   xact_start,query_start,wait_event,state,query                       +
                 | from pg_stat_activity where state in ('active','idle in transaction');

  

-- behavior after executing cancel in another session:
-- select pg_cancel_backend(17867);
-- take note that can't cancel query contains "idle" state

mytest=> begin;
BEGIN
mytest=*> update accounts set name='c' where id=1;


ERROR:  canceling statement due to user request
CONTEXT:  while updating tuple (0,3) in relation "accounts"
mytest=!> 


-- behavior after executing terminate in another session:
-- select pg_terminate_backend(16266);


mytest=*> commit;
FATAL:  terminating connection due to administrator command
SSL connection has been closed unexpectedly
The connection to the server was lost. Attempting reset: 
Succeeded.
SSL connection (protocol: TLSv1.2, cipher: ECDHE-RSA-AES256-GCM-SHA384, bits: 256, compression: off)
mytest=> 

*/



