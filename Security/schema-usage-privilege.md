# Schema USAGE Privilege: the Gate Before Table and Function Privileges

In PostgreSQL, access to an object inside a schema requires two things: the
`USAGE` privilege on the **schema** itself, and the appropriate privilege on the
**object** (e.g. `SELECT` on a table). Without `USAGE` on the schema, every
reference to an object in that schema is rejected — regardless of any
object-level grants.

This is a two-session walkthrough. **Session 1** is the superuser (`postgres`)
doing setup and granting privileges; **Session 2** is `user1` trying to access
the objects.

## Setup (Session 1 — `postgres`)

Create a schema `s`, a table `s.t1`, a procedure `s.p1`, another procedure `p2`
in the default schema, and a login role `user1`:

```sql
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
```

## Connecting as `user1` (Session 2)

```bash
psql -h database-1.cluster-c76zsnxguzb3.us-east-1.rds.amazonaws.com -U user1 -d mytest
```

```text
Password for user user1: 
psql (13.4)
SSL connection (protocol: TLSv1.3, cipher: TLS_AES_256_GCM_SHA384, bits: 256, compression: off)
Type "help" for help.
```

`user1` can **see** the objects in the catalog (listing functions and tables
works), because catalog visibility is not gated by `USAGE`:

```text
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
```

## Denied without schema USAGE

Even though the objects are visible, actually touching them fails with
`permission denied for schema s` — the schema itself is the barrier, so neither
the table nor the procedure can be reached:

```text
mytest=> select * from s.t1;
ERROR:  permission denied for schema s
LINE 1: select * from s.t1;
                      ^
mytest=> call s.p1();
ERROR:  permission denied for schema s
LINE 1: call s.p1();
             ^
```

## Grant USAGE on the schema (Session 1)

```sql
grant usage on schema s to user1;
```

```text
GRANT
```

## After USAGE: procedure runs, table still denied (Session 2)

With `USAGE` granted, the error on the table changes from *"permission denied
for schema s"* to *"permission denied for table t1"* — the schema gate is now
open, but `user1` still lacks `SELECT` on the table:

```text
mytest=> select * from s.t1; 
ERROR:  permission denied for table t1
mytest=> 
```

The procedure `s.p1`, however, now **runs successfully**. By default `PUBLIC`
has `EXECUTE` on new functions/procedures, so once the schema `USAGE` barrier is
removed, no further object grant is needed to call it:

```text
mytest=> call s.p1();
NOTICE:  I am in p1!
CALL
```

## Grant SELECT on the table (Session 1)

```sql
grant select on s.t1 to user1;
```

```text
GRANT
```

## Table access now succeeds (Session 2)

```text
mytest=> select * from s.t1;
 i 
---
(0 rows)
```

## Takeaways

- `USAGE` on a schema is a prerequisite for reaching any object inside it.
  Without it, every table/function reference fails with *"permission denied for
  schema"* — the object-level grants never even come into play.
- Catalog visibility (`\dt`, `\df`) is independent of `USAGE`: a user can list
  objects they cannot access.
- Once `USAGE` is granted, each object still needs its own privilege. Here
  `s.p1` became callable immediately (because `EXECUTE` defaults to `PUBLIC`),
  while `SELECT` on `s.t1` still had to be granted explicitly.
- The error message is the tell: *"permission denied for schema s"* means the
  schema gate; *"permission denied for table t1"* means the object grant.
