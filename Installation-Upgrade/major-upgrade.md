# PostgreSQL Major Version Upgrade

A set of pre-upgrade checks to run before performing a PostgreSQL major
version upgrade (for example on Amazon RDS for PostgreSQL). A major upgrade
uses `pg_upgrade` under the hood, which refuses to proceed when certain
objects or data types are present. Running these queries first surfaces the
blockers early so you can remediate them before kicking off the upgrade.

The checks below cover prepared transactions, unsupported `reg*` data types,
extension inventory/versions, and the deprecated `unknown` data type.

## Check for open prepared transactions

`pg_upgrade` will not run while there are prepared (two-phase commit)
transactions still open. Commit or roll them back first, then confirm the
count is zero:

```sql
-- Verify that there are no open prepared transactions on your instance:

SELECT count(*) FROM pg_catalog.pg_prepared_xacts;
```

## Check for unsupported `reg*` data types

With the exception of `regtype` and `regclass`, the `reg*` data types cannot be
upgraded, because they store OIDs that are not stable across the upgrade. This
query counts columns using any of the unsupported `reg*` types in user
schemas:

```sql
-- Verify that no uses of unsupported reg* data types
-- With the exception of regtype and regclass, reg* data types cannot be upgraded

select count(*)
  from pg_catalog.pg_class c, pg_catalog.pg_namespace n, pg_catalog.pg_attribute a
 where c.oid = a.attrelid
   and not a.attisdropped
   and a.atttypid in ('pg_catalog.regproc'::pg_catalog.regtype,
                      'pg_catalog.regprocedure'::pg_catalog.regtype,
                      'pg_catalog.regoper'::pg_catalog.regtype,
                      'pg_catalog.regoperator'::pg_catalog.regtype,
                      'pg_catalog.regconfig'::pg_catalog.regtype,
                      'pg_catalog.regdictionary'::pg_catalog.regtype)
    and c.relnamespace = n.oid
    and n.nspname not in ('pg_catalog','information_schema');
```

A non-zero result means you must change those columns to a supported type
before upgrading.

## Inventory installed extensions

List what is currently installed so you know which extensions need to be
compatible with (and possibly updated for) the target version:

```sql
-- List currently installed extensions
select * from pg_extension;
```

## Review available extension versions

Check the versions available on the server. If an installed extension is
behind, you can update it with `ALTER EXTENSION ... UPDATE TO 'new-version'`
before (or after) the upgrade:

```sql
-- View a list of specific extension versions
-- use below SQL to update the extension:
--   alter extension pg-extenstion update to 'new-version'
select * from pg_available_extension_versions;
```

A tidier form, ordered by name and version:

```sql
select name,version,schema,comment from pg_available_extension_versions order by name,version;
```

The captured output on this instance listed 149 available extension versions
(abbreviated here — see the leading and trailing rows):

```text
             name             |  version   |   schema   |                                                       comment
------------------------------+------------+------------+---------------------------------------------------------------------------------------------------------------------
 address_standardizer         | 3.1.4      |            | Used to parse an address into constituent elements. Generally used to support geocoding address normalization step.
 address_standardizer         | 3.1.4next  |            | Used to parse an address into constituent elements. Generally used to support geocoding address normalization step.
 address_standardizer_data_us | 3.1.4      |            | Address Standardizer US dataset example
 address_standardizer_data_us | 3.1.4next  |            | Address Standardizer US dataset example
 amcheck                      | 1.0        |            | functions for verifying relation integrity
 amcheck                      | 1.1        |            | functions for verifying relation integrity
 amcheck                      | 1.2        |            | functions for verifying relation integrity
 autoinc                      | 1.0        |            | functions for autoincrementing fields
 aws_commons                  | 1.2        |            | Common data types across AWS services
 aws_lambda                   | 1.0        |            | AWS Lambda integration
 aws_s3                       | 1.1        |            | AWS S3 extension for importing data from S3
 ...
 postgis                      | 3.1.4      |            | PostGIS geometry and geography spatial types and functions
 postgis                      | 3.1.4next  |            | PostGIS geometry and geography spatial types and functions
 postgis                      | unpackaged |            | PostGIS geometry and geography spatial types and functions
 ...
 pg_hint_plan                 | 1.3.7      | hint_plan  |
 pg_partman                   | 4.5.1      |            | Extension to manage partitioned tables by time or ID
 ...
 tsm_system_rows              | 1.0        |            | TABLESAMPLE method which accepts number of rows as a limit
 tsm_system_time              | 1.0        |            | TABLESAMPLE method which accepts time in milliseconds as a limit
 unaccent                     | 1.1        |            | text search dictionary that removes accents
 uuid-ossp                    | 1.1        |            | generate universally unique identifiers (UUIDs)
(149 rows)
```

Compare that catalog of *available* versions against what is actually
installed with `\dx`:

```text
mytest=> \dx
                 List of installed extensions
  Name   | Version |   Schema   |         Description
---------+---------+------------+------------------------------
 plpgsql | 1.0     | pg_catalog | PL/pgSQL procedural language
(1 row)
```

Here only `plpgsql` is installed, so there is nothing to update in this case.

## Check for the deprecated `unknown` data type

PostgreSQL 10 stopped supporting the `unknown` data type as a column type.
Any columns using it must be dropped or altered before upgrading past 9.6:

```sql
-- PostgreSQL version 10 stopped supporting the 'unknown' data type
-- drop unknown data types before upgrading

-- The key word ILIKE can be used instead of LIKE to make the match case-insensitive according to the active locale.
select distinct data_type from information_schema.columns where data_type ilike 'unknown';
```

`ILIKE` is used instead of `LIKE` so the match is case-insensitive according
to the active locale.

## Takeaways

- `pg_upgrade` blocks on open **prepared transactions** — resolve them and
  confirm `pg_prepared_xacts` is empty before upgrading.
- Most `reg*` data types (all except `regtype` and `regclass`) cannot be
  carried across an upgrade because they encode OIDs; find and convert any
  such columns first.
- Take an inventory of installed extensions (`pg_extension` / `\dx`) and
  compare against `pg_available_extension_versions`; update lagging extensions
  with `ALTER EXTENSION ... UPDATE TO 'new-version'`.
- PostgreSQL 10 removed the `unknown` column data type — scan
  `information_schema.columns` and remediate before upgrading past 9.6.
