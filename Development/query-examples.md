# Assorted Query Examples

A grab-bag of PostgreSQL query idioms and their output, using the `t_oil`
dataset (see [`load-data-t-oil.sql`](load-data-t-oil.sql)) plus
`generate_series`.

## `LIMIT`, `FETCH FIRST`, and `TABLE`

Three equivalent ways to get one row:

```sql
SELECT * FROM t_oil LIMIT 1;
SELECT * FROM t_oil FETCH FIRST 1 ROWS ONLY;
TABLE t_oil LIMIT 1;
```

```text
    region     | country | year | production | consumption
---------------+---------+------+------------+-------------
 North America | USA     | 1965 |       9014 |       11522
```

## String building: `format()` vs `||`

```sql
SELECT format('[%s] %s', region, country) AS region_country1,
       '[' || region || '] ' || country   AS region_country2,
       region, country
FROM t_oil LIMIT 1;
```

```text
   region_country1   |   region_country2   |    region     | country
---------------------+---------------------+---------------+---------
 [North America] USA | [North America] USA | North America | USA
```

`format()` is clearer and avoids NULL propagation surprises (`||` yields NULL if
any operand is NULL).

## Date parts with `extract()` / `to_char()`

```sql
SELECT date::date,
       extract('isodow'  FROM date) AS dow,
       to_char(date, 'dy')          AS day,
       extract('isoyear' FROM date) AS "iso year",
       extract('week'    FROM date) AS week,
       extract('day' FROM (date + interval '2 month - 1 day')) AS feb,
       extract('year'    FROM date) AS year,
       extract('day' FROM (date + interval '2 month - 1 day')) = 29 AS leap
FROM generate_series(date '2000-01-01', date '2010-01-01', interval '1 year') AS t(date);
```

```text
    date    | dow | day | iso year | week | feb | year | leap
------------+-----+-----+----------+------+-----+------+------
 2000-01-01 |   6 | sat |     1999 |   52 |  29 | 2000 | t
 2001-01-01 |   1 | mon |     2001 |    1 |  28 | 2001 | f
 2004-01-01 |   4 | thu |     2004 |    1 |  29 | 2004 | t
 2005-01-01 |   6 | sat |     2004 |   53 |  28 | 2005 | f
 ...
(11 rows)
```

Note how ISO year/week differ from calendar year around Jan 1 (e.g. 2000-01-01
is ISO year 1999, week 52), and the `feb = 29` column detects leap years.

## `NOT IN (NULL)` — a classic NULL trap

```sql
SELECT x FROM generate_series(1,5) AS t(x) WHERE x NOT IN (1,2,3);          -- 4,5
SELECT x FROM generate_series(1,5) AS t(x) WHERE x NOT IN (NULL);           -- 0 rows!
SELECT x FROM generate_series(1,5) AS t(x) WHERE x IN (NULL);               -- 0 rows
SELECT x FROM generate_series(1,5) AS t(x) WHERE x NOT IN (coalesce(NULL,-1)); -- 1..5
```

`x NOT IN (NULL)` returns **no rows**: `x <> NULL` is `UNKNOWN`, never `TRUE`, so
every row is filtered out. This is one of the most common SQL bugs — guard list
contents against NULLs (e.g. with `coalesce`) or use `NOT EXISTS`.

## Three-valued logic: `=` vs `IS DISTINCT FROM`

```sql
SELECT a::text AS left, b::text AS right,
       (a = b)::text                   AS "=",
       (a <> b)::text                  AS "<>",
       (a IS DISTINCT FROM b)::text     AS "is distinct",
       (a IS NOT DISTINCT FROM b)::text AS "is not distinct from"
FROM       (values(true),(false),(null)) v1(a)
CROSS JOIN (values(true),(false),(null)) v2(b);
```

```text
 left  | right |   =   |  <>   | is distinct | is not distinct from
-------+-------+-------+-------+-------------+----------------------
 true  | true  | true  | false | false       | true
 true  |       |       |       | true        | false
       |       |       |       | false       | true
 ...
(9 rows)
```

`=` / `<>` return NULL when either side is NULL; `IS [NOT] DISTINCT FROM` treats
NULL as a comparable value (NULL is "not distinct from" NULL). Also:

```sql
SELECT (null IS NULL) AS is_null, (null IS NOT NULL) AS is_not_null;  -- t | f
```

## Window functions

Running array aggregate:

```sql
SELECT x, array_agg(x) OVER (ORDER BY x)
FROM generate_series(1,3) AS t(x);
```

```text
 x | array_agg
---+-----------
 1 | {1}
 2 | {1,2}
 3 | {1,2,3}
```

`row_number()` partitioned per country:

```sql
SELECT row_number() OVER (PARTITION BY country ORDER BY year DESC), *
FROM t_oil WHERE country IN ('USA','Israel') ORDER BY year DESC LIMIT 10;
```

```text
 row_number |    region     | country | year | production | consumption
------------+---------------+---------+------+------------+-------------
          1 | North America | USA     | 2010 |       7513 |       19180
          1 | Middle East   | Israel  | 2010 |            |         234
          2 | Middle East   | Israel  | 2009 |            |         237
          ...
(10 rows)
```
