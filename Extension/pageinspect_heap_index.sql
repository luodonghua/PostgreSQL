-- Reference: https://www.postgresql.org/docs/14/pageinspect.html#id-1.11.7.32.4

create extension pageinspect;

/*    
mytest=> create extension pageinspect;
CREATE EXTENSION
mytest=> \dx
                                List of installed extensions
    Name     | Version |   Schema   |                      Description                      
-------------+---------+------------+-------------------------------------------------------
 pageinspect | 1.8     | public     | inspect the contents of database pages at a low level
 plpgsql     | 1.0     | pg_catalog | PL/pgSQL procedural language
(2 rows)
*/

create table t (id int, name varchar(10), extra text);
create unique index t_id on t(id);
create index t_name on t(name);
create index t_id_name on t(id,name);

/*    
mytest=> create table t (id int, name varchar(10), extra text);
CREATE TABLE
mytest=> create unique index t_id on t(id);
CREATE INDEX
mytest=> create index t_name on t(name);
CREATE INDEX

mytest=> create index t_id_name on t(id,name);
CREATE INDEX
mytest=> \d t
                        Table "public.t"
 Column |         Type          | Collation | Nullable | Default 
--------+-----------------------+-----------+----------+---------
 id     | integer               |           |          | 
 name   | character varying(10) |           |          | 
 extra  | text                  |           |          | 
Indexes:
    "t_id" UNIQUE, btree (id)
    "t_id_name" btree (id, name)
    "t_name" btree (name)
*/


insert into t values(1,'a','xxxx');
insert into t values(2,'a','xxxx');
insert into t values(3,'b','xxxx');
insert into t values(4,'c','xxxx');
select ctid,* from t;

/*
mytest=> select ctid,* from t;
 ctid  | id | name | extra 
-------+----+------+-------
 (0,1) |  1 | a    | xxxx
 (0,2) |  2 | a    | xxxx
 (0,3) |  3 | b    | xxxx
 (0,4) |  4 | c    | xxxx
*/

-- Check the heap table
SELECT * FROM page_header(get_raw_page('t', 0));
SELECT * FROM heap_page_items(get_raw_page('t', 0));

/*
 mytest=> SELECT * FROM page_header(get_raw_page('t', 0));
    lsn     | checksum | flags | lower | upper | special | pagesize | version | prune_xid 
------------+----------+-------+-------+-------+---------+----------+---------+-----------
 0/1C020408 |        0 |     0 |    40 |  8032 |    8192 |     8192 |       4 |         0
(1 row)

mytest=> SELECT * FROM page_header(get_raw_page('t', 0));
-[ RECORD 1 ]---------
lsn       | 0/1C020408
checksum  | 0
flags     | 0
lower     | 40
upper     | 8032
special   | 8192
pagesize  | 8192
version   | 4
prune_xid | 0


mytest=> SELECT * FROM heap_page_items(get_raw_page('t', 0));
 lp | lp_off | lp_flags | lp_len | t_xmin | t_xmax | t_field3 | t_ctid | t_infomask2 | t_infomask | t_hoff | t_bits | t_oid |          t_data          
----+--------+----------+--------+--------+--------+----------+--------+-------------+------------+--------+--------+-------+--------------------------
  1 |   8152 |        1 |     35 |    586 |      0 |        0 | (0,1)  |           3 |       2306 |     24 |        |       | \x0100000005610b78787878
  2 |   8112 |        1 |     35 |    587 |      0 |        0 | (0,2)  |           3 |       2306 |     24 |        |       | \x0200000005610b78787878
  3 |   8072 |        1 |     35 |    588 |      0 |        0 | (0,3)  |           3 |       2306 |     24 |        |       | \x0300000005620b78787878
  4 |   8032 |        1 |     35 |    589 |      0 |        0 | (0,4)  |           3 |       2306 |     24 |        |       | \x0400000005630b78787878
(4 rows)


mytest=> \x
Expanded display is on.
mytest=> SELECT * FROM heap_page_items(get_raw_page('t', 0));
-[ RECORD 1 ]-------------------------
lp          | 1
lp_off      | 8152
lp_flags    | 1
lp_len      | 35
t_xmin      | 586
t_xmax      | 0
t_field3    | 0
t_ctid      | (0,1)
t_infomask2 | 3
t_infomask  | 2306
t_hoff      | 24
t_bits      | 
t_oid       | 
t_data      | \x0100000005610b78787878
-[ RECORD 2 ]-------------------------
lp          | 2
lp_off      | 8112
lp_flags    | 1
lp_len      | 35
t_xmin      | 587
t_xmax      | 0
t_field3    | 0
t_ctid      | (0,2)
t_infomask2 | 3
t_infomask  | 2306
t_hoff      | 24
t_bits      | 
t_oid       | 
t_data      | \x0200000005610b78787878
-[ RECORD 3 ]-------------------------
lp          | 3
lp_off      | 8072
lp_flags    | 1
lp_len      | 35
t_xmin      | 588
t_xmax      | 0
t_field3    | 0
t_ctid      | (0,3)
t_infomask2 | 3
t_infomask  | 2306
t_hoff      | 24
t_bits      | 
t_oid       | 
t_data      | \x0300000005620b78787878
-[ RECORD 4 ]-------------------------
lp          | 4
lp_off      | 8032
lp_flags    | 1
lp_len      | 35
t_xmin      | 589
t_xmax      | 0
t_field3    | 0
t_ctid      | (0,4)
t_infomask2 | 3
t_infomask  | 2306
t_hoff      | 24
t_bits      | 
t_oid       | 
t_data      | \x0400000005630b78787878

*/

-- Analyze index t_id
SELECT * FROM bt_metap('t_id');
SELECT * FROM bt_page_stats('t_id', 1);
SELECT itemoffset, ctid, itemlen, nulls, vars, data, dead, htid, tids[0:2] AS some_tids
FROM bt_page_items('t_id', 1);


/*
mytest=> SELECT * FROM bt_metap('t_id');
-[ RECORD 1 ]-----------+-------
magic                   | 340322
version                 | 4
root                    | 1
level                   | 0
fastroot                | 1
fastlevel               | 0
oldest_xact             | 0
last_cleanup_num_tuples | -1
allequalimage           | t


mytest=> SELECT * FROM bt_page_stats('t_id', 1);
-[ RECORD 1 ]-+-----
blkno         | 1
type          | l
live_items    | 4
dead_items    | 0
avg_item_size | 16
page_size     | 8192
free_size     | 8068
btpo_prev     | 0
btpo_next     | 0
btpo          | 0
btpo_flags    | 3

mytest=> SELECT itemoffset, ctid, itemlen, nulls, vars, data, dead, htid, tids[0:2] AS some_tids
mytest-> FROM bt_page_items('t_id', 1);
-[ RECORD 1 ]-----------------------
itemoffset | 1
ctid       | (0,1)
itemlen    | 16
nulls      | f
vars       | f
data       | 01 00 00 00 00 00 00 00
dead       | f
htid       | (0,1)
some_tids  | 
-[ RECORD 2 ]-----------------------
itemoffset | 2
ctid       | (0,2)
itemlen    | 16
nulls      | f
vars       | f
data       | 02 00 00 00 00 00 00 00
dead       | f
htid       | (0,2)
some_tids  | 
-[ RECORD 3 ]-----------------------
itemoffset | 3
ctid       | (0,3)
itemlen    | 16
nulls      | f
vars       | f
data       | 03 00 00 00 00 00 00 00
dead       | f
htid       | (0,3)
some_tids  | 
-[ RECORD 4 ]-----------------------
itemoffset | 4
ctid       | (0,4)
itemlen    | 16
nulls      | f
vars       | f
data       | 04 00 00 00 00 00 00 00
dead       | f
htid       | (0,4)
some_tids  | 
*/


-- Analyze index t_name
SELECT * FROM bt_metap('t_name');
SELECT * FROM bt_page_stats('t_name', 1);
SELECT itemoffset, ctid, itemlen, nulls, vars, data, dead, htid, tids[0:2] AS some_tids
FROM bt_page_items('t_name', 1);

/*
mytest=> SELECT * FROM bt_metap('t_name');
-[ RECORD 1 ]-----------+-------
magic                   | 340322
version                 | 4
root                    | 1
level                   | 0
fastroot                | 1
fastlevel               | 0
oldest_xact             | 0
last_cleanup_num_tuples | -1
allequalimage           | t

mytest=> 
mytest=> 
mytest=> SELECT * FROM bt_page_stats('t_name', 1);
-[ RECORD 1 ]-+-----
blkno         | 1
type          | l
live_items    | 4
dead_items    | 0
avg_item_size | 16
page_size     | 8192
free_size     | 8068
btpo_prev     | 0
btpo_next     | 0
btpo          | 0
btpo_flags    | 3

mytest=> 
mytest=> SELECT itemoffset, ctid, itemlen, nulls, vars, data, dead, htid, tids[0:2] AS some_tids
mytest-> FROM bt_page_items('t_name', 1);
-[ RECORD 1 ]-----------------------
itemoffset | 1
ctid       | (0,1)
itemlen    | 16
nulls      | f
vars       | t
data       | 05 61 00 00 00 00 00 00
dead       | f
htid       | (0,1)
some_tids  | 
-[ RECORD 2 ]-----------------------
itemoffset | 2
ctid       | (0,2)
itemlen    | 16
nulls      | f
vars       | t
data       | 05 61 00 00 00 00 00 00
dead       | f
htid       | (0,2)
some_tids  | 
-[ RECORD 3 ]-----------------------
itemoffset | 3
ctid       | (0,3)
itemlen    | 16
nulls      | f
vars       | t
data       | 05 62 00 00 00 00 00 00
dead       | f
htid       | (0,3)
some_tids  | 
-[ RECORD 4 ]-----------------------
itemoffset | 4
ctid       | (0,4)
itemlen    | 16
nulls      | f
vars       | t
data       | 05 63 00 00 00 00 00 00
dead       | f
htid       | (0,4)
some_tids  | 

*/


-- Analyze composite index t_id_name

SELECT * FROM bt_metap('t_id_name');
SELECT * FROM bt_page_stats('t_id_name', 1);
SELECT itemoffset, ctid, itemlen, nulls, vars, data, dead, htid, tids[0:2] AS some_tids
FROM bt_page_items('t_id_name', 1);

/*

mytest=> SELECT * FROM bt_metap('t_id_name');
-[ RECORD 1 ]-----------+-------
magic                   | 340322
version                 | 4
root                    | 1
level                   | 0
fastroot                | 1
fastlevel               | 0
oldest_xact             | 0
last_cleanup_num_tuples | -1
allequalimage           | t


mytest=> SELECT * FROM bt_page_stats('t_id_name', 1);
-[ RECORD 1 ]-+-----
blkno         | 1
type          | l
live_items    | 4
dead_items    | 0
avg_item_size | 16
page_size     | 8192
free_size     | 8068
btpo_prev     | 0
btpo_next     | 0
btpo          | 0
btpo_flags    | 3


mytest=> SELECT itemoffset, ctid, itemlen, nulls, vars, data, dead, htid, tids[0:2] AS some_tids
mytest-> FROM bt_page_items('t_id_name', 1);
-[ RECORD 1 ]-----------------------
itemoffset | 1
ctid       | (0,1)
itemlen    | 16
nulls      | f
vars       | t
data       | 01 00 00 00 05 61 00 00
dead       | f
htid       | (0,1)
some_tids  | 
-[ RECORD 2 ]-----------------------
itemoffset | 2
ctid       | (0,2)
itemlen    | 16
nulls      | f
vars       | t
data       | 02 00 00 00 05 61 00 00
dead       | f
htid       | (0,2)
some_tids  | 
-[ RECORD 3 ]-----------------------
itemoffset | 3
ctid       | (0,3)
itemlen    | 16
nulls      | f
vars       | t
data       | 03 00 00 00 05 62 00 00
dead       | f
htid       | (0,3)
some_tids  | 
-[ RECORD 4 ]-----------------------
itemoffset | 4
ctid       | (0,4)
itemlen    | 16
nulls      | f
vars       | t
data       | 04 00 00 00 05 63 00 00
dead       | f
htid       | (0,4)
some_tids  | 
*/


-- What if data larger than 16 bytes?

insert into t values(1000000000,'abcdefghij','yyyy');
SELECT itemoffset, ctid, itemlen, nulls, vars, data, dead, htid, tids[0:2] AS some_tids
FROM bt_page_items('t_id', 1);
SELECT itemoffset, ctid, itemlen, nulls, vars, data, dead, htid, tids[0:2] AS some_tids
FROM bt_page_items('t_name', 1);
SELECT itemoffset, ctid, itemlen, nulls, vars, data, dead, htid, tids[0:2] AS some_tids
FROM bt_page_items('t_id_name', 1);


/*
mytest=> insert into t values(1000000000,'abcdefghij','yyyy');
INSERT 0 1
mytest=> 

mytest=> SELECT itemoffset, ctid, itemlen, nulls, vars, data, dead, htid, tids[0:2] AS some_tids
mytest-> FROM bt_page_items('t_id', 1);
 itemoffset | ctid  | itemlen | nulls | vars |          data           | dead | htid  | some_tids 
------------+-------+---------+-------+------+-------------------------+------+-------+-----------
          1 | (0,1) |      16 | f     | f    | 01 00 00 00 00 00 00 00 | f    | (0,1) | 
          2 | (0,2) |      16 | f     | f    | 02 00 00 00 00 00 00 00 | f    | (0,2) | 
          3 | (0,3) |      16 | f     | f    | 03 00 00 00 00 00 00 00 | f    | (0,3) | 
          4 | (0,4) |      16 | f     | f    | 04 00 00 00 00 00 00 00 | f    | (0,4) | 
          5 | (0,5) |      16 | f     | f    | 00 ca 9a 3b 00 00 00 00 | f    | (0,5) | 
(5 rows)

mytest=> SELECT itemoffset, ctid, itemlen, nulls, vars, data, dead, htid, tids[0:2] AS some_tids
FROM bt_page_items('t_name', 1);
 itemoffset | ctid  | itemlen | nulls | vars |                      data                       | dead | htid  | some_tids 
------------+-------+---------+-------+------+-------------------------------------------------+------+-------+-----------
          1 | (0,1) |      16 | f     | t    | 05 61 00 00 00 00 00 00                         | f    | (0,1) | 
          2 | (0,2) |      16 | f     | t    | 05 61 00 00 00 00 00 00                         | f    | (0,2) | 
          3 | (0,5) |      24 | f     | t    | 17 61 62 63 64 65 66 67 68 69 6a 00 00 00 00 00 | f    | (0,5) | 
          4 | (0,3) |      16 | f     | t    | 05 62 00 00 00 00 00 00                         | f    | (0,3) | 
          5 | (0,4) |      16 | f     | t    | 05 63 00 00 00 00 00 00                         | f    | (0,4) | 
(5 rows)


mytest=> SELECT itemoffset, ctid, itemlen, nulls, vars, data, dead, htid, tids[0:2] AS some_tids
mytest-> FROM bt_page_items('t_id_name', 1);
 itemoffset | ctid  | itemlen | nulls | vars |                      data                       | dead | htid  | some_tids 
------------+-------+---------+-------+------+-------------------------------------------------+------+-------+-----------
          1 | (0,1) |      16 | f     | t    | 01 00 00 00 05 61 00 00                         | f    | (0,1) | 
          2 | (0,2) |      16 | f     | t    | 02 00 00 00 05 61 00 00                         | f    | (0,2) | 
          3 | (0,3) |      16 | f     | t    | 03 00 00 00 05 62 00 00                         | f    | (0,3) | 
          4 | (0,4) |      16 | f     | t    | 04 00 00 00 05 63 00 00                         | f    | (0,4) | 
          5 | (0,5) |      24 | f     | t    | 00 ca 9a 3b 17 61 62 63 64 65 66 67 68 69 6a 00 | f    | (0,5) | 



mytest=> select convert_from('\x78','utf-8');
 convert_from 
--------------
 x

*/
