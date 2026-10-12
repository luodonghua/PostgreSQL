# `timestamp` vs `timestamp with time zone`

How PostgreSQL stores and displays `timestamp` (without time zone) versus
`timestamptz` (with time zone), and why the displayed value of a `timestamptz`
depends on the session `TimeZone`.

## Session time zone and the catalog of zones

```sql
SHOW timezone;   -- UTC

SELECT * FROM pg_timezone_names
WHERE name LIKE '%Singapore%' OR name LIKE '%Sydney%';
```

```text
       name       | abbrev | utc_offset | is_dst
------------------+--------+------------+--------
 Australia/Sydney | AEDT   | 11:00:00   | t
 Singapore        | +08    | 08:00:00   | f
 Asia/Singapore   | +08    | 08:00:00   | f
```

## Insert the same literal under different session zones

```sql
CREATE TABLE t (timezone varchar(20), ts timestamp, tstz timestamp with time zone);

-- session UTC
INSERT INTO t VALUES ('UTC', '2021-11-01 08:00:00'::timestamp, '2021-11-01 08:00:00'::timestamp);
INSERT INTO t VALUES ('UTC', '2021-10-01 08:00:00'::timestamp, '2021-10-01 08:00:00'::timestamp);

SET timezone='Australia/Sydney';
INSERT INTO t VALUES ('Sydney', '2021-11-01 08:00:00'::timestamp, '2021-11-01 08:00:00'::timestamp);
INSERT INTO t VALUES ('Sydney', '2021-10-01 08:00:00'::timestamp, '2021-10-01 08:00:00'::timestamp);

SET timezone='Asia/Singapore';
INSERT INTO t VALUES ('Singapore', '2021-11-01 08:00:00'::timestamp, '2021-11-01 08:00:00'::timestamp);
INSERT INTO t VALUES ('Singapore', '2021-10-01 08:00:00'::timestamp, '2021-10-01 08:00:00'::timestamp);
```

The `timestamptz` column captures the moment at insert time *as an absolute UTC
instant* (interpreting the literal in the then-current session zone). The plain
`timestamp` column stores the literal digits verbatim.

## Read it back under three different session zones

Viewed as **UTC** — note the `tstz` values differ per the zone each row was
inserted in, while `ts` is unchanged:

```text
mytest=> SET timezone='UTC'; SELECT * FROM t;
 timezone  |         ts          |          tstz
-----------+---------------------+------------------------
 UTC       | 2021-11-01 08:00:00 | 2021-11-01 08:00:00+00
 UTC       | 2021-10-01 08:00:00 | 2021-10-01 08:00:00+00
 Sydney    | 2021-11-01 08:00:00 | 2021-10-31 21:00:00+00
 Sydney    | 2021-10-01 08:00:00 | 2021-09-30 22:00:00+00
 Singapore | 2021-11-01 08:00:00 | 2021-11-01 00:00:00+00
 Singapore | 2021-10-01 08:00:00 | 2021-10-01 00:00:00+00
```

Viewed as **Australia/Sydney** (note DST: +11 in Nov, +10 in Oct) — `ts` still
unchanged, `tstz` rendered in the session zone:

```text
mytest=> SET timezone='Australia/Sydney'; SELECT * FROM t;
 timezone  |         ts          |          tstz
-----------+---------------------+------------------------
 UTC       | 2021-11-01 08:00:00 | 2021-11-01 19:00:00+11
 UTC       | 2021-10-01 08:00:00 | 2021-10-01 18:00:00+10
 Sydney    | 2021-11-01 08:00:00 | 2021-11-01 08:00:00+11
 Sydney    | 2021-10-01 08:00:00 | 2021-10-01 08:00:00+10
 Singapore | 2021-11-01 08:00:00 | 2021-11-01 11:00:00+11
 Singapore | 2021-10-01 08:00:00 | 2021-10-01 10:00:00+10
```

Viewed as **Asia/Singapore** (+08, no DST):

```text
mytest=> SET timezone='Asia/Singapore'; SELECT * FROM t;
 timezone  |         ts          |          tstz
-----------+---------------------+------------------------
 UTC       | 2021-11-01 08:00:00 | 2021-11-01 16:00:00+08
 UTC       | 2021-10-01 08:00:00 | 2021-10-01 16:00:00+08
 Sydney    | 2021-11-01 08:00:00 | 2021-11-01 05:00:00+08
 Sydney    | 2021-10-01 08:00:00 | 2021-10-01 06:00:00+08
 Singapore | 2021-11-01 08:00:00 | 2021-11-01 08:00:00+08
 Singapore | 2021-10-01 08:00:00 | 2021-10-01 08:00:00+08
```

## Both types are 8 bytes

Storing a time zone does **not** cost extra space — `timestamptz` is an 8-byte
UTC instant, same width as `timestamp`:

```text
mytest=> SELECT timezone, pg_column_size(ts) ts_size, pg_column_size(tstz) tstz_size FROM t;
 timezone  | ts_size | tstz_size
-----------+---------+-----------
 UTC       |       8 |         8
 ...
```

## Takeaways

- `timestamp` stores wall-clock digits with **no** zone — the same text regardless of session zone. Two different absolute instants can share the same `timestamp`.
- `timestamptz` stores an **absolute UTC instant**; the literal is interpreted in the session `TimeZone` at insert, and displayed in the session `TimeZone` at read. Prefer it for anything representing a real point in time.
- Both are 8 bytes — there's no storage penalty for using `timestamptz`.
