# Choosing the Right Data Type

The same temporal value — a point in time — can be stored in several different
column types: an `int` epoch, a `bigint` packed `YYYYMMDDHH24MISS`, a
fixed-width `char(14)` string, or a native `timestamp`. They are not equivalent
on disk or at query time. This benchmark loads 10 million rows into each
representation and compares **on-disk size** (tables and indexes) and
**query performance** of range scans.

The takeaway up front: `int` is the smallest, `timestamp` and `bigint` are both
8 bytes, and `char(14)` is by far the largest and the most prone to
type-coercion surprises.

## One table, four representations of the same instant

The first experiment puts all four types side by side in a single table and
loads 10 million one-second-apart timestamps, each written four ways.

```sql
create table t (col_int int,col_bigint bigint,col_char char(14),col_timestamp timestamp);
create index idx_int        on t(col_int);
create index idx_bigint     on t(col_bigint);
create index idx_char       on t(col_char);
create index idx_timestamp  on t(col_timestamp);

insert into t
with m10 as (
  select to_timestamp('2010-01-01 00:00:00','YYYY-MM-DD HH24:MI:SS')+
           concat(generate_series,' seconds')::interval as i
  from generate_series(1,10000000))
select extract(epoch from i),
       to_char(i,'YYYYMMDDHH24MISS')::bigint,
       to_char(i,'YYYYMMDDHH24MISS'),
       i
from m10;

select timestamp 'epoch'+col_int*interval '1 second' from t;
```

Checking the table and index sizes:

```text
mytest=> \dt+ t
                           List of relations
 Schema | Name | Type  |  Owner   | Persistence |  Size  | Description
--------+------+-------+----------+-------------+--------+-------------
 public | t    | table | postgres | permanent   | 651 MB |
(1 row)

mytest=> \diS+ idx*
                                   List of relations
 Schema |     Name      | Type  |  Owner   | Table | Persistence |  Size  | Description
--------+---------------+-------+----------+-------+-------------+--------+-------------
 public | idx_bigint    | index | postgres | t     | permanent   | 214 MB |
 public | idx_char      | index | postgres | t     | permanent   | 301 MB |
 public | idx_int       | index | postgres | t     | permanent   | 214 MB |
 public | idx_timestamp | index | postgres | t     | permanent   | 214 MB |
(4 rows)
```

Even in a mixed table, the index on `char(14)` is already noticeably larger
(301 MB) than the `int`, `bigint`, or `timestamp` indexes (214 MB each). The
8-byte `bigint` and `timestamp` indexes are the same size, as expected.

## Isolating each type in its own table

To measure table size per type cleanly, each representation gets its own table
with five identical columns and an index on the first.

```sql
create table t_int (col1 int, col2 int, col3 int, col4 int, col5 int);
create index idx_int on t_int(col1);

create table t_bigint (col1 bigint, col2 bigint, col3 bigint, col4 bigint, col5 bigint);
create index idx_bigint on t_bigint(col1);

create table t_char(col1 char(14), col2 char(14), col3 char(14), col4 char(14), col5 char(14));
create index idx_char on t_char(col1);

create table t_timestamp(col1 timestamp, col2 timestamp, col3 timestamp, col4 timestamp, col5 timestamp);
create index idx_timestamp on t_timestamp(col1);
```

Immediately after creation, all tables and indexes are empty:

```text
mytest=> \di+
                                        List of relations
 Schema |     Name      | Type  |  Owner   |    Table    | Persistence |    Size    | Description
--------+---------------+-------+----------+-------------+-------------+------------+-------------
 public | idx_bigint    | index | postgres | t_bigint    | permanent   | 8192 bytes |
 public | idx_char      | index | postgres | t_char      | permanent   | 8192 bytes |
 public | idx_int       | index | postgres | t_int       | permanent   | 8192 bytes |
 public | idx_timestamp | index | postgres | t_timestamp | permanent   | 8192 bytes |
(4 rows)

mytest=> \dt+
                               List of relations
 Schema |    Name     | Type  |  Owner   | Persistence |  Size   | Description
--------+-------------+-------+----------+-------------+---------+-------------
 public | t_bigint    | table | postgres | permanent   | 0 bytes |
 public | t_char      | table | postgres | permanent   | 0 bytes |
 public | t_int       | table | postgres | permanent   | 0 bytes |
 public | t_timestamp | table | postgres | permanent   | 0 bytes |
(4 rows)
```

## Loading 10 million rows into each table

Each table is loaded with the same 10 million instants, converted into its
respective representation.

```sql
insert into t_int
with m10 as (
  select to_timestamp('2010-10-01 00:00:00','YYYY-MM-DD HH24:MI:SS')+
           concat(generate_series,' seconds')::interval as i
  from generate_series(1,10000000))
select extract(epoch from i),
       extract(epoch from i),
       extract(epoch from i),
       extract(epoch from i),
       extract(epoch from i)
from m10;

insert into t_bigint
with m10 as (
  select to_timestamp('2010-10-01 00:00:00','YYYY-MM-DD HH24:MI:SS')+
           concat(generate_series,' seconds')::interval as i
  from generate_series(1,10000000))
select to_char(i,'YYYYMMDDHH24MISS')::bigint,
       to_char(i,'YYYYMMDDHH24MISS')::bigint,
       to_char(i,'YYYYMMDDHH24MISS')::bigint,
       to_char(i,'YYYYMMDDHH24MISS')::bigint,
       to_char(i,'YYYYMMDDHH24MISS')::bigint
 from m10;

insert into t_char
with m10 as (
  select to_timestamp('2010-10-01 00:00:00','YYYY-MM-DD HH24:MI:SS')+
           concat(generate_series,' seconds')::interval as i
  from generate_series(1,10000000))
select to_char(i,'YYYYMMDDHH24MISS'),
       to_char(i,'YYYYMMDDHH24MISS'),
       to_char(i,'YYYYMMDDHH24MISS'),
       to_char(i,'YYYYMMDDHH24MISS'),
       to_char(i,'YYYYMMDDHH24MISS')
        from m10;

insert into t_timestamp
with m10 as (
  select to_timestamp('2010-10-01 00:00:00','YYYY-MM-DD HH24:MI:SS')+
           concat(generate_series,' seconds')::interval as i
  from generate_series(1,10000000))
select i,i,i,i,i from m10;
```

## Size comparison after the load

With all four tables populated, the size differences become stark:

```text
mytest=> \dt+
                               List of relations
 Schema |    Name     | Type  |  Owner   | Persistence |  Size   | Description
--------+-------------+-------+----------+-------------+---------+-------------
 public | t_bigint    | table | postgres | permanent   | 651 MB  |
 public | t_char      | table | postgres | permanent   | 1042 MB |
 public | t_int       | table | postgres | permanent   | 498 MB  |
 public | t_timestamp | table | postgres | permanent   | 651 MB  |
(4 rows)

mytest=> \di+
                                      List of relations
 Schema |     Name      | Type  |  Owner   |    Table    | Persistence |  Size  | Description
--------+---------------+-------+----------+-------------+-------------+--------+-------------
 public | idx_bigint    | index | postgres | t_bigint    | permanent   | 214 MB |
 public | idx_char      | index | postgres | t_char      | permanent   | 301 MB |
 public | idx_int       | index | postgres | t_int       | permanent   | 214 MB |
 public | idx_timestamp | index | postgres | t_timestamp | permanent   | 214 MB |
(4 rows)
```

Reading the table sizes:

- `t_int` is the smallest at **498 MB** — a 4-byte `int` per column.
- `t_bigint` and `t_timestamp` are both **651 MB** — each stores 8 bytes per
  column, so they tie.
- `t_char` is the largest at **1042 MB** — a fixed-width `char(14)` consumes 14
  bytes per column plus length overhead, roughly double the `int` table.

The index sizes mirror this: `int`, `bigint`, and `timestamp` indexes are all
**214 MB**, while the `char(14)` index is **301 MB**.

## Range scan on the int table

A range query on `t_int` filters by epoch seconds and uses the index.

```sql
explain analyze verbose
select * from t_int
where col1 between extract(epoch from to_timestamp('2010-10-30 23:59:59','YYYY-MM-DD HH24:MI:SS'))::int
and extract(epoch from to_timestamp('2010-11-01 00:00:01','YYYY-MM-DD HH24:MI:SS'))::int;
```

A representative run (using a slightly different date window) returns three rows
and shows the planner choosing an index scan:

```text
mytest=> select * from t_int
mytest-> where col1 between extract(epoch from to_timestamp('2010-01-31 23:59:59','YYYY-MM-DD HH24:MI:SS'))::int
mytest->                and extract(epoch from to_timestamp('2010-02-01 00:00:01','YYYY-MM-DD HH24:MI:SS'))::int
mytest-> ;
    col1    |    col2    |    col3    |    col4    |    col5
------------+------------+------------+------------+------------
 1264982399 | 1264982399 | 1264982399 | 1264982399 | 1264982399
 1264982400 | 1264982400 | 1264982400 | 1264982400 | 1264982400
 1264982401 | 1264982401 | 1264982401 | 1264982401 | 1264982401
(3 rows)

Time: 216.414 ms
mytest=> explain analyze verbose
mytest-> select * from t_int
mytest-> where col1 between extract(epoch from to_timestamp('2010-01-31 23:59:59','YYYY-MM-DD HH24:MI:SS'))::int
mytest->                and extract(epoch from to_timestamp('2010-02-01 00:00:01','YYYY-MM-DD HH24:MI:SS'))::int;
                                                                                                                                   QUERY PLAN
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Index Scan using idx_int on public.t_int  (cost=0.45..8.51 rows=3 width=20) (actual time=0.019..0.021 rows=3 loops=1)
   Output: col1, col2, col3, col4, col5
   Index Cond: ((t_int.col1 >= (date_part('epoch'::text, to_timestamp('2010-01-31 23:59:59'::text, 'YYYY-MM-DD HH24:MI:SS'::text)))::integer) AND (t_int.col1 <= (date_part('epoch'::text, to_timestamp('2010-02-01 00:00:01'::text, 'YYYY-MM-DD HH24:MI:SS'::text)))::integer))
 Planning Time: 0.088 ms
 Execution Time: 0.036 ms
(5 rows)

Time: 214.318 ms
```

The index scan is efficient: `Execution Time: 0.036 ms` for the three matching
rows out of 10 million.

## Range scans on the other representations

The equivalent range predicates for the `bigint`, `char`, and `timestamp`
tables each convert the boundary instants into the matching representation.

```sql
explain analyze verbose
select * from t_int
where col1 between extract(epoch from to_timestamp('2010-01-31 23:59:59','YYYY-MM-DD HH24:MI:SS'))::int
and extract(epoch from to_timestamp('2010-02-01 00:00:01','YYYY-MM-DD HH24:MI:SS'))::int;

explain analyze verbose
select * from t_bigint
where col1 between  to_char(to_timestamp('2010-01-31 23:59:59','YYYY-MM-DD HH24:MI:SS'),'YYYYMMDDHH24MISS')::bigint
and to_char(to_timestamp('2010-02-01 00:00:01','YYYY-MM-DD HH24:MI:SS'),'YYYYMMDDHH24MISS')::bigint;

explain analyze verbose
select * from t_char
where col1 between  '2010-01-31 23:59:59'
and '2010-02-01 00:00:01';

explain analyze verbose
select * from t_timestamp
where col1 between  to_timestamp('2010-01-31 23:59:59','YYYY-MM-DD HH24:MI:SS')
and to_timestamp('2010-02-01 00:00:01','YYYY-MM-DD HH24:MI:SS');
```

Querying `t_char` by the packed `YYYYMMDDHH24MISS` form returns the expected
three rows — but note the elapsed time:

```text
mytest=> select * from t_char
mytest-> where col1 between  to_char(to_timestamp('2010-01-31 23:59:59','YYYY-MM-DD HH24:MI:SS'),'YYYYMMDDHH24MISS')
mytest-> and to_char(to_timestamp('2010-02-01 00:00:01','YYYY-MM-DD HH24:MI:SS'),'YYYYMMDDHH24MISS');
      col1      |      col2      |      col3      |      col4      |      col5
----------------+----------------+----------------+----------------+----------------
 20100131235959 | 20100131235959 | 20100131235959 | 20100131235959 | 20100131235959
 20100201000000 | 20100201000000 | 20100201000000 | 20100201000000 | 20100201000000
 20100201000001 | 20100201000001 | 20100201000001 | 20100201000001 | 20100201000001
(3 rows)

Time: 24533.995 ms (00:24.534)
```

At **24.5 seconds**, this `char` query is dramatically slower than the
sub-millisecond `int` index scan above — a sign that the predicate did not use
the index efficiently.

## Additional range queries across the data set

Further variations exercise wider windows and different boundary expressions
against each table:

```sql
explain analyze verbose
select * from t_int
where col1 between extract(epoch from to_timestamp('2010-10-31 23:59:59','YYYY-MM-DD HH24:MI:SS'))::int
and extract(epoch from to_timestamp('2010-11-01 00:00:01','YYYY-MM-DD HH24:MI:SS'))::int;

explain analyze verbose
select * from t_int
where col1 between extract(epoch from to_timestamp('2010-01-31 23:59:59','YYYY-MM-DD HH24:MI:SS'))::int
and extract(epoch from to_timestamp('2010-11-01 00:00:01','YYYY-MM-DD HH24:MI:SS'))::int;

explain analyze verbose
select * from t_bigint
where col1 between  to_char(to_timestamp('2010-10-31 23:59:59','YYYY-MM-DD HH24:MI:SS'),'YYYYMMDDHH24MISS')::bigint
and to_char(to_timestamp('2010-11-01 00:00:01','YYYY-MM-DD HH24:MI:SS'),'YYYYMMDDHH24MISS')::bigint;

explain analyze verbose
select * from t_bigint
where col1 between  20101031235959 and 20101101000001;

explain analyze verbose
select * from t_char
where col1 between  to_char(to_timestamp('2010-10-31 23:59:59','YYYY-MM-DD HH24:MI:SS'),'YYYYMMDDHH24MISS')
and to_char(to_timestamp('2010-11-01 00:00:01','YYYY-MM-DD HH24:MI:SS'),'YYYYMMDDHH24MISS');

explain analyze verbose
select * from t_char
where col1 between  '20101031235959' and '20101101000001';

explain analyze verbose
select * from t_timestamp
where col1 between  to_timestamp('2010-12-31 23:59:59','YYYY-MM-DD HH24:MI:SS')
and to_timestamp('2011-01-01 00:00:01','YYYY-MM-DD HH24:MI:SS');

explain analyze verbose
select * from t_bigint
where col1 between  to_char(to_timestamp('2010-12-31 23:59:59','YYYY-MM-DD HH24:MI:SS'),'YYYYMMDDHH24MISS')::bigint
and to_char(to_timestamp('2011-01-01 00:00:01','YYYY-MM-DD HH24:MI:SS'),'YYYYMMDDHH24MISS')::bigint;

explain analyze verbose
select * from t_char
where col1 between to_char(to_timestamp('2010-10-31 23:59:59','YYYY-MM-DD HH24:MI:SS'),'YYYYMMDDHH24MISS')
               and to_char(to_timestamp('2010-11-01 00:00:01','YYYY-MM-DD HH24:MI:SS'),'YYYYMMDDHH24MISS');
```

## Cross-check: the same char query on Oracle 19c

For comparison, the source captures the Oracle 19c plan for the equivalent
`char` range query. First an Oracle-style load (using `connect by level` and
`dual`) populates the table, then `explain plan` is run two ways — once with the
`to_char` boundary expressions and once with literal strings.

```sql
insert into t_char
with m10 as (
  select to_timestamp('2010-10-01 00:00:00','YYYY-MM-DD HH24:MI:SS')+rownum/(24*60*60) as i
  from (select level from dual connect by level <=10000), (select level from dual connect by level <=1000))
select to_char(i,'YYYYMMDDHH24MISS'),
       to_char(i,'YYYYMMDDHH24MISS'),
       to_char(i,'YYYYMMDDHH24MISS'),
       to_char(i,'YYYYMMDDHH24MISS'),
       to_char(i,'YYYYMMDDHH24MISS')
        from m10;

explain plan for
select * from t_char
where col1 between to_char(to_timestamp('2010-10-31 23:59:59','YYYY-MM-DD HH24:MI:SS'),'YYYYMMDDHH24MISS')
               and to_char(to_timestamp('2010-11-01 00:00:01','YYYY-MM-DD HH24:MI:SS'),'YYYYMMDDHH24MISS');
```

Oracle chooses an `INDEX RANGE SCAN` on `IDX_CHAR` in both forms. The captured
`dbms_xplan` output (abbreviated — the two plans are identical):

```text
SQL> explain plan for
  2  select * from t_char
  3  where col1 between to_char(to_timestamp('2010-10-31 23:59:59','YYYY-MM-DD HH24:MI:SS'),'YYYYMMDDHH24MISS')
  4*                and to_char(to_timestamp('2010-11-01 00:00:01','YYYY-MM-DD HH24:MI:SS'),'YYYYMMDDHH24MISS');

Explained.

Elapsed: 00:00:00.218
SQL> select * from dbms_xplan.display(format=>'ADVANCED');

                                                                                  PLAN_TABLE_OUTPUT
___________________________________________________________________________________________________
Plan hash value: 4039861024

------------------------------------------------------------------------------------------------
| Id  | Operation                           | Name     | Rows  | Bytes | Cost (%CPU)| Time     |
------------------------------------------------------------------------------------------------
|   0 | SELECT STATEMENT                    |          | 76471 |  5600K|  1338   (1)| 00:00:01 |
|   1 |  TABLE ACCESS BY INDEX ROWID BATCHED| T_CHAR   | 76471 |  5600K|  1338   (1)| 00:00:01 |
|*  2 |   INDEX RANGE SCAN                  | IDX_CHAR | 76471 |       |   247   (1)| 00:00:01 |
------------------------------------------------------------------------------------------------

Query Block Name / Object Alias (identified by operation id):
-------------------------------------------------------------

   1 - SEL$1 / T_CHAR@SEL$1
   2 - SEL$1 / T_CHAR@SEL$1

Predicate Information (identified by operation id):
---------------------------------------------------

   2 - access("COL1">='20101031235959' AND "COL1"<='20101101000001')

... (Outline Data, Column Projection, and Query Block Registry sections omitted)

50 rows selected.

Elapsed: 00:00:00.553
SQL>

SQL> explain plan for
  2  select * from t_char
  3* where col1 between  '20101031235959' and '20101101000001';

Explained.

... (identical plan: Plan hash value 4039861024, INDEX RANGE SCAN on IDX_CHAR)

50 rows selected.

Elapsed: 00:00:00.470
SQL>
```

Oracle happily uses the index for the `char` range scan in both forms — the
plan hash value `4039861024` is the same either way.

## Why the PostgreSQL char query was slow: coercion matters

Back in PostgreSQL, the difference comes down to how the boundary expressions
are typed. When the boundaries are explicitly cast to `bpchar` (the internal
name for `char(n)`), the planner can use the index directly:

```sql
explain analyze verbose
select * from t_char
where col1 between  to_char(to_timestamp('2010-10-31 23:59:59','YYYY-MM-DD HH24:MI:SS'),'YYYYMMDDHH24MISS')::bpchar
and to_char(to_timestamp('2010-11-01 00:00:01','YYYY-MM-DD HH24:MI:SS'),'YYYYMMDDHH24MISS')::bpchar;
```

```text
test=# explain
test-# select * from t_char
test-# where col1 between  to_char(to_timestamp('2010-10-31 23:59:59','YYYY-MM-DD HH24:MI:SS'),'YYYYMMDDHH24MISS')::bpchar
test-# and to_char(to_timestamp('2010-11-01 00:00:01','YYYY-MM-DD HH24:MI:SS'),'YYYYMMDDHH24MISS')::bpchar;
                                                                                                                                     QUERY PLAN
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Index Scan using idx_char on t_char  (cost=0.45..4881.44 rows=100000 width=75)
   Index Cond: ((col1 >= (to_char(to_timestamp('2010-10-31 23:59:59'::text, 'YYYY-MM-DD HH24:MI:SS'::text), 'YYYYMMDDHH24MISS'::text))::bpchar) AND (col1 <= (to_char(to_timestamp('2010-11-01 00:00:01'::text, 'YYYY-MM-DD HH24:MI:SS'::text), 'YYYYMMDDHH24MISS'::text))::bpchar))
(2 rows)
```

With the explicit `::bpchar` cast matching the column type, the predicate
becomes an `Index Cond` and the planner uses `idx_char` as an index scan.

```sql
explain
select * from t_char
where col2 between  to_char(to_timestamp('2010-10-31 23:59:59','YYYY-MM-DD HH24:MI:SS'),'YYYYMMDDHH24MISS')::char(14)
and to_char(to_timestamp('2010-11-01 00:00:01','YYYY-MM-DD HH24:MI:SS'),'YYYYMMDDHH24MISS')::char(14);
```

## Changing char(14) to varchar(14)

Altering the column type to `varchar(14)` changes the picture again — the plan
drops to a bitmap heap scan with a recheck, because the comparison is now done
through a `text` cast:

```sql
alter table t_char alter column col1 type varchar(14);

explain
select * from t_char
where col1 between  to_char(to_timestamp('2010-10-31 23:59:59','YYYY-MM-DD HH24:MI:SS'),'YYYYMMDDHH24MISS')
and to_char(to_timestamp('2010-11-01 00:00:01','YYYY-MM-DD HH24:MI:SS'),'YYYYMMDDHH24MISS');
```

```text
test=# alter table t_char alter column col1 type varchar(14);
ALTER TABLE
Time: 62798.041 ms (01:02.798)
test=# explain select * from t_char
test-# where col1 between  to_char(to_timestamp('2010-10-31 23:59:59','YYYY-MM-DD HH24:MI:SS'),'YYYYMMDDHH24MISS')
test-# and to_char(to_timestamp('2010-11-01 00:00:01','YYYY-MM-DD HH24:MI:SS'),'YYYYMMDDHH24MISS');
                                                                                                                                      QUERY PLAN
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Bitmap Heap Scan on t_char  (cost=1284.94..99973.91 rows=50000 width=106)
   Recheck Cond: (((col1)::text >= to_char(to_timestamp('2010-10-31 23:59:59'::text, 'YYYY-MM-DD HH24:MI:SS'::text), 'YYYYMMDDHH24MISS'::text)) AND ((col1)::text <= to_char(to_timestamp('2010-11-01 00:00:01'::text, 'YYYY-MM-DD HH24:MI:SS'::text), 'YYYYMMDDHH24MISS'::text)))
   ->  Bitmap Index Scan on idx_char  (cost=0.00..1272.44 rows=50000 width=0)
         Index Cond: (((col1)::text >= to_char(to_timestamp('2010-10-31 23:59:59'::text, 'YYYY-MM-DD HH24:MI:SS'::text), 'YYYYMMDDHH24MISS'::text)) AND ((col1)::text <= to_char(to_timestamp('2010-11-01 00:00:01'::text, 'YYYY-MM-DD HH24:MI:SS'::text), 'YYYYMMDDHH24MISS'::text)))
(4 rows)

Time: 3.101 ms
```

Note that the `ALTER TABLE ... TYPE varchar(14)` rewrites the whole table and
took **62.8 seconds** on this data set. The resulting plan compares via
`(col1)::text`, so the index is still usable (as a bitmap index scan) but the
comparison semantics have shifted from `bpchar` to `text`.

## Takeaways

- **`int` is the smallest** on-disk representation for this temporal data:
  `t_int` was 498 MB versus 651 MB for `bigint`/`timestamp` and 1042 MB for
  `char(14)`.
- **`timestamp` and `bigint` are both 8 bytes**, so their tables (651 MB) and
  indexes (214 MB) come out identical in size. A native `timestamp` gives you
  the same footprint as a packed `bigint` while keeping real date/time
  semantics.
- **`char(14)` is by far the largest** — roughly double the `int` table and with
  a 301 MB index versus 214 MB for the numeric/timestamp types.
- **Type coercion decides whether the index is used.** In PostgreSQL the
  "natural" `char` range query ran for 24.5 seconds, but casting the boundaries
  to `::bpchar` to match the column type produced a clean index scan.
- **Changing `char(14)` to `varchar(14)` rewrites the table** (62.8 s here) and
  shifts comparisons to `text`, yielding a bitmap heap scan with a recheck
  condition rather than a plain index scan.
- Prefer a native `timestamp` for temporal data: it matches `bigint` on size,
  keeps proper date semantics, and avoids the string-comparison and coercion
  pitfalls of storing timestamps as `char`/`varchar`.
