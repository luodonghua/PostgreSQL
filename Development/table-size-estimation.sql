mytest=> CREATE TABLE t_test (id serial, name text);
CREATE TABLE
mytest=> INSERT INTO t_test (name) SELECT 'hans' FROM generate_series(1, 2000000);
INSERT 0 2000000
mytest=> INSERT INTO t_test (name) SELECT 'paul' FROM generate_series(1, 2000000);
INSERT 0 2000000
mytest=> \dt+ t_test
                            List of relations
 Schema |  Name  | Type  |  Owner   | Persistence |  Size  | Description 
--------+--------+-------+----------+-------------+--------+-------------
 public | t_test | table | postgres | permanent   | 169 MB | 
(1 row)

mytest=> create extension pageinspect;
CREATE EXTENSION

mytest=> SELECT count(*) FROM heap_page_items(get_raw_page('t_test', 0));
 count 
-------
   185
(1 row)

mytest=> SELECT count(*) FROM heap_page_items(get_raw_page('t_test', 1));
 count 
-------
   185
(1 row)


mytest=> SELECT * FROM heap_page_items(get_raw_page('t_test', 1)) where lp=1;
-[ RECORD 1 ]---------------------
lp          | 1
lp_off      | 8152
lp_flags    | 1
lp_len      | 33
t_xmin      | 584
t_xmax      | 0
t_field3    | 0
t_ctid      | (1,1)
t_infomask2 | 2
t_infomask  | 2306
t_hoff      | 24
t_bits      | 
t_oid       | 
t_data      | \xba0000000b68616e73

mytest=> SELECT * FROM heap_page_items(get_raw_page('t_test', 1)) where lp=2;
-[ RECORD 1 ]---------------------
lp          | 2
lp_off      | 8112
lp_flags    | 1
lp_len      | 33
t_xmin      | 584
t_xmax      | 0
t_field3    | 0
t_ctid      | (1,2)
t_infomask2 | 2
t_infomask  | 2306
t_hoff      | 24
t_bits      | 
t_oid       | 
t_data      | \xbb0000000b68616e73

mytest=> SELECT * FROM heap_page_items(get_raw_page('t_test', 1)) where lp=185;
-[ RECORD 1 ]---------------------
lp          | 185
lp_off      | 792
lp_flags    | 1
lp_len      | 33
t_xmin      | 584
t_xmax      | 0
t_field3    | 0
t_ctid      | (1,185)
t_infomask2 | 2
t_infomask  | 2306
t_hoff      | 24
t_bits      | 
t_oid       | 
t_data      | \x720100000b68616e73


https://www.postgresql.org/docs/14/storage-page-layout.html

==> Block Size                  8192 bytes
--> PageHeaderData              24 bytes
  --> Per row Data              ceiling(24+9)/8 + 4 = 44
    --> ItemId:					4 bytes per row 
    --> HeapTupleHeaderData:    24 bytes per row
    --> Actual Data             9 bytes (4 bytes for column "id", 5 bytes for column "name")


Math: 24+44*185 = 8164

Total Size: ( 2000000 + 2000000 ) / 185 * 8 / 1024 = 168 MB





