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




create table t_int (col1 int, col2 int, col3 int, col4 int, col5 int);
create index idx_int on t_int(col1);

create table t_bigint (col1 bigint, col2 bigint, col3 bigint, col4 bigint, col5 bigint);
create index idx_bigint on t_bigint(col1);

create table t_char(col1 char(14), col2 char(14), col3 char(14), col4 char(14), col5 char(14));
create index idx_char on t_char(col1);

create table t_timestamp(col1 timestamp, col2 timestamp, col3 timestamp, col4 timestamp, col5 timestamp);
create index idx_timestamp on t_timestamp(col1);




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




explain analyze verbose
select * from t_int
where col1 between extract(epoch from to_timestamp('2010-10-30 23:59:59','YYYY-MM-DD HH24:MI:SS'))::int
and extract(epoch from to_timestamp('2010-11-01 00:00:01','YYYY-MM-DD HH24:MI:SS'))::int;
                                                                                                                                   



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

explain analyze verbose
select * from t_int
where col1 between extract(epoch from to_timestamp('2010-01-31 23:59:59','YYYY-MM-DD HH24:MI:SS'))::int
and extract(epoch from to_timestamp('2010-02-01 00:00:01','YYYY-MM-DD HH24:MI:SS'))::int;
                                                                                                                                   

explain analyze verbose
select * from t_bigint
where col1 between  to_char(to_timestamp('2010-01-31 23:59:59','YYYY-MM-DD HH24:MI:SS'),'YYYYMMDDHH24MISS')::bigint
and to_char(to_timestamp('2010-02-01 00:00:01','YYYY-MM-DD HH24:MI:SS'),'YYYYMMDDHH24MISS')::bigint;
                                                                                                                                   

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


explain analyze verbose
select * from t_char
where col1 between  '2010-01-31 23:59:59'
and '2010-02-01 00:00:01';

         
explain analyze verbose
select * from t_timestamp
where col1 between  to_timestamp('2010-01-31 23:59:59','YYYY-MM-DD HH24:MI:SS')
and to_timestamp('2010-02-01 00:00:01','YYYY-MM-DD HH24:MI:SS');


                 



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
                                                                                                    
Outline Data                                                                                        
-------------                                                                                       
                                                                                                    
  /*+                                                                                               
      BEGIN_OUTLINE_DATA                                                                            
      BATCH_TABLE_ACCESS_BY_ROWID(@"SEL$1" "T_CHAR"@"SEL$1")                                        
      INDEX_RS_ASC(@"SEL$1" "T_CHAR"@"SEL$1" ("T_CHAR"."COL1"))                                     
      OUTLINE_LEAF(@"SEL$1")                                                                        
      ALL_ROWS                                                                                      
      DB_VERSION('19.1.0')                                                                          
      OPTIMIZER_FEATURES_ENABLE('19.1.0')                                                           
      IGNORE_OPTIM_EMBEDDED_HINTS                                                                   
      END_OUTLINE_DATA                                                                              
  */                                                                                                
                                                                                                    
Predicate Information (identified by operation id):                                                 
---------------------------------------------------                                                 
                                                                                                    
   2 - access("COL1">='20101031235959' AND "COL1"<='20101101000001')                                
                                                                                                    
Column Projection Information (identified by operation id):                                         
-----------------------------------------------------------                                         
                                                                                                    
   1 - "COL1"[CHARACTER,14], "T_CHAR"."COL2"[CHARACTER,14],                                         
       "T_CHAR"."COL3"[CHARACTER,14], "T_CHAR"."COL4"[CHARACTER,14],                                

                                                                            PLAN_TABLE_OUTPUT 
_____________________________________________________________________________________________ 
       "T_CHAR"."COL5"[CHARACTER,14]                                                          
   2 - "T_CHAR".ROWID[ROWID,10], "COL1"[CHARACTER,14]                                         
                                                                                              
Query Block Registry:                                                                         
---------------------                                                                         
                                                                                              
  <q o="2" f="y"><n><![CDATA[SEL$1]]></n><f><h><t><![CDATA[T_CHAR]]></t><s><![CDATA[SEL$1]    
        ]></s></h></f></q>                                                                    
                                                                                              

50 rows selected. 

Elapsed: 00:00:00.553
SQL> 

SQL> explain plan for 
  2  select * from t_char
  3* where col1 between  '20101031235959' and '20101101000001';

Explained.

Elapsed: 00:00:00.219
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
                                                                                                    
Outline Data                                                                                        
-------------                                                                                       
                                                                                                    
  /*+                                                                                               
      BEGIN_OUTLINE_DATA                                                                            
      BATCH_TABLE_ACCESS_BY_ROWID(@"SEL$1" "T_CHAR"@"SEL$1")                                        
      INDEX_RS_ASC(@"SEL$1" "T_CHAR"@"SEL$1" ("T_CHAR"."COL1"))                                     
      OUTLINE_LEAF(@"SEL$1")                                                                        
      ALL_ROWS                                                                                      
      DB_VERSION('19.1.0')                                                                          
      OPTIMIZER_FEATURES_ENABLE('19.1.0')                                                           
      IGNORE_OPTIM_EMBEDDED_HINTS                                                                   
      END_OUTLINE_DATA                                                                              
  */                                                                                                
                                                                                                    
Predicate Information (identified by operation id):                                                 
---------------------------------------------------                                                 
                                                                                                    
   2 - access("COL1">='20101031235959' AND "COL1"<='20101101000001')                                
                                                                                                    
Column Projection Information (identified by operation id):                                         
-----------------------------------------------------------                                         
                                                                                                    
   1 - "COL1"[CHARACTER,14], "T_CHAR"."COL2"[CHARACTER,14],                                         
       "T_CHAR"."COL3"[CHARACTER,14], "T_CHAR"."COL4"[CHARACTER,14],                                

                                                                            PLAN_TABLE_OUTPUT 
_____________________________________________________________________________________________ 
       "T_CHAR"."COL5"[CHARACTER,14]                                                          
   2 - "T_CHAR".ROWID[ROWID,10], "COL1"[CHARACTER,14]                                         
                                                                                              
Query Block Registry:                                                                         
---------------------                                                                         
                                                                                              
  <q o="2" f="y"><n><![CDATA[SEL$1]]></n><f><h><t><![CDATA[T_CHAR]]></t><s><![CDATA[SEL$1]    
        ]></s></h></f></q>                                                                    
                                                                                              

50 rows selected. 

Elapsed: 00:00:00.470
SQL> 



explain analyze verbose
select * from t_char
where col1 between  to_char(to_timestamp('2010-10-31 23:59:59','YYYY-MM-DD HH24:MI:SS'),'YYYYMMDDHH24MISS')::bpchar
and to_char(to_timestamp('2010-11-01 00:00:01','YYYY-MM-DD HH24:MI:SS'),'YYYYMMDDHH24MISS')::bpchar;
       
test=# explain 
test-# select * from t_char
test-# where col1 between  to_char(to_timestamp('2010-10-31 23:59:59','YYYY-MM-DD HH24:MI:SS'),'YYYYMMDDHH24MISS')::bpchar
test-# and to_char(to_timestamp('2010-11-01 00:00:01','YYYY-MM-DD HH24:MI:SS'),'YYYYMMDDHH24MISS')::bpchar;
                                                                                                                                     QUERY PLAN                                                                                                                                      
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Index Scan using idx_char on t_char  (cost=0.45..4881.44 rows=100000 width=75)
   Index Cond: ((col1 >= (to_char(to_timestamp('2010-10-31 23:59:59'::text, 'YYYY-MM-DD HH24:MI:SS'::text), 'YYYYMMDDHH24MISS'::text))::bpchar) AND (col1 <= (to_char(to_timestamp('2010-11-01 00:00:01'::text, 'YYYY-MM-DD HH24:MI:SS'::text), 'YYYYMMDDHH24MISS'::text))::bpchar))
(2 rows)

explain 
select * from t_char
where col2 between  to_char(to_timestamp('2010-10-31 23:59:59','YYYY-MM-DD HH24:MI:SS'),'YYYYMMDDHH24MISS')::char(14)
and to_char(to_timestamp('2010-11-01 00:00:01','YYYY-MM-DD HH24:MI:SS'),'YYYYMMDDHH24MISS')::char(14);

         
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


