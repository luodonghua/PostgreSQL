-- Display query for internal commands used 
-- "psql --echo-hidden" / "psql -E"

/*
psql --echo-hidden postgresql://postgres@postgres-instance1.cfvver3ervfg.us-east-1.rds.amazonaws.com/mytest
psql (13.4)
SSL connection (protocol: TLSv1.2, cipher: ECDHE-RSA-AES256-GCM-SHA384, bits: 256, compression: off)
Type "help" for help.

mytest=> \dt
********* QUERY **********
SELECT n.nspname as "Schema",
  c.relname as "Name",
  CASE c.relkind WHEN 'r' THEN 'table' WHEN 'v' THEN 'view' WHEN 'm' THEN 'materialized view' WHEN 'i' THEN 'index' WHEN 'S' THEN 'sequence' WHEN 's' THEN 'special' WHEN 'f' THEN 'foreign table' WHEN 'p' THEN 'partitioned table' WHEN 'I' THEN 'partitioned index' END as "Type",
  pg_catalog.pg_get_userbyid(c.relowner) as "Owner"
FROM pg_catalog.pg_class c
     LEFT JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r','p','')
      AND n.nspname <> 'pg_catalog'
      AND n.nspname <> 'information_schema'
      AND n.nspname !~ '^pg_toast'
  AND pg_catalog.pg_table_is_visible(c.oid)
ORDER BY 1,2;
**************************

              List of relations
 Schema |       Name       | Type  |  Owner   
--------+------------------+-------+----------
 public | pgbench_accounts | table | postgres
 public | pgbench_branches | table | postgres
 public | pgbench_history  | table | postgres
 public | pgbench_tellers  | table | postgres
(4 rows)


mytest=> SELECT n.nspname as "Schema",
mytest->   c.relname as "Name",
mytest->   CASE c.relkind WHEN 'r' THEN 'table' WHEN 'v' THEN 'view' WHEN 'm' THEN 'materialized view' WHEN 'i' THEN 'index' WHEN 'S' THEN 'sequence' WHEN 's' THEN 'special' WHEN 'f' THEN 'foreign table' WHEN 'p' THEN 'partitioned table' WHEN 'I' THEN 'partitioned index' END as "Type",
mytest->   pg_catalog.pg_get_userbyid(c.relowner) as "Owner"
mytest-> FROM pg_catalog.pg_class c
mytest->      LEFT JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
mytest-> WHERE c.relkind IN ('r','p','')
mytest->       AND n.nspname <> 'pg_catalog'
mytest->       AND n.nspname <> 'information_schema'
mytest->       AND n.nspname !~ '^pg_toast'
mytest->   AND pg_catalog.pg_table_is_visible(c.oid)
mytest-> ORDER BY 1,2;
 Schema |       Name       | Type  |  Owner   
--------+------------------+-------+----------
 public | pgbench_accounts | table | postgres
 public | pgbench_branches | table | postgres
 public | pgbench_history  | table | postgres
 public | pgbench_tellers  | table | postgres

*/

/*

mytest=> \dt pg_catalog.*
                    List of relations
   Schema   |          Name           | Type  |  Owner   
------------+-------------------------+-------+----------
 pg_catalog | pg_aggregate            | table | rdsadmin
 pg_catalog | pg_am                   | table | rdsadmin
 pg_catalog | pg_amop                 | table | rdsadmin
 pg_catalog | pg_amproc               | table | rdsadmin
 pg_catalog | pg_attrdef              | table | rdsadmin
 pg_catalog | pg_attribute            | table | rdsadmin
 pg_catalog | pg_auth_members         | table | rdsadmin
 pg_catalog | pg_authid               | table | rdsadmin
 pg_catalog | pg_cast                 | table | rdsadmin
 pg_catalog | pg_class                | table | rdsadmin
 pg_catalog | pg_collation            | table | rdsadmin
 pg_catalog | pg_constraint           | table | rdsadmin
 pg_catalog | pg_conversion           | table | rdsadmin
 pg_catalog | pg_database             | table | rdsadmin
 pg_catalog | pg_db_role_setting      | table | rdsadmin
 pg_catalog | pg_default_acl          | table | rdsadmin
 pg_catalog | pg_depend               | table | rdsadmin
 pg_catalog | pg_description          | table | rdsadmin
 pg_catalog | pg_enum                 | table | rdsadmin
 pg_catalog | pg_event_trigger        | table | rdsadmin
 pg_catalog | pg_extension            | table | rdsadmin
 pg_catalog | pg_foreign_data_wrapper | table | rdsadmin
 pg_catalog | pg_foreign_server       | table | rdsadmin
 pg_catalog | pg_foreign_table        | table | rdsadmin
 pg_catalog | pg_index                | table | rdsadmin
 pg_catalog | pg_inherits             | table | rdsadmin
 pg_catalog | pg_init_privs           | table | rdsadmin
 pg_catalog | pg_language             | table | rdsadmin
 pg_catalog | pg_largeobject          | table | rdsadmin
 pg_catalog | pg_largeobject_metadata | table | rdsadmin
 pg_catalog | pg_namespace            | table | rdsadmin
 pg_catalog | pg_opclass              | table | rdsadmin
 pg_catalog | pg_operator             | table | rdsadmin
 pg_catalog | pg_opfamily             | table | rdsadmin
 pg_catalog | pg_partitioned_table    | table | rdsadmin
 pg_catalog | pg_policy               | table | rdsadmin
 pg_catalog | pg_proc                 | table | rdsadmin
 pg_catalog | pg_publication          | table | rdsadmin
 pg_catalog | pg_publication_rel      | table | rdsadmin
 pg_catalog | pg_range                | table | rdsadmin
 pg_catalog | pg_replication_origin   | table | rdsadmin
 pg_catalog | pg_rewrite              | table | rdsadmin
 pg_catalog | pg_seclabel             | table | rdsadmin
 pg_catalog | pg_sequence             | table | rdsadmin
 pg_catalog | pg_shdepend             | table | rdsadmin
 pg_catalog | pg_shdescription        | table | rdsadmin
 pg_catalog | pg_shseclabel           | table | rdsadmin
 pg_catalog | pg_statistic            | table | rdsadmin
 pg_catalog | pg_statistic_ext        | table | rdsadmin
 pg_catalog | pg_statistic_ext_data   | table | rdsadmin
 pg_catalog | pg_subscription         | table | rdsadmin
 pg_catalog | pg_subscription_rel     | table | rdsadmin
 pg_catalog | pg_tablespace           | table | rdsadmin
 pg_catalog | pg_transform            | table | rdsadmin
 pg_catalog | pg_trigger              | table | rdsadmin
 pg_catalog | pg_ts_config            | table | rdsadmin
 pg_catalog | pg_ts_config_map        | table | rdsadmin
 pg_catalog | pg_ts_dict              | table | rdsadmin
 pg_catalog | pg_ts_parser            | table | rdsadmin
 pg_catalog | pg_ts_template          | table | rdsadmin
 pg_catalog | pg_type                 | table | rdsadmin
 pg_catalog | pg_user_mapping         | table | rdsadmin
(62 rows)

mytest=> \dv pg_catalog.*
                       List of relations
   Schema   |              Name               | Type |  Owner   
------------+---------------------------------+------+----------
 pg_catalog | pg_available_extension_versions | view | rdsadmin
 pg_catalog | pg_available_extensions         | view | rdsadmin
 pg_catalog | pg_config                       | view | rdsadmin
 pg_catalog | pg_cursors                      | view | rdsadmin
 pg_catalog | pg_file_settings                | view | rdsadmin
 pg_catalog | pg_group                        | view | rdsadmin
 pg_catalog | pg_hba_file_rules               | view | rdsadmin
 pg_catalog | pg_indexes                      | view | rdsadmin
 pg_catalog | pg_locks                        | view | rdsadmin
 pg_catalog | pg_matviews                     | view | rdsadmin
 pg_catalog | pg_policies                     | view | rdsadmin
 pg_catalog | pg_prepared_statements          | view | rdsadmin
 pg_catalog | pg_prepared_xacts               | view | rdsadmin
 pg_catalog | pg_publication_tables           | view | rdsadmin
 pg_catalog | pg_replication_origin_status    | view | rdsadmin
 pg_catalog | pg_replication_slots            | view | rdsadmin
 pg_catalog | pg_roles                        | view | rdsadmin
 pg_catalog | pg_rules                        | view | rdsadmin
 pg_catalog | pg_seclabels                    | view | rdsadmin
 pg_catalog | pg_sequences                    | view | rdsadmin
 pg_catalog | pg_settings                     | view | rdsadmin
 pg_catalog | pg_shadow                       | view | rdsadmin
 pg_catalog | pg_shmem_allocations            | view | rdsadmin
 pg_catalog | pg_stat_activity                | view | rdsadmin
 pg_catalog | pg_stat_all_indexes             | view | rdsadmin
 pg_catalog | pg_stat_all_tables              | view | rdsadmin
 pg_catalog | pg_stat_archiver                | view | rdsadmin
 pg_catalog | pg_stat_bgwriter                | view | rdsadmin
 pg_catalog | pg_stat_database                | view | rdsadmin
 pg_catalog | pg_stat_database_conflicts      | view | rdsadmin
 pg_catalog | pg_stat_gssapi                  | view | rdsadmin
 pg_catalog | pg_stat_progress_analyze        | view | rdsadmin
 pg_catalog | pg_stat_progress_basebackup     | view | rdsadmin
 pg_catalog | pg_stat_progress_cluster        | view | rdsadmin
 pg_catalog | pg_stat_progress_create_index   | view | rdsadmin
 pg_catalog | pg_stat_progress_vacuum         | view | rdsadmin
 pg_catalog | pg_stat_replication             | view | rdsadmin
 pg_catalog | pg_stat_slru                    | view | rdsadmin
 pg_catalog | pg_stat_ssl                     | view | rdsadmin
 pg_catalog | pg_stat_subscription            | view | rdsadmin
 pg_catalog | pg_stat_sys_indexes             | view | rdsadmin
 pg_catalog | pg_stat_sys_tables              | view | rdsadmin
 pg_catalog | pg_stat_user_functions          | view | rdsadmin
 pg_catalog | pg_stat_user_indexes            | view | rdsadmin
 pg_catalog | pg_stat_user_tables             | view | rdsadmin
 pg_catalog | pg_stat_wal_receiver            | view | rdsadmin
 pg_catalog | pg_stat_xact_all_tables         | view | rdsadmin
 pg_catalog | pg_stat_xact_sys_tables         | view | rdsadmin
 pg_catalog | pg_stat_xact_user_functions     | view | rdsadmin
 pg_catalog | pg_stat_xact_user_tables        | view | rdsadmin
 pg_catalog | pg_statio_all_indexes           | view | rdsadmin
 pg_catalog | pg_statio_all_sequences         | view | rdsadmin
 pg_catalog | pg_statio_all_tables            | view | rdsadmin
 pg_catalog | pg_statio_sys_indexes           | view | rdsadmin
 pg_catalog | pg_statio_sys_sequences         | view | rdsadmin
 pg_catalog | pg_statio_sys_tables            | view | rdsadmin
 pg_catalog | pg_statio_user_indexes          | view | rdsadmin
 pg_catalog | pg_statio_user_sequences        | view | rdsadmin
 pg_catalog | pg_statio_user_tables           | view | rdsadmin
 pg_catalog | pg_stats                        | view | rdsadmin
 pg_catalog | pg_stats_ext                    | view | rdsadmin
 pg_catalog | pg_tables                       | view | rdsadmin
 pg_catalog | pg_timezone_abbrevs             | view | rdsadmin
 pg_catalog | pg_timezone_names               | view | rdsadmin
 pg_catalog | pg_user                         | view | rdsadmin
 pg_catalog | pg_user_mappings                | view | rdsadmin
 pg_catalog | pg_views                        | view | rdsadmin
(67 rows)


mytest=> \dt information_schema.*

                        List of relations
       Schema       |          Name           | Type  |  Owner   
--------------------+-------------------------+-------+----------
 information_schema | sql_features            | table | rdsadmin
 information_schema | sql_implementation_info | table | rdsadmin
 information_schema | sql_parts               | table | rdsadmin
 information_schema | sql_sizing              | table | rdsadmin
(4 rows)

mytest=> \dv information_schema.*
                              List of relations
       Schema       |                 Name                  | Type |  Owner   
--------------------+---------------------------------------+------+----------
 information_schema | _pg_foreign_data_wrappers             | view | rdsadmin
 information_schema | _pg_foreign_servers                   | view | rdsadmin
 information_schema | _pg_foreign_table_columns             | view | rdsadmin
 information_schema | _pg_foreign_tables                    | view | rdsadmin
 information_schema | _pg_user_mappings                     | view | rdsadmin
 information_schema | administrable_role_authorizations     | view | rdsadmin
 information_schema | applicable_roles                      | view | rdsadmin
 information_schema | attributes                            | view | rdsadmin
 information_schema | character_sets                        | view | rdsadmin
 information_schema | check_constraint_routine_usage        | view | rdsadmin
 information_schema | check_constraints                     | view | rdsadmin
 information_schema | collation_character_set_applicability | view | rdsadmin
 information_schema | collations                            | view | rdsadmin
 information_schema | column_column_usage                   | view | rdsadmin
 information_schema | column_domain_usage                   | view | rdsadmin
 information_schema | column_options                        | view | rdsadmin
 information_schema | column_privileges                     | view | rdsadmin
 information_schema | column_udt_usage                      | view | rdsadmin
 information_schema | columns                               | view | rdsadmin
 information_schema | constraint_column_usage               | view | rdsadmin
 information_schema | constraint_table_usage                | view | rdsadmin
 information_schema | data_type_privileges                  | view | rdsadmin
 information_schema | domain_constraints                    | view | rdsadmin
 information_schema | domain_udt_usage                      | view | rdsadmin
 information_schema | domains                               | view | rdsadmin
 information_schema | element_types                         | view | rdsadmin
 information_schema | enabled_roles                         | view | rdsadmin
 information_schema | foreign_data_wrapper_options          | view | rdsadmin
 information_schema | foreign_data_wrappers                 | view | rdsadmin
 information_schema | foreign_server_options                | view | rdsadmin
 information_schema | foreign_servers                       | view | rdsadmin
 information_schema | foreign_table_options                 | view | rdsadmin
 information_schema | foreign_tables                        | view | rdsadmin
 information_schema | information_schema_catalog_name       | view | rdsadmin
 information_schema | key_column_usage                      | view | rdsadmin
 information_schema | parameters                            | view | rdsadmin
 information_schema | referential_constraints               | view | rdsadmin
 information_schema | role_column_grants                    | view | rdsadmin
 information_schema | role_routine_grants                   | view | rdsadmin
 information_schema | role_table_grants                     | view | rdsadmin
 information_schema | role_udt_grants                       | view | rdsadmin
 information_schema | role_usage_grants                     | view | rdsadmin
 information_schema | routine_privileges                    | view | rdsadmin
 information_schema | routines                              | view | rdsadmin
 information_schema | schemata                              | view | rdsadmin
 information_schema | sequences                             | view | rdsadmin
 information_schema | table_constraints                     | view | rdsadmin
 information_schema | table_privileges                      | view | rdsadmin
 information_schema | tables                                | view | rdsadmin
 information_schema | transforms                            | view | rdsadmin
 information_schema | triggered_update_columns              | view | rdsadmin
 information_schema | triggers                              | view | rdsadmin
 information_schema | udt_privileges                        | view | rdsadmin
 information_schema | usage_privileges                      | view | rdsadmin
 information_schema | user_defined_types                    | view | rdsadmin
 information_schema | user_mapping_options                  | view | rdsadmin
 information_schema | user_mappings                         | view | rdsadmin
 information_schema | view_column_usage                     | view | rdsadmin
 information_schema | view_routine_usage                    | view | rdsadmin
 information_schema | view_table_usage                      | view | rdsadmin
 information_schema | views                                 | view | rdsadmin
(61 rows)


*/

select datname, datcollate, datconnlimit, datacl from pg_database;

/*

mytest=> select datname, datcollate, datconnlimit, datacl from pg_database;
  datname  | datcollate  | datconnlimit |                    datacl                     
-----------+-------------+--------------+-----------------------------------------------
 template0 | en_US.UTF-8 |           -1 | {=c/rdsadmin,rdsadmin=CTc/rdsadmin}
 template1 | en_US.UTF-8 |           -1 | {=c/postgres,postgres=CTc/postgres}
 postgres  | en_US.UTF-8 |           -1 | 
 mytest    | en_US.UTF-8 |           -1 | 
 rdsadmin  | en_US.UTF-8 |           -1 | {rdsadmin=CTc/rdsadmin,rdstopmgr=Tc/rdsadmin}
(5 rows)

*/

-- Object identifiers (OIDs) are the names for any type of object or element in a database. 
-- They are used internally by PostgreSQL as primary keys for system tables. 
-- An OID is an unsigned 4-byte integer that uniquely identifies each row (or record) in a table. 

/*
mytest=> \d pg_namespace
            Table "pg_catalog.pg_namespace"
  Column  |   Type    | Collation | Nullable | Default 
----------+-----------+-----------+----------+---------
 oid      | oid       |           | not null | 
 nspname  | name      |           | not null | 
 nspowner | oid       |           | not null | 
 nspacl   | aclitem[] |           |          | 
Indexes:
    "pg_namespace_nspname_index" UNIQUE, btree (nspname)
    "pg_namespace_oid_index" UNIQUE, btree (oid)
*/

select attrelid,attname,atttypid,attlen,attnum from pg_attribute
where attrelid = 'pgbench_accounts'::regclass;

select attrelid,attname,atttypid,attlen,attnum from pg_attribute
where attrelid = (select oid from pg_class where relname='pgbench_accounts');

/*

mytest=> \d pgbench_accounts
              Table "public.pgbench_accounts"
  Column  |     Type      | Collation | Nullable | Default 
----------+---------------+-----------+----------+---------
 aid      | integer       |           | not null | 
 bid      | integer       |           |          | 
 abalance | integer       |           |          | 
 filler   | character(84) |           |          | 
Indexes:
    "pgbench_accounts_pkey" PRIMARY KEY, btree (aid)

mytest=> select attrelid,attname,atttypid,attlen,attnum from pg_attribute
mytest-> where attrelid = 'pgbench_accounts'::regclass;
 attrelid | attname  | atttypid | attlen | attnum 
----------+----------+----------+--------+--------
    16423 | tableoid |       26 |      4 |     -6
    16423 | cmax     |       29 |      4 |     -5
    16423 | xmax     |       28 |      4 |     -4
    16423 | cmin     |       29 |      4 |     -3
    16423 | xmin     |       28 |      4 |     -2
    16423 | ctid     |       27 |      6 |     -1
    16423 | aid      |       23 |      4 |      1
    16423 | bid      |       23 |      4 |      2
    16423 | abalance |       23 |      4 |      3
    16423 | filler   |     1042 |     -1 |      4
(10 rows)

mytest=> select attrelid,attname,atttypid,attlen,attnum from pg_attribute
mytest-> where attrelid = (select oid from pg_class where relname='pgbench_accounts');

 attrelid | attname  | atttypid | attlen | attnum 
----------+----------+----------+--------+--------
    16423 | tableoid |       26 |      4 |     -6
    16423 | cmax     |       29 |      4 |     -5
    16423 | xmax     |       28 |      4 |     -4
    16423 | cmin     |       29 |      4 |     -3
    16423 | xmin     |       28 |      4 |     -2
    16423 | ctid     |       27 |      6 |     -1
    16423 | aid      |       23 |      4 |      1
    16423 | bid      |       23 |      4 |      2
    16423 | abalance |       23 |      4 |      3
    16423 | filler   |     1042 |     -1 |      4
(10 rows)

*/

select * from pg_am;

/*

mytest=> select * from pg_am;
 oid  | amname |      amhandler       | amtype 
------+--------+----------------------+--------
    2 | heap   | heap_tableam_handler | t
  403 | btree  | bthandler            | i
  405 | hash   | hashhandler          | i
  783 | gist   | gisthandler          | i
 2742 | gin    | ginhandler           | i
 4000 | spgist | spghandler           | i
 3580 | brin   | brinhandler          | i
(7 rows)

*/


select relname,relkind,relnatts,relhasindex
from pg_class where relnamespace = 2200;

/*

mytest=> select * from pg_namespace;
  oid  |      nspname       | nspowner |               nspacl                
-------+--------------------+----------+-------------------------------------
    99 | pg_toast           |       10 | 
    11 | pg_catalog         |       10 | {rdsadmin=UC/rdsadmin,=U/rdsadmin}
 14017 | information_schema |       10 | {rdsadmin=UC/rdsadmin,=U/rdsadmin}
  2200 | public             |    16400 | {postgres=UC/postgres,=UC/postgres}
(4 rows)

mytest=> select relname,relkind,relnatts,relhasindex
from pg_class where relnamespace = 2200;
        relname        | relkind | relnatts | relhasindex 
-----------------------+---------+----------+-------------
 pgbench_accounts      | r       |        4 | t
 pgbench_branches      | r       |        3 | t
 pgbench_tellers       | r       |        4 | t
 pgbench_branches_pkey | i       |        1 | f
 pgbench_tellers_pkey  | i       |        1 | f
 pgbench_accounts_pkey | i       |        1 | f
 pgbench_history       | r       |        6 | f
 pg_stat_statements    | v       |       32 | f
(8 rows)

*/

select relname,relpages,reltuples::bigint from pg_class where relnamespace=2200 and relkind='r';

/*

mytest=> select relname,relpages,reltuples::bigint from pg_class where relnamespace=2200 and relkind='r';
     relname      | relpages | reltuples 
------------------+----------+-----------
 pgbench_accounts |    16394 |   1000000
 pgbench_branches |        1 |        10
 pgbench_tellers  |        1 |       100
 pgbench_history  |        0 |         0
(4 rows)

*/

select datname, pg_database_size(oid) from pg_database;

select datname, pg_size_pretty(pg_database_size(oid)) from pg_database;

/*

mytest=> select datname, pg_database_size(oid) from pg_database;
  datname  | pg_database_size 
-----------+------------------
 template0 |          8225283
 template1 |          8385071
 postgres  |          8376879
 mytest    |        165433903
 rdsadmin  |          8426031
(5 rows)

mytest=> select datname, pg_size_pretty(pg_database_size(oid)) from pg_database;
  datname  | pg_size_pretty 
-----------+----------------
 template0 | 8033 kB
 template1 | 8189 kB
 postgres  | 8181 kB
 mytest    | 158 MB
 rdsadmin  | 8229 kB
(5 rows)

*/


/*

  By default, table_size shows disk space used by the tables and excludes indexes.

    pg_relation_size shows just the relation.
    pg_table_size shows the relation, TOAST, free-space map (FSM), and visibility map (VM).
    pg_total_relation_size shows relation, TOAST, FSM, VM, and indexes.

    TOAST: The Oversized-Attribute Storage Technique
*/

select pg_relation_size(oid),pg_table_size(oid),pg_total_relation_size(oid)
from pg_class where relname='pgbench_accounts';
  
/*

mytest=> select pg_relation_size(oid),pg_table_size(oid),pg_total_relation_size(oid)
mytest-> from pg_class where relname='pgbench_accounts';
 pg_relation_size | pg_table_size | pg_total_relation_size 
------------------+---------------+------------------------
        134316032 |     134381568 |              156868608
(1 row)
*/

select tablename, pg_size_pretty(pg_relation_size(tablename::regclass)) as pg_relation_size,
    pg_size_pretty(pg_table_size(tablename::regclass)) as pg_table_size,
    pg_size_pretty(pg_total_relation_size(tablename::regclass)) as pg_total_relation_size
from pg_tables where schemaname='public';

/*

mytest=> select tablename, pg_size_pretty(pg_relation_size(tablename::regclass)) as pg_relation_size,
mytest->     pg_size_pretty(pg_table_size(tablename::regclass)) as pg_table_size,
mytest->     pg_size_pretty(pg_total_relation_size(tablename::regclass)) as pg_total_relation_size
mytest-> from pg_tables where schemaname='public';
    tablename     | pg_relation_size | pg_table_size | pg_total_relation_size 
------------------+------------------+---------------+------------------------
 pgbench_accounts | 128 MB           | 128 MB        | 150 MB
 pgbench_branches | 8192 bytes       | 40 kB         | 56 kB
 pgbench_tellers  | 8192 bytes       | 40 kB         | 56 kB
 pgbench_history  | 8192 bytes       | 8192 bytes    | 8192 bytes
 t                | 8192 bytes       | 8192 bytes    | 8192 bytes
(5 rows)

*/

select * from pg_stat_database where datname='mytest';

/*

mytest=> select * from pg_stat_database where datname='mytest';
-[ RECORD 1 ]---------+------------------------------
datid                 | 16402
datname               | mytest
numbackends           | 3
xact_commit           | 1832
xact_rollback         | 46
blks_read             | 60072
blks_hit              | 124779
tup_returned          | 2025179
tup_fetched           | 25748
tup_inserted          | 1000357
tup_updated           | 145
tup_deleted           | 42
conflicts             | 0
temp_files            | 4
temp_bytes            | 20062208
deadlocks             | 0
checksum_failures     | 0
checksum_last_failure | 
blk_read_time         | 350.13
blk_write_time        | 162.669
stats_reset           | 2021-10-30 13:45:01.739887+00

*/
    



