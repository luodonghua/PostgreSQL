# Managing PostgreSQL

Common day-to-day server management tasks: creating and altering databases,
working with schemas and the search path, managing roles/users/groups and their
privileges, and inspecting or terminating backend connections. Each section
shows the real commands followed by the captured console output.

## Creating databases

A new database can be created with an explicit encoding, locale, and template.
Using `template0` is required when you want an encoding that differs from the
default template.

```sql
create database d1 encoding 'SQL_ASCII' lc_collate 'POSIX' lc_ctype 'POSIX' template 'template0';
```

Trying to create a database with an encoding incompatible with the template
database (`template1`, which is UTF8 here) fails:

```text
template2=> create database d1 encoding 'SQL_ASCII' lc_collate 'POSIX' lc_ctype 'POSIX' template 'template0';
CREATE DATABASE

template2=> create database d2 encoding 'SQL_ASCII' lc_collate 'POSIX' lc_ctype 'POSIX' template 'template1';
ERROR:  new encoding (SQL_ASCII) is incompatible with the encoding of the template database (UTF8)
HINT:  Use the same encoding as in the template database, or use template0 as template.
```

Databases can also be created with a connection limit or with connections
disallowed:

```sql
create database d3 with connection limit 10;
create database d4 with allow_connections = false;
```

## Altering and dropping databases

Databases can be dropped, renamed, and have their attributes changed after
creation.

```sql
drop database d3;
alter database d4 rename to d3;
alter database d3 with connection limit=20 allow_connections=true;
```

Inspecting the renamed/altered database shows the new connection limit (`20`)
and that connections are allowed (`datallowconn | t`):

```text
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
```

Ownership can be reassigned to a named role or to the current user:

```sql
alter database d2 owner to postgres;
alter database d2 owner to current_user;
```

## Schemas

In PostgreSQL, a schema is a namespace that contains named database objects.
Schemas let users group objects together within a database — a logical
collection of objects. A schema can be created on its own, or together with the
objects it contains in a single statement.

```sql
create schema schemaA;

create schema schemaB
  create table accounts(id serial, name text)
  create index idx_accounts_id on accounts (id);
```

The combined statement creates the schema and its table in one step:

```text
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
```

Schemas can be renamed:

```sql
alter schema schemaA rename to schemaC;
```

```text
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
```

Dropping a schema that still contains objects fails unless `CASCADE` is used,
which drops the dependent objects too:

```sql
drop schema schemaB;
drop schema schemaB cascade;
```

```text
template2=> drop schema schemaB;
ERROR:  cannot drop schema schemab because other objects depend on it
DETAIL:  table schemab.accounts depends on schema schemab
HINT:  Use DROP ... CASCADE to drop the dependent objects too.

template2=> drop schema schemaB cascade;
NOTICE:  drop cascades to table schemab.accounts
DROP SCHEMA
```

## The search path

The `search_path` controls which schemas are searched (and in what order) when
an object is referenced without a schema qualifier. The default includes the
special `"$user"` entry and `public`.

```sql
show search_path;
set search_path=schemaA,"$user",public;
```

Setting the search path puts the listed schemas at the front. The example below
also demonstrates that an unqualified object reference resolves to the first
matching schema, and that an unqualified `CREATE TABLE` lands in the first
schema on the path:

```text
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
```

### Role- and database-level search path

A `search_path` set at the role level takes precedence over the database-level
setting. The role setting is stored in `pg_roles.rolconfig`:

```sql
alter role postgres set search_path to schemaA,"$user",public;
select rolconfig from pg_roles where rolname='postgres';
```

```text
template2=> select rolconfig from pg_roles where rolname='postgres';
                 rolconfig                  
--------------------------------------------
 {"search_path=schemaa, \"$user\", public"}
(1 row)
```

A database-level setting is stored in `pg_db_role_setting`:

```sql
alter database d2 set search_path to schemaA,public;
select d.datname,dr.setconfig 
from pg_db_role_setting dr 
	join pg_database d on dr.setdatabase=d.oid 
where d.datname='d2';
```

```text
template2=> select d.datname,dr.setconfig
from pg_db_role_setting dr join pg_database d
on dr.setdatabase=d.oid where d.datname='d2';
 datname |            setconfig            
---------+---------------------------------
 d2      | {"search_path=schemaa, public"}
(1 row)
```

## Roles, users, and groups

Users, groups, and roles are held at the instance level, not inside a database,
because of the specific things that users and groups can access.

A login role can be created with an expiry date:

```sql
create role john login valid until '2021-12-31';
```

```text
d2=> \du+ john
                                   List of roles
 Role name |                 Attributes                  | Member of | Description 
-----------+---------------------------------------------+-----------+-------------
 john      | 5 connections                              +| {}        | 
           | Password valid until 2021-12-31 00:00:00+00 |           | 
```

Roles can be given a password and granted administrative attributes, and
membership relationships can be established at creation time. Here `ana` is made
a member of `admin`, and `admin` is made a member of `bob`:

```sql
create role ana login password 'password';
create role admin with createdb createrole role ana in role bob;
```

```text
d2=> create role admin with createdb createrole role ana in role bob;
CREATE ROLE
d2=> \du ana
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
```

`CREATE USER` is an alias for `CREATE ROLE` with `LOGIN` as the default:

```sql
create user johnd password 'PostgreSQL';
create user johnd_dba createdb createrole;
create user johnd_temp valid until '2021-12-31';
```

`CREATE GROUP` is also an alias for `CREATE ROLE`. A group can own database
objects, and when users become members of a group they assume the group's
permissions:

```sql
create group dba_group with user johnd_dba;
create group temp_user;
```

```text
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
```

## Granting and revoking privileges

Object privileges can be granted to and revoked from roles and groups:

```sql
create table warehouse(id serial, location text);
create table accounts(id serial, name text);

grant update,delete on warehouse to johnd;
grant all on accounts to group temp_user;
revoke update,delete on warehouse from johnd;
grant usage on schema schemaB to johnd;
```

## Inspecting and terminating connections

Active sessions and open transactions can be inspected via `pg_stat_activity`.
A specific backend's current query can be cancelled with `pg_cancel_backend`, or
the whole connection terminated with `pg_terminate_backend`, using the backend
process id (`pid`).

```sql
\x auto
select pid,datname,usename,application_name,client_addr,backend_start,
  xact_start,query_start,wait_event,state,query 
from pg_stat_activity where state in ('active','idle in transaction');

select pg_cancel_backend(17867);
select pg_terminate_backend(16266);
```

The activity view shows the running update (`active`, pid 17867), an open
transaction waiting on client input (`idle in transaction`, pid 16266), and the
monitoring query itself:

```text
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
```

Note that you cannot cancel a query in the `idle in transaction` state —
`pg_cancel_backend` only interrupts an actively running statement.

When `pg_cancel_backend(17867)` runs in another session, the active statement
in that session is cancelled while the transaction stays open (note the `=!>`
prompt indicating a failed transaction block):

```text
mytest=> begin;
BEGIN
mytest=*> update accounts set name='c' where id=1;


ERROR:  canceling statement due to user request
CONTEXT:  while updating tuple (0,3) in relation "accounts"
mytest=!> 
```

When `pg_terminate_backend(16266)` runs against the idle-in-transaction session,
the entire connection is dropped; psql reports the lost connection and
automatically reconnects:

```text
mytest=*> commit;
FATAL:  terminating connection due to administrator command
SSL connection has been closed unexpectedly
The connection to the server was lost. Attempting reset: 
Succeeded.
SSL connection (protocol: TLSv1.2, cipher: ECDHE-RSA-AES256-GCM-SHA384, bits: 256, compression: off)
mytest=> 
```

## Takeaways

- Use `template0` when creating a database with a non-default encoding; using
  `template1` fails if the encodings are incompatible.
- `ALTER DATABASE` can rename, change connection limits, toggle
  `allow_connections`, reassign ownership, and set a per-database `search_path`.
- A schema is a namespace; drop a non-empty schema with `CASCADE`, which also
  drops dependent objects.
- Unqualified object references and `CREATE TABLE` resolve against the first
  schema in the `search_path`; a role-level `search_path` takes precedence over
  the database-level one.
- Roles, users, and groups are instance-level objects. `CREATE USER` adds
  `LOGIN` by default; `CREATE GROUP` creates a role that cannot log in but can
  own objects and confer its permissions to members.
- Inspect sessions with `pg_stat_activity`. `pg_cancel_backend` cancels an
  active statement (but not an idle-in-transaction one), while
  `pg_terminate_backend` drops the whole connection.
