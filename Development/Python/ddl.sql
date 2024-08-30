create table t_txn (
    id bigint primary key,
    c1 text,
    c2 text,
    update_ts timestamp)
;
create index idx_t_txn_update_ts on t_txn(update_ts);

create table t_txn_new (
    id bigint primary key,
    c1 text,
    c2 text,
    update_ts timestamp)
;
create index idx_t_txn_new_update_ts on t_txn_new(update_ts);

create table t_txn_new2 (
    id bigint primary key,
    c1 text,
    c2 text,
    update_ts timestamp)
;
create index idx_t_txn_new2_update_ts on t_txn_new2(update_ts);

insert into t_txn_new2 select * from t_txn;


insert into t_txn
select i, rpad(i::text,1000,'x'),rpad(i::text,1000,'y'), to_timestamp('2024-01-01 00:00','YYYY-MM-DD HH24:MI')+(interval '0.01 sec')*i 
   from generate_series(1,1000000000) i;
   

insert into t_txn
select i, rpad(i::text,1000,'x'),rpad(i::text,1000,'y'), to_timestamp('2024-01-01 00:00','YYYY-MM-DD HH24:MI')+(interval '0.01 sec')*i 
   from generate_series(1,1000000) i;
   


test=> select min(update_ts),max(update_ts) from t_txn;
          min           |         max         
------------------------+---------------------
 2024-01-01 00:00:00.01 | 2024-04-25 17:46:40
(1 row)

mytest=> explain
mytest-> INSERT INTO t_txn_new (id, c1, c2, update_ts)
mytest->                                   select id, c1, c2, update_ts
mytest->                                   from t_txn where update_ts >= '2024-01-01T02:46:00'::timestamp and update_ts < '2024-01-01T02:47:00'::timestamp

select count(*) from t_txn where update_ts >= '2024-01-01T00:00:00'::timestamp and update_ts < '2024-01-02T00:00:00'::timestamp

test=> select count(*) from t_txn where update_ts >= '2024-01-01T00:00:00'::timestamp and update_ts < '2024-01-02T00:00:00'::timestamp;
  count  
---------
 8639999
(1 row)

SELECT n.nspname as "Schema",
  c.relname as "Name",
  CASE c.relkind WHEN 'r' THEN 'table' WHEN 'v' THEN 'view' WHEN 'm' THEN 'materialized view' WHEN 'i' THEN 'index' WHEN 'S' THEN 'sequence' WHEN 't' THEN 'TOAST table' WHEN 'f' THEN 'foreign table' WHEN 'p' THEN 'partitioned table' WHEN 'I' THEN 'partitioned index' END as "Type",
  pg_catalog.pg_get_userbyid(c.relowner) as "Owner",
  CASE c.relpersistence WHEN 'p' THEN 'permanent' WHEN 't' THEN 'temporary' WHEN 'u' THEN 'unlogged' END as "Persistence",
  am.amname as "Access method",
  pg_catalog.pg_size_pretty(pg_catalog.pg_table_size(c.oid)) as "Size",
  pg_catalog.obj_description(c.oid, 'pg_class') as "Description"
FROM pg_catalog.pg_class c
     LEFT JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
     LEFT JOIN pg_catalog.pg_am am ON am.oid = c.relam
WHERE c.relkind IN ('r','p','')
      AND n.nspname <> 'pg_catalog'
      AND n.nspname !~ '^pg_toast'
      AND n.nspname <> 'information_schema'
  AND pg_catalog.pg_table_is_visible(c.oid)
ORDER BY 1,2;
