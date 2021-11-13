/*
max_standby_streaming_delay: 
    (ms) Sets the maximum delay before canceling queries when a hot standby server is processing streamed WAL data.
max_standby_archive_delay: 
    (ms) Sets the maximum delay before canceling queries when a hot standby server is processing archived WAL data.
hot_standby_feedback: 
    Allows feedback from a hot standby to the primary that will avoid query conflicts.
*/


select name,setting from pg_settings
where name in ('max_standby_streaming_delay','hot_standby_feedback','max_standby_streaming_delay');

/*
mytest=> select name,setting from pg_settings
mytest-> where name in ('max_standby_streaming_delay','hot_standby_feedback','max_standby_streaming_delay');
            name             | setting 
-----------------------------+---------
 hot_standby_feedback        | off
 max_standby_streaming_delay | 30000
(2 rows)
*/



create table t1 (id int);
insert into t1 values (1);

/*
mytest=> create table t1 (id int);
CREATE TABLE

mytest=> insert into t1 values (1);
INSERT 0 1
mytest=> select * from t1;
 id 
----
  1
(1 row)
*/


-- generate workload so LSN increased continiously at source 
do
$$
declare 
  i bigint;
begin
  for i in 1..100000000 loop
     update t1 set id = i;
     commit;
  end loop;
end;
$$
;


select * from pg_stat_replication;

/*
mytest=> select * from pg_stat_replication;
-[ RECORD 1 ]----+------------------------------
pid              | 8318
usesysid         | 16396
usename          | rdsrepladmin
application_name | walreceiver
client_addr      | 172.17.4.208
client_hostname  | 
client_port      | 53678
backend_start    | 2021-11-13 02:51:35.162109+00
backend_xmin     | 
state            | streaming
sent_lsn         | 0/381B1DC0
write_lsn        | 0/381B1DC0
flush_lsn        | 0/381B1D50
replay_lsn       | 0/381B1D50
write_lag        | 00:00:00.000126
flush_lag        | 00:00:00.000126
replay_lag       | 00:00:00.000126
sync_priority    | 0
sync_state       | async
reply_time       | 2021-11-13 03:28:20.186629+00
*/


-- on Read Replica Node

begin transaction;
set transaction isolation level repeatable read;
select * from t1;
-- wait few seconds
select * from t1;
-- wait few seconds
select * from t1;

/*
mytest=> begin transaction;
BEGIN
mytest=*> set transaction isolation level repeatable read;
SET
mytest=*> select * from t1;
   id   
--------
 299543
(1 row)

mytest=*> select * from t1;
   id   
--------
 299543
(1 row)

mytest=*> select * from t1;
   id   
--------
 299543
(1 row)

mytest=*> select * from t1;
FATAL:  terminating connection due to conflict with recovery
DETAIL:  User query might have needed to see row versions that must be removed.
HINT:  In a moment you should be able to reconnect to the database and repeat your command.
SSL connection has been closed unexpectedly
The connection to the server was lost. Attempting reset: Succeeded.
SSL connection (protocol: TLSv1.2, cipher: ECDHE-RSA-AES256-GCM-SHA384, bits: 256, compression: off)
mytest=> 
*/


-- On Master Node

select * from pg_stat_replication;

/*

mytest=> select * from pg_stat_replication;
-[ RECORD 1 ]----+------------------------------
pid              | 8318
usesysid         | 16396
usename          | rdsrepladmin
application_name | walreceiver
client_addr      | 172.17.4.208
client_hostname  | 
client_port      | 53678
backend_start    | 2021-11-13 02:51:35.162109+00
backend_xmin     | 
state            | streaming
sent_lsn         | 0/3C01DC78
write_lsn        | 0/3C01DC78
flush_lsn        | 0/3C01DC78
replay_lsn       | 0/3A0C40E0
write_lag        | 00:00:00.000135
flush_lag        | 00:00:00.001063
replay_lag       | 00:00:17.262337
sync_priority    | 0
sync_state       | async
reply_time       | 2021-11-13 03:32:58.91535+00

-- the lag close to 0 after query on read replica cancelled

mytest=> select * from pg_stat_replication;
-[ RECORD 1 ]----+------------------------------
pid              | 8318
usesysid         | 16396
usename          | rdsrepladmin
application_name | walreceiver
client_addr      | 172.17.4.208
client_hostname  | 
client_port      | 53678
backend_start    | 2021-11-13 02:51:35.162109+00
backend_xmin     | 
state            | streaming
sent_lsn         | 0/3D62C138
write_lsn        | 0/3D62C138
flush_lsn        | 0/3D62C138
replay_lsn       | 0/3D62C138
write_lag        | 00:00:00.000146
flush_lag        | 00:00:00.000674
replay_lag       | 00:00:00.000677
sync_priority    | 0
sync_state       | async
reply_time       | 2021-11-13 03:36:04.63463+00
*/

--- Testing again with hot_standby_feedback=1 (no reboot is required)

select name,setting from pg_settings
where name in ('max_standby_streaming_delay','hot_standby_feedback','max_standby_streaming_delay');

/*
mytest=> select name,setting from pg_settings
mytest-> where name in ('max_standby_streaming_delay','hot_standby_feedback','max_standby_streaming_delay');
            name             | setting 
-----------------------------+---------
 hot_standby_feedback        | on
 max_standby_streaming_delay | 30000
*/



-- on Read Replica Node

begin transaction;
set transaction isolation level repeatable read;
select * from t1;
-- wait few seconds
select * from t1;
-- wait few seconds
select * from t1;

/*
mytest=> begin transaction;
BEGIN
mytest=*> set transaction isolation level repeatable read;
SET
mytest=*> 
mytest=*> select * from t1;
   id   
--------
 845974
(1 row)

mytest=*> select * from t1;
   id   
--------
 845974
(1 row)

mytest=*> select * from t1;
   id   
--------
 845974
(1 row)

mytest=*> select * from t1;
   id   
--------
 845974
(1 row)

mytest=*> select * from t1;
   id   
--------
 845974
(1 row)

mytest=*> commit;
COMMIT
*/


-- On Master Node

select * from pg_stat_replication;
/*
mytest=> select * from pg_stat_replication;
-[ RECORD 1 ]----+------------------------------
pid              | 8318
usesysid         | 16396
usename          | rdsrepladmin
application_name | walreceiver
client_addr      | 172.17.4.208
client_hostname  | 
client_port      | 53678
backend_start    | 2021-11-13 02:51:35.162109+00
backend_xmin     | 846573
state            | streaming
sent_lsn         | 0/44E26B48
write_lsn        | 0/44E26B48
flush_lsn        | 0/44E26B48
replay_lsn       | 0/44E26B48
write_lag        | 00:00:00.000149
flush_lag        | 00:00:00.000642
replay_lag       | 00:00:00.000646
sync_priority    | 0
sync_state       | async
reply_time       | 2021-11-13 03:42:25.608981+00

mytest=> select * from pg_stat_replication;
-[ RECORD 1 ]----+------------------------------
pid              | 8318
usesysid         | 16396
usename          | rdsrepladmin
application_name | walreceiver
client_addr      | 172.17.4.208
client_hostname  | 
client_port      | 53678
backend_start    | 2021-11-13 02:51:35.162109+00
backend_xmin     | 846573
state            | streaming
sent_lsn         | 0/452507E0
write_lsn        | 0/452507E0
flush_lsn        | 0/452507E0
replay_lsn       | 0/452507E0
write_lag        | 00:00:00.000263
flush_lag        | 00:00:00.000795
replay_lag       | 00:00:00.000825
sync_priority    | 0
sync_state       | async
reply_time       | 2021-11-13 03:43:52.074713+00
*/

--- Testing again with hot_standby_feedback=1 & max_standby_streaming_delay=-1 (no reboot is required)

select name,setting from pg_settings
where name in ('max_standby_streaming_delay','hot_standby_feedback','max_standby_streaming_delay');
/*
mytest=> select name,setting from pg_settings
mytest-> where name in ('max_standby_streaming_delay','hot_standby_feedback','max_standby_streaming_delay');
            name             | setting 
-----------------------------+---------
 hot_standby_feedback        | on
 max_standby_streaming_delay | -1
(2 rows)
*/

-- on Read Replica Node

begin transaction;
set transaction isolation level repeatable read;
select clock_timestamp(),id from t1;
-- wait few seconds
select clock_timestamp(),id from t1;
-- wait few seconds
select clock_timestamp(),id from t1;

/*

mytest=> begin transaction;
set transaction isolation level repeatable read;
BEGIN
mytest=*> set transaction isolation level repeatable read;
SET
mytest=*> 
mytest=*> select clock_timestamp(),id from t1;
        clock_timestamp        |   id    
-------------------------------+---------
 2021-11-13 03:55:02.438018+00 | 1204392
(1 row)

mytest=*> select clock_timestamp(),id from t1;
        clock_timestamp        |   id    
-------------------------------+---------
 2021-11-13 03:55:27.050267+00 | 1204392
(1 row)

mytest=*> select clock_timestamp(),id from t1;
        clock_timestamp        |   id    
-------------------------------+---------
 2021-11-13 03:55:46.081596+00 | 1204392
(1 row)

mytest=*> commit;
COMMIT

*/
-- On Master Node

select * from pg_stat_replication;

/*
mytest=> select * from pg_stat_replication;
-[ RECORD 1 ]----+------------------------------
pid              | 8318
usesysid         | 16396
usename          | rdsrepladmin
application_name | walreceiver
client_addr      | 172.17.4.208
client_hostname  | 
client_port      | 53678
backend_start    | 2021-11-13 02:51:35.162109+00
backend_xmin     | 1204994
state            | streaming
sent_lsn         | 0/5016CB88
write_lsn        | 0/5016CB18
flush_lsn        | 0/5016CB18
replay_lsn       | 0/5016CB18
write_lag        | 00:00:00.00015
flush_lag        | 00:00:00.000861
replay_lag       | 00:00:00.000876
sync_priority    | 0
sync_state       | async
reply_time       | 2021-11-13 03:55:06.79656+00

mytest=> select * from pg_stat_replication;
-[ RECORD 1 ]----+------------------------------
pid              | 8318
usesysid         | 16396
usename          | rdsrepladmin
application_name | walreceiver
client_addr      | 172.17.4.208
client_hostname  | 
client_port      | 53678
backend_start    | 2021-11-13 02:51:35.162109+00
backend_xmin     | 1204994
state            | streaming
sent_lsn         | 0/503421A8
write_lsn        | 0/503421A8
flush_lsn        | 0/50342138
replay_lsn       | 0/50342138
write_lag        | 00:00:00.000223
flush_lag        | 00:00:00.000223
replay_lag       | 00:00:00.000223
sync_priority    | 0
sync_state       | async
reply_time       | 2021-11-13 03:55:54.333883+00

*/



-- monitoring scripts run on the standby/read replica
select * from pg_stat_wal_receiver;
select pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn(), pg_last_xact_replay_timestamp();

/*
mytest=> select * from pg_stat_wal_receiver;
-[ RECORD 1 ]---------+-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
pid                   | 10929
status                | streaming
receive_start_lsn     | 0/18000000
receive_start_tli     | 1
written_lsn           | 0/58379AD0
flushed_lsn           | 0/58379AD0
received_tli          | 1
last_msg_send_time    | 2021-11-13 04:06:17.47048+00
last_msg_receipt_time | 2021-11-13 04:06:17.471265+00
latest_end_lsn        | 0/58379AD0
latest_end_time       | 2021-11-13 04:06:17.47048+00
slot_name             | 
sender_host           | 172.17.4.21
sender_port           | 5432
conninfo              | user=rdsrepladmin password=******** channel_binding=prefer dbname=replication host=172.17.4.21 port=5432 fallback_application_name=walreceiver sslmode=prefer sslcompression=0 ssl_min_protocol_version=TLSv1.2 gssencmode=prefer krbsrvname=whatever target_session_attrs=any

mytest=> 
mytest=> select pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn(), pg_last_xact_replay_timestamp();
 pg_last_wal_receive_lsn | pg_last_wal_replay_lsn | pg_last_xact_replay_timestamp 
-------------------------+------------------------+-------------------------------
 0/58439818              | 0/58439818             | 2021-11-13 04:06:40.140538+00
(1 row)
*/



--- Testing again with:
---    hot_standby_feedback=1 & max_standby_streaming_delay=-1 on primary/first replica
---    hot_standby_feedback=0 & max_standby_streaming_delay=-1 on second replica

-- Primary:         postgres-instance1.cnxwg0faljnj.us-east-1.rds.amazonaws.com
-- First Replica:   postgres-instance-rr.cnxwg0faljnj.us-east-1.rds.amazonaws.com
-- Second Replca:   postgres-instance-rr2.cnxwg0faljnj.us-east-1.rds.amazonaws.com

-- running on Primary: (1st session)
select name,setting from pg_settings
where name in ('max_standby_streaming_delay','hot_standby_feedback','max_standby_streaming_delay');
-- generate workload so LSN increased continiously at source 
do
$$
declare 
  i bigint;
begin
  for i in 1..100000000 loop
     update t1 set id = i;
     commit;
  end loop;
end;
$$
;

/*

mytest=> select name,setting from pg_settings
mytest-> where name in ('max_standby_streaming_delay','hot_standby_feedback','max_standby_streaming_delay');
            name             | setting 
-----------------------------+---------
 hot_standby_feedback        | on
 max_standby_streaming_delay | -1
(2 rows)

-- generate workload so LSN increased continiously at source 
do
$$
declare 
  i bigint;
begin
  for i in 1..100000000 loop
     update t1 set id = i;
     commit;
  end loop;
end;
$$
;
*/


-- running on First Replica: (1st session)
select name,setting from pg_settings
where name in ('max_standby_streaming_delay','hot_standby_feedback','max_standby_streaming_delay');

begin transaction;
set transaction isolation level repeatable read;
select clock_timestamp(),id from t1;
-- wait few seconds
select clock_timestamp(),id from t1;
-- wait few seconds
select clock_timestamp(),id from t1;


/*

mytest=> select name,setting from pg_settings
mytest-> where name in ('max_standby_streaming_delay','hot_standby_feedback','max_standby_streaming_delay');
            name             | setting 
-----------------------------+---------
 hot_standby_feedback        | on
 max_standby_streaming_delay | -1
(2 rows)

mytest=> 
mytest=> begin transaction;
BEGIN
mytest=*> set transaction isolation level repeatable read;
SET
mytest=*> select clock_timestamp(),id from t1;
       clock_timestamp        |   id   
------------------------------+--------
 2021-11-13 04:47:44.96726+00 | 172961
(1 row)

mytest=*> select clock_timestamp(),id from t1;
       clock_timestamp        |   id   
------------------------------+--------
 2021-11-13 04:49:59.15892+00 | 172961
(1 row)

mytest=*> select clock_timestamp(),id from t1;
        clock_timestamp        |   id   
-------------------------------+--------
 2021-11-13 05:04:54.463664+00 | 172961
(1 row)

mytest=*> select clock_timestamp(),id from t1;
        clock_timestamp        |   id   
-------------------------------+--------
 2021-11-13 05:06:54.644168+00 | 172961
(1 row)

mytest=*> commit;
COMMIT
*/



-- running on Second Replca: (1st session)
select name,setting from pg_settings
where name in ('max_standby_streaming_delay','hot_standby_feedback','max_standby_streaming_delay');


begin transaction;
set transaction isolation level repeatable read;
select clock_timestamp(),id from t1;
-- wait few seconds
select clock_timestamp(),id from t1;
-- wait few seconds
select clock_timestamp(),id from t1;

/*

mytest=> select name,setting from pg_settings
mytest-> where name in ('max_standby_streaming_delay','hot_standby_feedback','max_standby_streaming_delay');
            name             | setting 
-----------------------------+---------
 hot_standby_feedback        | off
 max_standby_streaming_delay | -1
(2 rows)



mytest=> begin transaction;
BEGIN
mytest=*> set transaction isolation level repeatable read;
SET
mytest=*> select clock_timestamp(),id from t1;
        clock_timestamp        |   id   
-------------------------------+--------
 2021-11-13 04:48:27.874233+00 | 202044
(1 row)

mytest=*> select clock_timestamp(),id from t1;
        clock_timestamp        |   id   
-------------------------------+--------
 2021-11-13 04:50:04.278137+00 | 202044
(1 row)

mytest=*> select clock_timestamp(),id from t1;
        clock_timestamp        |   id   
-------------------------------+--------
 2021-11-13 05:04:58.586146+00 | 202044
(1 row)

mytest=*> select clock_timestamp(),id from t1;
       clock_timestamp        |   id   
------------------------------+--------
 2021-11-13 05:07:00.26481+00 | 202044
(1 row)

mytest=*> commit;
COMMIT

*/


-- running on Primary: (2nd session)
select * from pg_stat_replication;
/*


mytest=> select * from pg_stat_replication;
-[ RECORD 1 ]----+------------------------------
pid              | 8318
usesysid         | 16396
usename          | rdsrepladmin
application_name | walreceiver
client_addr      | 172.17.4.208
client_hostname  | 
client_port      | 53678
backend_start    | 2021-11-13 02:51:35.162109+00
backend_xmin     | 2084624
state            | streaming
sent_lsn         | 0/797D6768
write_lsn        | 0/797D6768
flush_lsn        | 0/797D6768
replay_lsn       | 0/797D6768
write_lag        | 00:00:00.000162
flush_lag        | 00:00:00.001258
replay_lag       | 00:00:00.001291
sync_priority    | 0
sync_state       | async
reply_time       | 2021-11-13 04:49:26.252501+00
-[ RECORD 2 ]----+------------------------------
pid              | 19766
usesysid         | 16396
usename          | rdsrepladmin
application_name | walreceiver
client_addr      | 172.17.4.197
client_hostname  | 
client_port      | 39216
backend_start    | 2021-11-13 04:41:02.6988+00
backend_xmin     | 
state            | streaming
sent_lsn         | 0/797D67D8
write_lsn        | 0/797D6768
flush_lsn        | 0/797D6768
replay_lsn       | 0/797D6768
write_lag        | 00:00:00.000146
flush_lag        | 00:00:00.000764
replay_lag       | 00:00:00.000767
sync_priority    | 0
sync_state       | async
reply_time       | 2021-11-13 04:49:26.250713+00


mytest=> select * from pg_stat_replication;
-[ RECORD 1 ]----+------------------------------
pid              | 8318
usesysid         | 16396
usename          | rdsrepladmin
application_name | walreceiver
client_addr      | 172.17.4.208
client_hostname  | 
client_port      | 53678
backend_start    | 2021-11-13 02:51:35.162109+00
backend_xmin     | 2084624
state            | streaming
sent_lsn         | 0/7C15FBF8
write_lsn        | 0/7C15FBF8
flush_lsn        | 0/7C15FBF8
replay_lsn       | 0/7C15FBF8
write_lag        | 00:00:00.000134
flush_lag        | 00:00:00.000825
replay_lag       | 00:00:00.000834
sync_priority    | 0
sync_state       | async
reply_time       | 2021-11-13 04:50:08.080834+00
-[ RECORD 2 ]----+------------------------------
pid              | 19766
usesysid         | 16396
usename          | rdsrepladmin
application_name | walreceiver
client_addr      | 172.17.4.197
client_hostname  | 
client_port      | 39216
backend_start    | 2021-11-13 04:41:02.6988+00
backend_xmin     | 
state            | streaming
sent_lsn         | 0/7C15FBF8
write_lsn        | 0/7C15FBF8
flush_lsn        | 0/7C15FBF8
replay_lsn       | 0/7C15FBF8
write_lag        | 00:00:00.000202
flush_lag        | 00:00:00.000949
replay_lag       | 00:00:00.000966
sync_priority    | 0
sync_state       | async
reply_time       | 2021-11-13 04:50:08.079774+00


mytest=> select * from pg_stat_replication;
-[ RECORD 1 ]----+------------------------------
pid              | 8318
usesysid         | 16396
usename          | rdsrepladmin
application_name | walreceiver
client_addr      | 172.17.4.208
client_hostname  | 
client_port      | 53678
backend_start    | 2021-11-13 02:51:35.162109+00
backend_xmin     | 2084624
state            | streaming
sent_lsn         | 0/880B5E38
write_lsn        | 0/880B5E38
flush_lsn        | 0/880B5E38
replay_lsn       | 0/880B5E38
write_lag        | 00:00:00.000149
flush_lag        | 00:00:00.000819
replay_lag       | 00:00:00.000836
sync_priority    | 0
sync_state       | async
reply_time       | 2021-11-13 05:05:21.477371+00
-[ RECORD 2 ]----+------------------------------
pid              | 19766
usesysid         | 16396
usename          | rdsrepladmin
application_name | walreceiver
client_addr      | 172.17.4.197
client_hostname  | 
client_port      | 39216
backend_start    | 2021-11-13 04:41:02.6988+00
backend_xmin     | 
state            | streaming
sent_lsn         | 0/880B5E38
write_lsn        | 0/880B5E38
flush_lsn        | 0/880B5E38
replay_lsn       | 0/880B5E38
write_lag        | 00:00:00.000268
flush_lag        | 00:00:00.000961
replay_lag       | 00:00:00.000987
sync_priority    | 0
sync_state       | async
reply_time       | 2021-11-13 05:05:21.47589+00

*/

-- running on First Replica: (2nd session)
\x auto
select * from pg_stat_wal_receiver;
select pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn(), pg_last_xact_replay_timestamp();

/*
mytest=> \x auto
Expanded display is used automatically.
mytest=> select * from pg_stat_wal_receiver;
-[ RECORD 1 ]---------+-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
pid                   | 10929
status                | streaming
receive_start_lsn     | 0/18000000
receive_start_tli     | 1
written_lsn           | 0/7C2677E8
flushed_lsn           | 0/7C2677E8
received_tli          | 1
last_msg_send_time    | 2021-11-13 04:50:36.36034+00
last_msg_receipt_time | 2021-11-13 04:50:36.363056+00
latest_end_lsn        | 0/7C2677E8
latest_end_time       | 2021-11-13 04:50:36.36034+00
slot_name             | 
sender_host           | 172.17.4.21
sender_port           | 5432
conninfo              | user=rdsrepladmin password=******** channel_binding=prefer dbname=replication host=172.17.4.21 port=5432 fallback_application_name=walreceiver sslmode=prefer sslcompression=0 ssl_min_protocol_version=TLSv1.2 gssencmode=prefer krbsrvname=whatever target_session_attrs=any

mytest=> select pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn(), pg_last_xact_replay_timestamp();
 pg_last_wal_receive_lsn | pg_last_wal_replay_lsn | pg_last_xact_replay_timestamp 
-------------------------+------------------------+-------------------------------
 0/7C2A2188              | 0/7C2A2188             | 2021-11-13 04:50:43.160063+00
(1 row)

mytest=> 
mytest=> select * from pg_stat_wal_receiver;
-[ RECORD 1 ]---------+-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
pid                   | 10929
status                | streaming
receive_start_lsn     | 0/18000000
receive_start_tli     | 1
written_lsn           | 0/88123210
flushed_lsn           | 0/88123210
received_tli          | 1
last_msg_send_time    | 2021-11-13 05:05:50.849746+00
last_msg_receipt_time | 2021-11-13 05:05:50.851854+00
latest_end_lsn        | 0/88123210
latest_end_time       | 2021-11-13 05:05:50.849746+00
slot_name             | 
sender_host           | 172.17.4.21
sender_port           | 5432
conninfo              | user=rdsrepladmin password=******** channel_binding=prefer dbname=replication host=172.17.4.21 port=5432 fallback_application_name=walreceiver sslmode=prefer sslcompression=0 ssl_min_protocol_version=TLSv1.2 gssencmode=prefer krbsrvname=whatever target_session_attrs=any

mytest=> select pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn(), pg_last_xact_replay_timestamp();
 pg_last_wal_receive_lsn | pg_last_wal_replay_lsn | pg_last_xact_replay_timestamp 
-------------------------+------------------------+-------------------------------
 0/88129620              | 0/88129620             | 2021-11-13 05:05:52.664062+00
(1 row)
*/


-- running on Second Replca: (2nd session)

\x auto
select * from pg_stat_wal_receiver;
select pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn(), pg_last_xact_replay_timestamp();

/*
mytest=> \x auto
Expanded display is used automatically.
mytest=> select * from pg_stat_wal_receiver;
-[ RECORD 1 ]---------+-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
pid                   | 1804
status                | streaming
receive_start_lsn     | 0/74000000
receive_start_tli     | 1
written_lsn           | 0/7C3FBC50
flushed_lsn           | 0/7C3FBC50
received_tli          | 1
last_msg_send_time    | 2021-11-13 04:51:25.237689+00
last_msg_receipt_time | 2021-11-13 04:51:25.239871+00
latest_end_lsn        | 0/7C3FBC50
latest_end_time       | 2021-11-13 04:51:25.237689+00
slot_name             | 
sender_host           | 172.17.4.21
sender_port           | 5432
conninfo              | user=rdsrepladmin password=******** channel_binding=prefer dbname=replication host=172.17.4.21 port=5432 fallback_application_name=walreceiver sslmode=prefer sslcompression=0 ssl_min_protocol_version=TLSv1.2 gssencmode=prefer krbsrvname=whatever target_session_attrs=any

mytest=> select pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn(), pg_last_xact_replay_timestamp();
 pg_last_wal_receive_lsn | pg_last_wal_replay_lsn | pg_last_xact_replay_timestamp 
-------------------------+------------------------+-------------------------------
 0/7C423C10              | 0/7C423C10             | 2021-11-13 04:51:30.15197+00
(1 row)

mytest=> select * from pg_stat_wal_receiver;
-[ RECORD 1 ]---------+-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
pid                   | 1804
status                | streaming
receive_start_lsn     | 0/74000000
receive_start_tli     | 1
written_lsn           | 0/8818D0F8
flushed_lsn           | 0/8818D0F8
received_tli          | 1
last_msg_send_time    | 2021-11-13 05:06:19.940066+00
last_msg_receipt_time | 2021-11-13 05:06:19.940536+00
latest_end_lsn        | 0/8818D0F8
latest_end_time       | 2021-11-13 05:06:19.940066+00
slot_name             | 
sender_host           | 172.17.4.21
sender_port           | 5432
conninfo              | user=rdsrepladmin password=******** channel_binding=prefer dbname=replication host=172.17.4.21 port=5432 fallback_application_name=walreceiver sslmode=prefer sslcompression=0 ssl_min_protocol_version=TLSv1.2 gssencmode=prefer krbsrvname=whatever target_session_attrs=any

mytest=> select pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn(), pg_last_xact_replay_timestamp();
 pg_last_wal_receive_lsn | pg_last_wal_replay_lsn | pg_last_xact_replay_timestamp 
-------------------------+------------------------+-------------------------------
 0/881BDFC0              | 0/881BDFC0             | 2021-11-13 05:06:32.964386+00
(1 row)

*/


--- Testing again with:
---    hot_standby_feedback=0 & max_standby_streaming_delay=-1 on primary/first replica
---    hot_standby_feedback=1 & max_standby_streaming_delay=-1 on second replica

-- Primary:         postgres-instance1.cnxwg0faljnj.us-east-1.rds.amazonaws.com
-- First Replica:   postgres-instance-rr.cnxwg0faljnj.us-east-1.rds.amazonaws.com
-- Second Replca:   postgres-instance-rr2.cnxwg0faljnj.us-east-1.rds.amazonaws.com

-- running on Primary: (1st session)
select name,setting from pg_settings
where name in ('max_standby_streaming_delay','hot_standby_feedback','max_standby_streaming_delay');
-- generate workload so LSN increased continiously at source 
do
$$
declare 
  i bigint;
begin
  for i in 1..100000000 loop
     update t1 set id = i;
     commit;
  end loop;
end;
$$
;

/*

mytest=> select name,setting from pg_settings
mytest-> where name in ('max_standby_streaming_delay','hot_standby_feedback','max_standby_streaming_delay');
            name             | setting 
-----------------------------+---------
 hot_standby_feedback        | off
 max_standby_streaming_delay | -1
(2 rows)

mytest=> -- generate workload so LSN increased continiously at source 
mytest=> do
mytest-> $$
mytest$> declare 
mytest$>   i bigint;
mytest$> begin
mytest$>   for i in 1..100000000 loop
mytest$>      update t1 set id = i;
mytest$>      commit;
mytest$>   end loop;
mytest$> end;
mytest$> $$
mytest-> ;

*/


-- running on First Replica: (1st session)
select name,setting from pg_settings
where name in ('max_standby_streaming_delay','hot_standby_feedback','max_standby_streaming_delay');

begin transaction;
set transaction isolation level repeatable read;
select clock_timestamp(),id from t1;
-- wait few seconds
select clock_timestamp(),id from t1;
-- wait few seconds
select clock_timestamp(),id from t1;


/*

mytest=> 
mytest=> select name,setting from pg_settings
mytest-> where name in ('max_standby_streaming_delay','hot_standby_feedback','max_standby_streaming_delay');
            name             | setting 
-----------------------------+---------
 hot_standby_feedback        | off
 max_standby_streaming_delay | -1
(2 rows)

mytest=> 
mytest=> begin transaction;
BEGIN
mytest=*> set transaction isolation level repeatable read;
SET
mytest=*> select clock_timestamp(),id from t1;
        clock_timestamp        |  id   
-------------------------------+-------
 2021-11-13 05:18:42.062482+00 | 10270
(1 row)

mytest=*> select clock_timestamp(),id from t1;
        clock_timestamp        |  id   
-------------------------------+-------
 2021-11-13 05:24:04.898627+00 | 10270
(1 row)

mytest=*> commit;
COMMIT
*/



-- running on Second Replca: (1st session)
select name,setting from pg_settings
where name in ('max_standby_streaming_delay','hot_standby_feedback','max_standby_streaming_delay');


begin transaction;
set transaction isolation level repeatable read;
select clock_timestamp(),id from t1;
-- wait few seconds
select clock_timestamp(),id from t1;
-- wait few seconds
select clock_timestamp(),id from t1;

/*

mytest=> select name,setting from pg_settings
mytest-> where name in ('max_standby_streaming_delay','hot_standby_feedback','max_standby_streaming_delay');
            name             | setting 
-----------------------------+---------
 hot_standby_feedback        | on
 max_standby_streaming_delay | -1
(2 rows)

mytest=> 
mytest=> begin transaction;
BEGIN
mytest=*> set transaction isolation level repeatable read;
SET
mytest=*> select clock_timestamp(),id from t1;
        clock_timestamp        |  id   
-------------------------------+-------
 2021-11-13 05:19:07.600522+00 | 20716
(1 row)

mytest=*> 
mytest=*> select clock_timestamp(),id from t1;
        clock_timestamp        |  id   
-------------------------------+-------
 2021-11-13 05:24:07.770528+00 | 20716
(1 row)

mytest=*> commit;
COMMIT



*/



-- running on Primary: (2nd session)
select * from pg_stat_replication;

/*

mytest=> select * from pg_stat_replication;
-[ RECORD 1 ]----+------------------------------
pid              | 8318
usesysid         | 16396
usename          | rdsrepladmin
application_name | walreceiver
client_addr      | 172.17.4.208
client_hostname  | 
client_port      | 53678
backend_start    | 2021-11-13 02:51:35.162109+00
backend_xmin     | 
state            | streaming
sent_lsn         | 0/941A4FB8
write_lsn        | 0/941A4F48
flush_lsn        | 0/941A4F48
replay_lsn       | 0/9014E3E0
write_lag        | 00:00:00.000223
flush_lag        | 00:00:00.000809
replay_lag       | 00:01:26.076765
sync_priority    | 0
sync_state       | async
reply_time       | 2021-11-13 05:20:12.098703+00
-[ RECORD 2 ]----+------------------------------
pid              | 19766
usesysid         | 16396
usename          | rdsrepladmin
application_name | walreceiver
client_addr      | 172.17.4.197
client_hostname  | 
client_port      | 39216
backend_start    | 2021-11-13 04:41:02.6988+00
backend_xmin     | 2432572
state            | streaming
sent_lsn         | 0/941A4FB8
write_lsn        | 0/941A4F48
flush_lsn        | 0/941A4F48
replay_lsn       | 0/941A4F48
write_lag        | 00:00:00.009252
flush_lag        | 00:00:00.009257
replay_lag       | 00:00:00.009289
sync_priority    | 0
sync_state       | async
reply_time       | 2021-11-13 05:20:12.099+00

mytest=> select * from pg_replication_slots;
(0 rows)


mytest=> select * from pg_stat_replication;
-[ RECORD 1 ]----+------------------------------
pid              | 8318
usesysid         | 16396
usename          | rdsrepladmin
application_name | walreceiver
client_addr      | 172.17.4.208
client_hostname  | 
client_port      | 53678
backend_start    | 2021-11-13 02:51:35.162109+00
backend_xmin     | 
state            | streaming
sent_lsn         | 0/948E8438
write_lsn        | 0/948E8438
flush_lsn        | 0/948E8438
replay_lsn       | 0/9014E3E0
write_lag        | 00:00:00.000223
flush_lag        | 00:00:00.000809
replay_lag       | 00:05:25.417925
sync_priority    | 0
sync_state       | async
reply_time       | 2021-11-13 05:24:11.448423+00
-[ RECORD 2 ]----+------------------------------
pid              | 19766
usesysid         | 16396
usename          | rdsrepladmin
application_name | walreceiver
client_addr      | 172.17.4.197
client_hostname  | 
client_port      | 39216
backend_start    | 2021-11-13 04:41:02.6988+00
backend_xmin     | 2432572
state            | streaming
sent_lsn         | 0/948E8438
write_lsn        | 0/948E8438
flush_lsn        | 0/948E8438
replay_lsn       | 0/948E8438
write_lag        | 00:00:00.000206
flush_lag        | 00:00:00.000849
replay_lag       | 00:00:00.00089
sync_priority    | 0
sync_state       | async
reply_time       | 2021-11-13 05:24:11.448437+00

-- after commit in first replica


mytest=> select * from pg_stat_replication;
-[ RECORD 1 ]----+------------------------------
pid              | 8318
usesysid         | 16396
usename          | rdsrepladmin
application_name | walreceiver
client_addr      | 172.17.4.208
client_hostname  | 
client_port      | 53678
backend_start    | 2021-11-13 02:51:35.162109+00
backend_xmin     | 
state            | streaming
sent_lsn         | 0/981CA0F8
write_lsn        | 0/981CA0F8
flush_lsn        | 0/981CA0F8
replay_lsn       | 0/981CA0F8
write_lag        | 00:00:00.000244
flush_lag        | 00:00:00.000874
replay_lag       | 00:00:00.000917
sync_priority    | 0
sync_state       | async
reply_time       | 2021-11-13 05:25:40.495585+00
-[ RECORD 2 ]----+------------------------------
pid              | 19766
usesysid         | 16396
usename          | rdsrepladmin
application_name | walreceiver
client_addr      | 172.17.4.197
client_hostname  | 
client_port      | 39216
backend_start    | 2021-11-13 04:41:02.6988+00
backend_xmin     | 2544403
state            | streaming
sent_lsn         | 0/981CA0F8
write_lsn        | 0/981CA0F8
flush_lsn        | 0/981CA0F8
replay_lsn       | 0/981CA0F8
write_lag        | 00:00:00.000194
flush_lag        | 00:00:00.000798
replay_lag       | 00:00:00.000801
sync_priority    | 0
sync_state       | async
reply_time       | 2021-11-13 05:25:40.495098+00



*/

-- running on First Replica: (2nd session)
\x auto
select * from pg_stat_wal_receiver;
select pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn(), pg_last_xact_replay_timestamp();

/*

mytest=> select * from pg_stat_wal_receiver;
-[ RECORD 1 ]---------+-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
pid                   | 10929
status                | streaming
receive_start_lsn     | 0/18000000
receive_start_tli     | 1
written_lsn           | 0/942F87C8
flushed_lsn           | 0/942F8758
received_tli          | 1
last_msg_send_time    | 2021-11-13 05:20:47.870413+00
last_msg_receipt_time | 2021-11-13 05:20:47.871914+00
latest_end_lsn        | 0/942F87C8
latest_end_time       | 2021-11-13 05:20:47.870413+00
slot_name             | 
sender_host           | 172.17.4.21
sender_port           | 5432
conninfo              | user=rdsrepladmin password=******** channel_binding=prefer dbname=replication host=172.17.4.21 port=5432 fallback_application_name=walreceiver sslmode=prefer sslcompression=0 ssl_min_protocol_version=TLSv1.2 gssencmode=prefer krbsrvname=whatever target_session_attrs=any

mytest=> select pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn(), pg_last_xact_replay_timestamp();
 pg_last_wal_receive_lsn | pg_last_wal_replay_lsn | pg_last_xact_replay_timestamp 
-------------------------+------------------------+-------------------------------
 0/9430C6F8              | 0/9014E3E0             | 2021-11-13 05:18:46.025279+00
(1 row)


mytest=> select * from pg_stat_wal_receiver;
-[ RECORD 1 ]---------+-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
pid                   | 10929
status                | streaming
receive_start_lsn     | 0/18000000
receive_start_tli     | 1
written_lsn           | 0/980470E0
flushed_lsn           | 0/980470E0
received_tli          | 1
last_msg_send_time    | 2021-11-13 05:24:44.211597+00
last_msg_receipt_time | 2021-11-13 05:24:44.214101+00
latest_end_lsn        | 0/980470E0
latest_end_time       | 2021-11-13 05:24:44.211597+00
slot_name             | 
sender_host           | 172.17.4.21
sender_port           | 5432
conninfo              | user=rdsrepladmin password=******** channel_binding=prefer dbname=replication host=172.17.4.21 port=5432 fallback_application_name=walreceiver sslmode=prefer sslcompression=0 ssl_min_protocol_version=TLSv1.2 gssencmode=prefer krbsrvname=whatever target_session_attrs=any

mytest=> select pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn(), pg_last_xact_replay_timestamp();
 pg_last_wal_receive_lsn | pg_last_wal_replay_lsn | pg_last_xact_replay_timestamp 
-------------------------+------------------------+-------------------------------
 0/98051908              | 0/9014E3E0             | 2021-11-13 05:18:46.025279+00
(1 row)

-- after commit in first replica

mytest=> select * from pg_stat_wal_receiver;
-[ RECORD 1 ]---------+-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
pid                   | 10929
status                | streaming
receive_start_lsn     | 0/18000000
receive_start_tli     | 1
written_lsn           | 0/983D8F98
flushed_lsn           | 0/983D8F98
received_tli          | 1
last_msg_send_time    | 2021-11-13 05:26:21.711613+00
last_msg_receipt_time | 2021-11-13 05:26:21.713251+00
latest_end_lsn        | 0/983D8F98
latest_end_time       | 2021-11-13 05:26:21.711613+00
slot_name             | 
sender_host           | 172.17.4.21
sender_port           | 5432
conninfo              | user=rdsrepladmin password=******** channel_binding=prefer dbname=replication host=172.17.4.21 port=5432 fallback_application_name=walreceiver sslmode=prefer sslcompression=0 ssl_min_protocol_version=TLSv1.2 gssencmode=prefer krbsrvname=whatever target_session_attrs=any

mytest=> select pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn(), pg_last_xact_replay_timestamp();
 pg_last_wal_receive_lsn | pg_last_wal_replay_lsn | pg_last_xact_replay_timestamp 
-------------------------+------------------------+-------------------------------
 0/983F1348              | 0/983F1348             | 2021-11-13 05:26:23.482624+00
(1 row)



*/


-- running on Second Replca: (2nd session)

\x auto
select * from pg_stat_wal_receiver;
select pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn(), pg_last_xact_replay_timestamp();

/*

mytest=> select * from pg_stat_wal_receiver;
-[ RECORD 1 ]---------+-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
pid                   | 1804
status                | streaming
receive_start_lsn     | 0/74000000
receive_start_tli     | 1
written_lsn           | 0/943D0B60
flushed_lsn           | 0/943D0AF0
received_tli          | 1
last_msg_send_time    | 2021-11-13 05:21:13.063138+00
last_msg_receipt_time | 2021-11-13 05:21:13.064017+00
latest_end_lsn        | 0/943D0B60
latest_end_time       | 2021-11-13 05:21:13.063138+00
slot_name             | 
sender_host           | 172.17.4.21
sender_port           | 5432
conninfo              | user=rdsrepladmin password=******** channel_binding=prefer dbname=replication host=172.17.4.21 port=5432 fallback_application_name=walreceiver sslmode=prefer sslcompression=0 ssl_min_protocol_version=TLSv1.2 gssencmode=prefer krbsrvname=whatever target_session_attrs=any

mytest=> select pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn(), pg_last_xact_replay_timestamp();
 pg_last_wal_receive_lsn | pg_last_wal_replay_lsn | pg_last_xact_replay_timestamp 
-------------------------+------------------------+-------------------------------
 0/943E94C0              | 0/943E94C0             | 2021-11-13 05:21:15.879503+00
(1 row)

mytest=> select * from pg_stat_wal_receiver;
-[ RECORD 1 ]---------+-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
pid                   | 1804
status                | streaming
receive_start_lsn     | 0/74000000
receive_start_tli     | 1
written_lsn           | 0/980CC530
flushed_lsn           | 0/980CC4C0
received_tli          | 1
last_msg_send_time    | 2021-11-13 05:25:07.047399+00
last_msg_receipt_time | 2021-11-13 05:25:07.048689+00
latest_end_lsn        | 0/980CC530
latest_end_time       | 2021-11-13 05:25:07.047399+00
slot_name             | 
sender_host           | 172.17.4.21
sender_port           | 5432
conninfo              | user=rdsrepladmin password=******** channel_binding=prefer dbname=replication host=172.17.4.21 port=5432 fallback_application_name=walreceiver sslmode=prefer sslcompression=0 ssl_min_protocol_version=TLSv1.2 gssencmode=prefer krbsrvname=whatever target_session_attrs=any

mytest=> select pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn(), pg_last_xact_replay_timestamp();
 pg_last_wal_receive_lsn | pg_last_wal_replay_lsn | pg_last_xact_replay_timestamp 
-------------------------+------------------------+-------------------------------
 0/980D4E30              | 0/980D4E30             | 2021-11-13 05:25:08.518163+00
(1 row)

-- after commit in first replica

mytest=> select * from pg_stat_wal_receiver;
-[ RECORD 1 ]---------+-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
pid                   | 1804
status                | streaming
receive_start_lsn     | 0/74000000
receive_start_tli     | 1
written_lsn           | 0/98526CC0
flushed_lsn           | 0/98526BD0
received_tli          | 1
last_msg_send_time    | 2021-11-13 05:26:46.955802+00
last_msg_receipt_time | 2021-11-13 05:26:46.957227+00
latest_end_lsn        | 0/98526CC0
latest_end_time       | 2021-11-13 05:26:46.955802+00
slot_name             | 
sender_host           | 172.17.4.21
sender_port           | 5432
conninfo              | user=rdsrepladmin password=******** channel_binding=prefer dbname=replication host=172.17.4.21 port=5432 fallback_application_name=walreceiver sslmode=prefer sslcompression=0 ssl_min_protocol_version=TLSv1.2 gssencmode=prefer krbsrvname=whatever target_session_attrs=any

mytest=> select pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn(), pg_last_xact_replay_timestamp();
 pg_last_wal_receive_lsn | pg_last_wal_replay_lsn | pg_last_xact_replay_timestamp 
-------------------------+------------------------+-------------------------------
 0/9853A100              | 0/9853A100             | 2021-11-13 05:26:48.568767+00
(1 row)



*/

