

-- Verify that there are no open prepared transactions on your instance:

SELECT count(*) FROM pg_catalog.pg_prepared_xacts;

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

-- List currently installed extensions
select * from pg_extension;

-- View a list of specific extension versions
-- use below SQL to update the extension:
--   alter extension pg-extenstion update to 'new-version'
select * from pg_available_extension_versions;

/*

mytest=> select name,version,schema,comment from pg_available_extension_versions order by name,version;
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
 bloom                        | 1.0        |            | bloom access method - signature file based index
 bool_plperl                  | 1.0        |            | transform between bool and plperl
 btree_gin                    | 1.0        |            | support for indexing common datatypes in GIN
 btree_gin                    | 1.1        |            | support for indexing common datatypes in GIN
 btree_gin                    | 1.2        |            | support for indexing common datatypes in GIN
 btree_gin                    | 1.3        |            | support for indexing common datatypes in GIN
 btree_gist                   | 1.2        |            | support for indexing common datatypes in GiST
 btree_gist                   | 1.3        |            | support for indexing common datatypes in GiST
 btree_gist                   | 1.4        |            | support for indexing common datatypes in GiST
 btree_gist                   | 1.5        |            | support for indexing common datatypes in GiST
 citext                       | 1.4        |            | data type for case-insensitive character strings
 citext                       | 1.5        |            | data type for case-insensitive character strings
 citext                       | 1.6        |            | data type for case-insensitive character strings
 cube                         | 1.2        |            | data type for multidimensional cubes
 cube                         | 1.3        |            | data type for multidimensional cubes
 cube                         | 1.4        |            | data type for multidimensional cubes
 dblink                       | 1.2        |            | connect to other PostgreSQL databases from within a database
 dict_int                     | 1.0        |            | text search dictionary template for integers
 dict_xsyn                    | 1.0        |            | text search dictionary template for extended synonym processing
 earthdistance                | 1.1        |            | calculate great-circle distances on the surface of the Earth
 flow_control                 | 1.0        |            | tools for controlling apply lag during streaming replication
 fuzzystrmatch                | 1.1        |            | determine similarities and distance between strings
 hll                          | 2.10       |            | type for storing hyperloglog data
 hll                          | 2.11       |            | type for storing hyperloglog data
 hll                          | 2.12       |            | type for storing hyperloglog data
 hll                          | 2.13       |            | type for storing hyperloglog data
 hll                          | 2.14       |            | type for storing hyperloglog data
 hll                          | 2.15       |            | type for storing hyperloglog data
 hstore                       | 1.4        |            | data type for storing sets of (key, value) pairs
 hstore                       | 1.5        |            | data type for storing sets of (key, value) pairs
 hstore                       | 1.6        |            | data type for storing sets of (key, value) pairs
 hstore                       | 1.7        |            | data type for storing sets of (key, value) pairs
 hstore_plperl                | 1.0        |            | transform between hstore and plperl
 insert_username              | 1.0        |            | functions for tracking who changed a table
 intagg                       | 1.1        |            | integer aggregator and enumerator (obsolete)
 intarray                     | 1.2        |            | functions, operators, and index support for 1-D arrays of integers
 intarray                     | 1.3        |            | functions, operators, and index support for 1-D arrays of integers
 ip4r                         | 2.4        |            | 
 isn                          | 1.1        |            | data types for international product numbering standards
 isn                          | 1.2        |            | data types for international product numbering standards
 jsonb_plperl                 | 1.0        |            | transform between jsonb and plperl
 log_fdw                      | 1.1        |            | foreign-data wrapper for Postgres log file access
 log_fdw                      | 1.2        |            | foreign-data wrapper for Postgres log file access
 ltree                        | 1.1        |            | data type for hierarchical tree-like structures
 ltree                        | 1.2        |            | data type for hierarchical tree-like structures
 moddatetime                  | 1.0        |            | functions for tracking last modification time
 oracle_fdw                   | 1.2        |            | foreign data wrapper for Oracle access
 orafce                       | 3.15       |            | Functions and operators that emulate a subset of functions and packages from the Oracle RDBMS
 pageinspect                  | 1.5        |            | inspect the contents of database pages at a low level
 pageinspect                  | 1.6        |            | inspect the contents of database pages at a low level
 pageinspect                  | 1.7        |            | inspect the contents of database pages at a low level
 pageinspect                  | 1.8        |            | inspect the contents of database pages at a low level
 pg_bigm                      | 1.2        |            | text similarity measurement and index searching based on bigrams
 pg_buffercache               | 1.2        |            | examine the shared buffer cache
 pg_buffercache               | 1.3        |            | examine the shared buffer cache
 pg_cron                      | 1.0        |            | Job scheduler for PostgreSQL
 pg_cron                      | 1.1        |            | Job scheduler for PostgreSQL
 pg_cron                      | 1.2        |            | Job scheduler for PostgreSQL
 pg_cron                      | 1.3        |            | Job scheduler for PostgreSQL
 pg_freespacemap              | 1.1        |            | examine the free space map (FSM)
 pg_freespacemap              | 1.2        |            | examine the free space map (FSM)
 pg_hint_plan                 | 1.3.7      | hint_plan  | 
 pg_partman                   | 4.5.1      |            | Extension to manage partitioned tables by time or ID
 pg_prewarm                   | 1.1        |            | prewarm relation data
 pg_prewarm                   | 1.2        |            | prewarm relation data
 pg_proctab                   | 0.0.9      |            | Access operating system process table
 pg_repack                    | 1.4.6      |            | Reorganize tables in PostgreSQL databases with minimal locks
 pg_similarity                | 1.0        |            | support similarity queries
 pg_stat_statements           | 1.4        |            | track planning and execution statistics of all SQL statements executed
 pg_stat_statements           | 1.5        |            | track planning and execution statistics of all SQL statements executed
 pg_stat_statements           | 1.6        |            | track planning and execution statistics of all SQL statements executed
 pg_stat_statements           | 1.7        |            | track planning and execution statistics of all SQL statements executed
 pg_stat_statements           | 1.8        |            | track planning and execution statistics of all SQL statements executed
 pg_transport                 | 1.0        |            | physical transport for PostgreSQL databases
 pg_trgm                      | 1.3        |            | text similarity measurement and index searching based on trigrams
 pg_trgm                      | 1.4        |            | text similarity measurement and index searching based on trigrams
 pg_trgm                      | 1.5        |            | text similarity measurement and index searching based on trigrams
 pg_visibility                | 1.1        |            | examine the visibility map (VM) and page-level visibility info
 pg_visibility                | 1.2        |            | examine the visibility map (VM) and page-level visibility info
 pgaudit                      | 1.5        |            | provides auditing functionality
 pgcrypto                     | 1.3        |            | cryptographic functions
 pglogical                    | 1.0.0      | pglogical  | PostgreSQL Logical Replication
 pglogical                    | 1.0.1      | pglogical  | PostgreSQL Logical Replication
 pglogical                    | 1.1.0      | pglogical  | PostgreSQL Logical Replication
 pglogical                    | 1.1.1      | pglogical  | PostgreSQL Logical Replication
 pglogical                    | 1.1.2      | pglogical  | PostgreSQL Logical Replication
 pglogical                    | 1.2.0      | pglogical  | PostgreSQL Logical Replication
 pglogical                    | 1.2.1      | pglogical  | PostgreSQL Logical Replication
 pglogical                    | 1.2.2      | pglogical  | PostgreSQL Logical Replication
 pglogical                    | 2.0.0      | pglogical  | PostgreSQL Logical Replication
 pglogical                    | 2.0.1      | pglogical  | PostgreSQL Logical Replication
 pglogical                    | 2.1.0      | pglogical  | PostgreSQL Logical Replication
 pglogical                    | 2.1.1      | pglogical  | PostgreSQL Logical Replication
 pglogical                    | 2.2.0      | pglogical  | PostgreSQL Logical Replication
 pglogical                    | 2.2.1      | pglogical  | PostgreSQL Logical Replication
 pglogical                    | 2.2.2      | pglogical  | PostgreSQL Logical Replication
 pglogical                    | 2.3.0      | pglogical  | PostgreSQL Logical Replication
 pglogical                    | 2.3.1      | pglogical  | PostgreSQL Logical Replication
 pglogical                    | 2.3.2      | pglogical  | PostgreSQL Logical Replication
 pglogical                    | 2.3.3      | pglogical  | PostgreSQL Logical Replication
 pglogical                    | 2.3.4      | pglogical  | PostgreSQL Logical Replication
 pglogical                    | 2.4.0      | pglogical  | PostgreSQL Logical Replication
 pgrouting                    | 3.0.0      |            | pgRouting Extension
 pgrouting                    | 3.1.3      |            | pgRouting Extension
 pgrowlocks                   | 1.2        |            | show row-level locking information
 pgstattuple                  | 1.4        |            | show tuple-level statistics
 pgstattuple                  | 1.5        |            | show tuple-level statistics
 pgtap                        | 1.1.0      |            | Unit testing for PostgreSQL
 plcoffee                     | 2.3.15     | pg_catalog | PL/CoffeeScript (v8) trusted procedural language
 plls                         | 2.3.15     | pg_catalog | PL/LiveScript (v8) trusted procedural language
 plperl                       | 1.0        | pg_catalog | PL/Perl procedural language
 plpgsql                      | 1.0        | pg_catalog | PL/pgSQL procedural language
 plprofiler                   | 4.1        |            | server-side support for profiling PL/pgSQL functions
 pltcl                        | 1.0        | pg_catalog | PL/Tcl procedural language
 plv8                         | 2.3.15     | pg_catalog | PL/JavaScript (v8) trusted procedural language
 postgis                      | 3.1.4      |            | PostGIS geometry and geography spatial types and functions
 postgis                      | 3.1.4next  |            | PostGIS geometry and geography spatial types and functions
 postgis                      | unpackaged |            | PostGIS geometry and geography spatial types and functions
 postgis_raster               | 3.1.4      |            | PostGIS raster types and functions
 postgis_raster               | 3.1.4next  |            | PostGIS raster types and functions
 postgis_raster               | unpackaged |            | PostGIS raster types and functions
 postgis_tiger_geocoder       | 3.1.4      | tiger      | PostGIS tiger geocoder and reverse geocoder
 postgis_tiger_geocoder       | 3.1.4next  | tiger      | PostGIS tiger geocoder and reverse geocoder
 postgis_topology             | 3.1.4      | topology   | PostGIS topology spatial types and functions
 postgis_topology             | 3.1.4next  | topology   | PostGIS topology spatial types and functions
 postgis_topology             | unpackaged | topology   | PostGIS topology spatial types and functions
 postgres_fdw                 | 1.0        |            | foreign-data wrapper for remote PostgreSQL servers
 prefix                       | 1.2.0      |            | Prefix Range module for PostgreSQL
 rdkit                        | 3.8        |            | Cheminformatics functionality for PostgreSQL.
 rds_tools                    | 1.0        | rds_tools  | miscellaneous administrative functions for RDS PostgreSQL
 refint                       | 1.0        |            | functions for implementing referential integrity (obsolete)
 sslinfo                      | 1.2        |            | information about SSL certificates
 tablefunc                    | 1.0        |            | functions that manipulate whole tables, including crosstab
 test_parser                  | 1.0        |            | example of a custom parser for full-text search
 tsm_system_rows              | 1.0        |            | TABLESAMPLE method which accepts number of rows as a limit
 tsm_system_time              | 1.0        |            | TABLESAMPLE method which accepts time in milliseconds as a limit
 unaccent                     | 1.1        |            | text search dictionary that removes accents
 uuid-ossp                    | 1.1        |            | generate universally unique identifiers (UUIDs)
(149 rows)


mytest=> \dx
                 List of installed extensions
  Name   | Version |   Schema   |         Description          
---------+---------+------------+------------------------------
 plpgsql | 1.0     | pg_catalog | PL/pgSQL procedural language
(1 row)

*/


-- PostgreSQL version 10 stopped supporting the 'unknown' data type
-- drop unknown data types before upgrading

-- The key word ILIKE can be used instead of LIKE to make the match case-insensitive according to the active locale. 
select distinct data_type from information_schema.columns where data_type ilike 'unknown';



