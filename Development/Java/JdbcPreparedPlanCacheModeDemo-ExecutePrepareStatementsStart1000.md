### Prepare Statements Starts with 1000
```java
PreparedStatement ps = conn.prepareStatement("SELECT * FROM t WHERE id = ?");

ps.setInt(1, 1000);
ps.executeQuery().close();
ps.setInt(1, 2);
ps.executeQuery().close();
ps.setInt(1, 3);
ps.executeQuery().close();
ps.setInt(1, 4);
ps.executeQuery().close();
ps.setInt(1, 5);
ps.executeQuery().close();
ps.setInt(1, 6);
ps.executeQuery().close();
ps.setInt(1, 1000);
ps.executeQuery().close();
ps.setInt(1, 7);
ps.executeQuery().close();
ps.setInt(1, 1000);
ps.executeQuery().close();     
```

#### Result

| Config | `1000` | `2` | `3` | `4` | `5` | `6` | `1000` | `7` | `1000`|
| :-- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
|10.PrepareThreshold5CacheModeAuto|SEQ|IS|IS|IS|IS|IS|SEQ|IS|SEQ|
|11.PrepareThreshold5CacheModeForceCustom|SEQ|IS|IS|IS|IS|IS|SEQ|IS|SEQ|
|12.PrepareThreshold5CacheModeForceGeneric|IS|IS|IS|IS|IS|IS|IS|IS|IS|
|13.PrepareThreshold10CacheModeAuto|SEQ|IS|IS|IS|IS|IS|SEQ|IS|SEQ|
|14.PrepareThreshold10CacheModeForceCustom|SEQ|IS|IS|IS|IS|IS|SEQ|IS|SEQ|
|15.PrepareThreshold10CacheModeForceGeneric|IS|IS|IS|IS|IS|IS|IS|IS|IS|
|16.PrepareThreshold1CacheModeAuto|SEQ|IS|IS|IS|IS|IS|IS|IS|IS|
|17.PrepareThreshold1CacheModeForceCustom|SEQ|IS|IS|IS|IS|IS|SEQ|IS|SEQ|
|18.PrepareThreshold1CacheModeForceGeneric|IS|IS|IS|IS|IS|IS|IS|IS|IS|

- BIS: Bitmap Index Scan
- IS: Index Scan
- SEQ: Seq Scan

### Test 10: PrepareThreshold5CacheModeAuto + PreparedStatementsStart1000

#### Sample Code
```java
 props.setProperty("ApplicationName", "JDBCConnection: PrepareThreshold5CacheModeAuto");
props.setProperty("options", "-c plan_cache_mode=auto -c log_statement=all -c auto_explain.log_analyze=1 -c auto_explain.log_min_duration=0");
props.setProperty("prepareThreshold", "5");

```

#### Output
```sql
2023-08-12T05:46:30 2023-08-12 05:46:30 UTC:121.7.242.90(53756):postgres@mytest:[2018]:LOG:  execute <unnamed>: SET extra_float_digits = 3
2023-08-12T05:46:31 2023-08-12 05:46:31 UTC:121.7.242.90(53756):postgres@mytest:[2018]:LOG:  execute <unnamed>: SET application_name = 'JDBCConnection: PrepareThreshold5CacheModeAuto'
2023-08-12T05:46:31 2023-08-12 05:46:31 UTC:121.7.242.90(53756):postgres@mytest:[2018]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:31 2023-08-12 05:46:31 UTC:121.7.242.90(53756):postgres@mytest:[2018]:DETAIL:  parameters: $1 = '1000'
2023-08-12T05:46:31 2023-08-12 05:46:31 UTC:121.7.242.90(53756):postgres@mytest:[2018]:LOG:  duration: 482.362 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.014..0.191 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
2023-08-12T05:46:32 2023-08-12 05:46:32 UTC:121.7.242.90(53756):postgres@mytest:[2018]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:32 2023-08-12 05:46:32 UTC:121.7.242.90(53756):postgres@mytest:[2018]:DETAIL:  parameters: $1 = '2'
2023-08-12T05:46:32 2023-08-12 05:46:32 UTC:121.7.242.90(53756):postgres@mytest:[2018]:LOG:  duration: 0.029 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.023..0.025 rows=1 loops=1)
	  Index Cond: (id = 2)
2023-08-12T05:46:32 2023-08-12 05:46:32 UTC:121.7.242.90(53756):postgres@mytest:[2018]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:32 2023-08-12 05:46:32 UTC:121.7.242.90(53756):postgres@mytest:[2018]:DETAIL:  parameters: $1 = '3'
2023-08-12T05:46:32 2023-08-12 05:46:32 UTC:121.7.242.90(53756):postgres@mytest:[2018]:LOG:  duration: 0.019 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.013..0.015 rows=1 loops=1)
	  Index Cond: (id = 3)
2023-08-12T05:46:32 2023-08-12 05:46:32 UTC:121.7.242.90(53756):postgres@mytest:[2018]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:32 2023-08-12 05:46:32 UTC:121.7.242.90(53756):postgres@mytest:[2018]:DETAIL:  parameters: $1 = '4'
2023-08-12T05:46:32 2023-08-12 05:46:32 UTC:121.7.242.90(53756):postgres@mytest:[2018]:LOG:  duration: 0.020 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.014..0.016 rows=1 loops=1)
	  Index Cond: (id = 4)
2023-08-12T05:46:32 2023-08-12 05:46:32 UTC:121.7.242.90(53756):postgres@mytest:[2018]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:32 2023-08-12 05:46:32 UTC:121.7.242.90(53756):postgres@mytest:[2018]:DETAIL:  parameters: $1 = '5'
2023-08-12T05:46:32 2023-08-12 05:46:32 UTC:121.7.242.90(53756):postgres@mytest:[2018]:LOG:  duration: 0.019 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.014..0.016 rows=1 loops=1)
	  Index Cond: (id = 5)
2023-08-12T05:46:33 2023-08-12 05:46:33 UTC:121.7.242.90(53756):postgres@mytest:[2018]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:33 2023-08-12 05:46:33 UTC:121.7.242.90(53756):postgres@mytest:[2018]:DETAIL:  parameters: $1 = '6'
2023-08-12T05:46:33 2023-08-12 05:46:33 UTC:121.7.242.90(53756):postgres@mytest:[2018]:LOG:  duration: 0.026 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.020..0.022 rows=1 loops=1)
	  Index Cond: (id = 6)
2023-08-12T05:46:33 2023-08-12 05:46:33 UTC:121.7.242.90(53756):postgres@mytest:[2018]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:33 2023-08-12 05:46:33 UTC:121.7.242.90(53756):postgres@mytest:[2018]:DETAIL:  parameters: $1 = '1000'
2023-08-12T05:46:33 2023-08-12 05:46:33 UTC:121.7.242.90(53756):postgres@mytest:[2018]:LOG:  duration: 0.540 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.015..0.186 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
2023-08-12T05:46:33 2023-08-12 05:46:33 UTC:121.7.242.90(53756):postgres@mytest:[2018]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:33 2023-08-12 05:46:33 UTC:121.7.242.90(53756):postgres@mytest:[2018]:DETAIL:  parameters: $1 = '7'
2023-08-12T05:46:33 2023-08-12 05:46:33 UTC:121.7.242.90(53756):postgres@mytest:[2018]:LOG:  duration: 0.020 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.014..0.016 rows=1 loops=1)
	  Index Cond: (id = 7)
2023-08-12T05:46:33 2023-08-12 05:46:33 UTC:121.7.242.90(53756):postgres@mytest:[2018]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:33 2023-08-12 05:46:33 UTC:121.7.242.90(53756):postgres@mytest:[2018]:DETAIL:  parameters: $1 = '1000'
2023-08-12T05:46:33 2023-08-12 05:46:33 UTC:121.7.242.90(53756):postgres@mytest:[2018]:LOG:  duration: 0.540 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.014..0.169 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10

```


### Test 11: PrepareThreshold5CacheModeForceCustom + PreparedStatementsStart1000

#### Sample Code
```java
props.setProperty("ApplicationName", "JDBCConnection: PrepareThreshold5CacheModeForceCustom");
props.setProperty("options", "-c plan_cache_mode=force_custom_plan -c log_statement=all -c auto_explain.log_analyze=1 -c auto_explain.log_min_duration=0");
props.setProperty("prepareThreshold", "5");
```

#### Output
```sql
2023-08-12T05:46:35 2023-08-12 05:46:35 UTC:121.7.242.90(53762):postgres@mytest:[2020]:LOG:  execute <unnamed>: SET extra_float_digits = 3
2023-08-12T05:46:36 2023-08-12 05:46:36 UTC:121.7.242.90(53762):postgres@mytest:[2020]:LOG:  execute <unnamed>: SET application_name = 'JDBCConnection: PrepareThreshold5CacheModeForceCustom'
2023-08-12T05:46:36 2023-08-12 05:46:36 UTC:121.7.242.90(53762):postgres@mytest:[2020]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:36 2023-08-12 05:46:36 UTC:121.7.242.90(53762):postgres@mytest:[2020]:DETAIL:  parameters: $1 = '1000'
2023-08-12T05:46:36 2023-08-12 05:46:36 UTC:121.7.242.90(53762):postgres@mytest:[2020]:LOG:  duration: 491.288 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.014..0.307 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
2023-08-12T05:46:37 2023-08-12 05:46:37 UTC:121.7.242.90(53762):postgres@mytest:[2020]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:37 2023-08-12 05:46:37 UTC:121.7.242.90(53762):postgres@mytest:[2020]:DETAIL:  parameters: $1 = '2'
2023-08-12T05:46:37 2023-08-12 05:46:37 UTC:121.7.242.90(53762):postgres@mytest:[2020]:LOG:  duration: 0.028 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.023..0.024 rows=1 loops=1)
	  Index Cond: (id = 2)
2023-08-12T05:46:37 2023-08-12 05:46:37 UTC:121.7.242.90(53762):postgres@mytest:[2020]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:37 2023-08-12 05:46:37 UTC:121.7.242.90(53762):postgres@mytest:[2020]:DETAIL:  parameters: $1 = '3'
2023-08-12T05:46:37 2023-08-12 05:46:37 UTC:121.7.242.90(53762):postgres@mytest:[2020]:LOG:  duration: 0.019 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.014..0.016 rows=1 loops=1)
	  Index Cond: (id = 3)
2023-08-12T05:46:38 2023-08-12 05:46:38 UTC:121.7.242.90(53762):postgres@mytest:[2020]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:38 2023-08-12 05:46:38 UTC:121.7.242.90(53762):postgres@mytest:[2020]:DETAIL:  parameters: $1 = '4'
2023-08-12T05:46:38 2023-08-12 05:46:38 UTC:121.7.242.90(53762):postgres@mytest:[2020]:LOG:  duration: 0.020 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.013..0.015 rows=1 loops=1)
	  Index Cond: (id = 4)
2023-08-12T05:46:38 2023-08-12 05:46:38 UTC:121.7.242.90(53762):postgres@mytest:[2020]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:38 2023-08-12 05:46:38 UTC:121.7.242.90(53762):postgres@mytest:[2020]:DETAIL:  parameters: $1 = '5'
2023-08-12T05:46:38 2023-08-12 05:46:38 UTC:121.7.242.90(53762):postgres@mytest:[2020]:LOG:  duration: 0.021 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.016..0.017 rows=1 loops=1)
	  Index Cond: (id = 5)
2023-08-12T05:46:38 2023-08-12 05:46:38 UTC:121.7.242.90(53762):postgres@mytest:[2020]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:38 2023-08-12 05:46:38 UTC:121.7.242.90(53762):postgres@mytest:[2020]:DETAIL:  parameters: $1 = '6'
2023-08-12T05:46:38 2023-08-12 05:46:38 UTC:121.7.242.90(53762):postgres@mytest:[2020]:LOG:  duration: 0.022 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.017..0.019 rows=1 loops=1)
	  Index Cond: (id = 6)
2023-08-12T05:46:38 2023-08-12 05:46:38 UTC:121.7.242.90(53762):postgres@mytest:[2020]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:38 2023-08-12 05:46:38 UTC:121.7.242.90(53762):postgres@mytest:[2020]:DETAIL:  parameters: $1 = '1000'
2023-08-12T05:46:38 2023-08-12 05:46:38 UTC:121.7.242.90(53762):postgres@mytest:[2020]:LOG:  duration: 0.535 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.014..0.170 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
2023-08-12T05:46:39 2023-08-12 05:46:39 UTC:121.7.242.90(53762):postgres@mytest:[2020]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:39 2023-08-12 05:46:39 UTC:121.7.242.90(53762):postgres@mytest:[2020]:DETAIL:  parameters: $1 = '7'
2023-08-12T05:46:39 2023-08-12 05:46:39 UTC:121.7.242.90(53762):postgres@mytest:[2020]:LOG:  duration: 0.025 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.016..0.019 rows=1 loops=1)
	  Index Cond: (id = 7)
2023-08-12T05:46:39 2023-08-12 05:46:39 UTC:121.7.242.90(53762):postgres@mytest:[2020]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:39 2023-08-12 05:46:39 UTC:121.7.242.90(53762):postgres@mytest:[2020]:DETAIL:  parameters: $1 = '1000'
2023-08-12T05:46:39 2023-08-12 05:46:39 UTC:121.7.242.90(53762):postgres@mytest:[2020]:LOG:  duration: 0.561 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.014..0.184 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
```


### Test 12: PrepareThreshold5CacheModeForceGeneric + PreparedStatementsStart1000

#### Sample Code
```java
props.setProperty("ApplicationName", "JDBCConnection: PrepareThreshold5CacheModeForceGeneric");
props.setProperty("options", "-c plan_cache_mode=force_generic_plan -c log_statement=all -c auto_explain.log_analyze=1 -c auto_explain.log_min_duration=0");
props.setProperty("prepareThreshold", "5");
```

#### Output
```sql
2023-08-12T05:46:41 2023-08-12 05:46:41 UTC:121.7.242.90(53768):postgres@mytest:[2025]:LOG:  execute <unnamed>: SET extra_float_digits = 3
2023-08-12T05:46:41 2023-08-12 05:46:41 UTC:121.7.242.90(53768):postgres@mytest:[2025]:LOG:  execute <unnamed>: SET application_name = 'JDBCConnection: PrepareThreshold5CacheModeForceGeneric'
2023-08-12T05:46:41 2023-08-12 05:46:41 UTC:121.7.242.90(53768):postgres@mytest:[2025]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:41 2023-08-12 05:46:41 UTC:121.7.242.90(53768):postgres@mytest:[2025]:DETAIL:  parameters: $1 = '1000'
2023-08-12T05:46:42 2023-08-12 05:46:42 UTC:121.7.242.90(53768):postgres@mytest:[2025]:LOG:  duration: 494.852 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.025..0.234 rows=990 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:46:42 2023-08-12 05:46:42 UTC:121.7.242.90(53768):postgres@mytest:[2025]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:42 2023-08-12 05:46:42 UTC:121.7.242.90(53768):postgres@mytest:[2025]:DETAIL:  parameters: $1 = '2'
2023-08-12T05:46:42 2023-08-12 05:46:42 UTC:121.7.242.90(53768):postgres@mytest:[2025]:LOG:  duration: 0.024 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.018..0.020 rows=1 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:46:43 2023-08-12 05:46:43 UTC:121.7.242.90(53768):postgres@mytest:[2025]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:43 2023-08-12 05:46:43 UTC:121.7.242.90(53768):postgres@mytest:[2025]:DETAIL:  parameters: $1 = '3'
2023-08-12T05:46:43 2023-08-12 05:46:43 UTC:121.7.242.90(53768):postgres@mytest:[2025]:LOG:  duration: 0.019 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.014..0.016 rows=1 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:46:43 2023-08-12 05:46:43 UTC:121.7.242.90(53768):postgres@mytest:[2025]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:43 2023-08-12 05:46:43 UTC:121.7.242.90(53768):postgres@mytest:[2025]:DETAIL:  parameters: $1 = '4'
2023-08-12T05:46:43 2023-08-12 05:46:43 UTC:121.7.242.90(53768):postgres@mytest:[2025]:LOG:  duration: 0.023 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.017..0.019 rows=1 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:46:43 2023-08-12 05:46:43 UTC:121.7.242.90(53768):postgres@mytest:[2025]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:43 2023-08-12 05:46:43 UTC:121.7.242.90(53768):postgres@mytest:[2025]:DETAIL:  parameters: $1 = '5'
2023-08-12T05:46:43 2023-08-12 05:46:43 UTC:121.7.242.90(53768):postgres@mytest:[2025]:LOG:  duration: 0.026 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.017..0.018 rows=1 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:46:43 2023-08-12 05:46:43 UTC:121.7.242.90(53768):postgres@mytest:[2025]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:43 2023-08-12 05:46:43 UTC:121.7.242.90(53768):postgres@mytest:[2025]:DETAIL:  parameters: $1 = '6'
2023-08-12T05:46:43 2023-08-12 05:46:43 UTC:121.7.242.90(53768):postgres@mytest:[2025]:LOG:  duration: 0.026 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.020..0.022 rows=1 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:46:44 2023-08-12 05:46:44 UTC:121.7.242.90(53768):postgres@mytest:[2025]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:44 2023-08-12 05:46:44 UTC:121.7.242.90(53768):postgres@mytest:[2025]:DETAIL:  parameters: $1 = '1000'
2023-08-12T05:46:44 2023-08-12 05:46:44 UTC:121.7.242.90(53768):postgres@mytest:[2025]:LOG:  duration: 0.644 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.034..0.252 rows=990 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:46:44 2023-08-12 05:46:44 UTC:121.7.242.90(53768):postgres@mytest:[2025]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:44 2023-08-12 05:46:44 UTC:121.7.242.90(53768):postgres@mytest:[2025]:DETAIL:  parameters: $1 = '7'
2023-08-12T05:46:44 2023-08-12 05:46:44 UTC:121.7.242.90(53768):postgres@mytest:[2025]:LOG:  duration: 0.042 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.036..0.038 rows=1 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:46:44 2023-08-12 05:46:44 UTC:121.7.242.90(53768):postgres@mytest:[2025]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:44 2023-08-12 05:46:44 UTC:121.7.242.90(53768):postgres@mytest:[2025]:DETAIL:  parameters: $1 = '1000'
2023-08-12T05:46:44 2023-08-12 05:46:44 UTC:121.7.242.90(53768):postgres@mytest:[2025]:LOG:  duration: 0.582 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.026..0.174 rows=990 loops=1)
	  Index Cond: (id = $1)
```



### Test 13: PrepareThreshold10CacheModeAuto + PreparedStatementsStart1000

#### Sample Code
```java
props.setProperty("ApplicationName", "JDBCConnection: PrepareThreshold10CacheModeAuto");
props.setProperty("options", "-c plan_cache_mode=auto -c log_statement=all -c auto_explain.log_analyze=1 -c auto_explain.log_min_duration=0");
props.setProperty("prepareThreshold", "10");
```

#### Output
```sql
2023-08-12T05:46:46 2023-08-12 05:46:46 UTC:121.7.242.90(53775):postgres@mytest:[2032]:LOG:  execute <unnamed>: SET extra_float_digits = 3
2023-08-12T05:46:46 2023-08-12 05:46:46 UTC:121.7.242.90(53775):postgres@mytest:[2032]:LOG:  execute <unnamed>: SET application_name = 'JDBCConnection: PrepareThreshold10CacheModeAuto'
2023-08-12T05:46:47 2023-08-12 05:46:47 UTC:121.7.242.90(53775):postgres@mytest:[2032]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:47 2023-08-12 05:46:47 UTC:121.7.242.90(53775):postgres@mytest:[2032]:DETAIL:  parameters: $1 = '1000'
2023-08-12T05:46:47 2023-08-12 05:46:47 UTC:121.7.242.90(53775):postgres@mytest:[2032]:LOG:  duration: 476.189 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.012..0.165 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
2023-08-12T05:46:48 2023-08-12 05:46:48 UTC:121.7.242.90(53775):postgres@mytest:[2032]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:48 2023-08-12 05:46:48 UTC:121.7.242.90(53775):postgres@mytest:[2032]:DETAIL:  parameters: $1 = '2'
2023-08-12T05:46:48 2023-08-12 05:46:48 UTC:121.7.242.90(53775):postgres@mytest:[2032]:LOG:  duration: 0.028 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.021..0.024 rows=1 loops=1)
	  Index Cond: (id = 2)
2023-08-12T05:46:48 2023-08-12 05:46:48 UTC:121.7.242.90(53775):postgres@mytest:[2032]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:48 2023-08-12 05:46:48 UTC:121.7.242.90(53775):postgres@mytest:[2032]:DETAIL:  parameters: $1 = '3'
2023-08-12T05:46:48 2023-08-12 05:46:48 UTC:121.7.242.90(53775):postgres@mytest:[2032]:LOG:  duration: 0.021 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.015..0.017 rows=1 loops=1)
	  Index Cond: (id = 3)
2023-08-12T05:46:48 2023-08-12 05:46:48 UTC:121.7.242.90(53775):postgres@mytest:[2032]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:48 2023-08-12 05:46:48 UTC:121.7.242.90(53775):postgres@mytest:[2032]:DETAIL:  parameters: $1 = '4'
2023-08-12T05:46:48 2023-08-12 05:46:48 UTC:121.7.242.90(53775):postgres@mytest:[2032]:LOG:  duration: 0.019 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.013..0.016 rows=1 loops=1)
	  Index Cond: (id = 4)
2023-08-12T05:46:48 2023-08-12 05:46:48 UTC:121.7.242.90(53775):postgres@mytest:[2032]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:48 2023-08-12 05:46:48 UTC:121.7.242.90(53775):postgres@mytest:[2032]:DETAIL:  parameters: $1 = '5'
2023-08-12T05:46:48 2023-08-12 05:46:48 UTC:121.7.242.90(53775):postgres@mytest:[2032]:LOG:  duration: 0.020 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.015..0.016 rows=1 loops=1)
	  Index Cond: (id = 5)
2023-08-12T05:46:49 2023-08-12 05:46:49 UTC:121.7.242.90(53775):postgres@mytest:[2032]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:49 2023-08-12 05:46:49 UTC:121.7.242.90(53775):postgres@mytest:[2032]:DETAIL:  parameters: $1 = '6'
2023-08-12T05:46:49 2023-08-12 05:46:49 UTC:121.7.242.90(53775):postgres@mytest:[2032]:LOG:  duration: 0.021 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.015..0.017 rows=1 loops=1)
	  Index Cond: (id = 6)
2023-08-12T05:46:49 2023-08-12 05:46:49 UTC:121.7.242.90(53775):postgres@mytest:[2032]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:49 2023-08-12 05:46:49 UTC:121.7.242.90(53775):postgres@mytest:[2032]:DETAIL:  parameters: $1 = '1000'
2023-08-12T05:46:49 2023-08-12 05:46:49 UTC:121.7.242.90(53775):postgres@mytest:[2032]:LOG:  duration: 0.516 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.014..0.141 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
2023-08-12T05:46:49 2023-08-12 05:46:49 UTC:121.7.242.90(53775):postgres@mytest:[2032]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:49 2023-08-12 05:46:49 UTC:121.7.242.90(53775):postgres@mytest:[2032]:DETAIL:  parameters: $1 = '7'
2023-08-12T05:46:49 2023-08-12 05:46:49 UTC:121.7.242.90(53775):postgres@mytest:[2032]:LOG:  duration: 0.016 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.012..0.013 rows=1 loops=1)
	  Index Cond: (id = 7)
2023-08-12T05:46:49 2023-08-12 05:46:49 UTC:121.7.242.90(53775):postgres@mytest:[2032]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:49 2023-08-12 05:46:49 UTC:121.7.242.90(53775):postgres@mytest:[2032]:DETAIL:  parameters: $1 = '1000'
2023-08-12T05:46:49 2023-08-12 05:46:49 UTC:121.7.242.90(53775):postgres@mytest:[2032]:LOG:  duration: 0.507 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.010..0.132 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10

```



### Test 14: PrepareThreshold10CacheModeForceCustom + PreparedStatementsStart1000

#### Sample Code
```java
props.setProperty("ApplicationName", "JDBCConnection: PrepareThreshold10CacheModeForceCustom");
props.setProperty("options", "-c plan_cache_mode=force_custom_plan -c log_statement=all -c auto_explain.log_analyze=1 -c auto_explain.log_min_duration=0");
props.setProperty("prepareThreshold", "10");
```

#### Output
```sql
2023-08-12T05:46:51 2023-08-12 05:46:51 UTC:121.7.242.90(53783):postgres@mytest:[2034]:LOG:  execute <unnamed>: SET extra_float_digits = 3
2023-08-12T05:46:51 2023-08-12 05:46:51 UTC:121.7.242.90(53783):postgres@mytest:[2034]:LOG:  execute <unnamed>: SET application_name = 'JDBCConnection: PrepareThreshold10CacheModeForceCustom'
2023-08-12T05:46:52 2023-08-12 05:46:52 UTC:121.7.242.90(53783):postgres@mytest:[2034]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:52 2023-08-12 05:46:52 UTC:121.7.242.90(53783):postgres@mytest:[2034]:DETAIL:  parameters: $1 = '1000'
2023-08-12T05:46:52 2023-08-12 05:46:52 UTC:121.7.242.90(53783):postgres@mytest:[2034]:LOG:  duration: 474.768 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.017..0.175 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
2023-08-12T05:46:53 2023-08-12 05:46:53 UTC:121.7.242.90(53783):postgres@mytest:[2034]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:53 2023-08-12 05:46:53 UTC:121.7.242.90(53783):postgres@mytest:[2034]:DETAIL:  parameters: $1 = '2'
2023-08-12T05:46:53 2023-08-12 05:46:53 UTC:121.7.242.90(53783):postgres@mytest:[2034]:LOG:  duration: 0.029 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.022..0.024 rows=1 loops=1)
	  Index Cond: (id = 2)
2023-08-12T05:46:53 2023-08-12 05:46:53 UTC:121.7.242.90(53783):postgres@mytest:[2034]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:53 2023-08-12 05:46:53 UTC:121.7.242.90(53783):postgres@mytest:[2034]:DETAIL:  parameters: $1 = '3'
2023-08-12T05:46:53 2023-08-12 05:46:53 UTC:121.7.242.90(53783):postgres@mytest:[2034]:LOG:  duration: 0.019 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.013..0.015 rows=1 loops=1)
	  Index Cond: (id = 3)
2023-08-12T05:46:53 2023-08-12 05:46:53 UTC:121.7.242.90(53783):postgres@mytest:[2034]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:53 2023-08-12 05:46:53 UTC:121.7.242.90(53783):postgres@mytest:[2034]:DETAIL:  parameters: $1 = '4'
2023-08-12T05:46:53 2023-08-12 05:46:53 UTC:121.7.242.90(53783):postgres@mytest:[2034]:LOG:  duration: 0.021 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.015..0.017 rows=1 loops=1)
	  Index Cond: (id = 4)
2023-08-12T05:46:53 2023-08-12 05:46:53 UTC:121.7.242.90(53783):postgres@mytest:[2034]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:53 2023-08-12 05:46:53 UTC:121.7.242.90(53783):postgres@mytest:[2034]:DETAIL:  parameters: $1 = '5'
2023-08-12T05:46:53 2023-08-12 05:46:53 UTC:121.7.242.90(53783):postgres@mytest:[2034]:LOG:  duration: 0.047 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.041..0.042 rows=1 loops=1)
	  Index Cond: (id = 5)
2023-08-12T05:46:54 2023-08-12 05:46:54 UTC:121.7.242.90(53783):postgres@mytest:[2034]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:54 2023-08-12 05:46:54 UTC:121.7.242.90(53783):postgres@mytest:[2034]:DETAIL:  parameters: $1 = '6'
2023-08-12T05:46:54 2023-08-12 05:46:54 UTC:121.7.242.90(53783):postgres@mytest:[2034]:LOG:  duration: 0.023 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.016..0.018 rows=1 loops=1)
	  Index Cond: (id = 6)
2023-08-12T05:46:54 2023-08-12 05:46:54 UTC:121.7.242.90(53783):postgres@mytest:[2034]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:54 2023-08-12 05:46:54 UTC:121.7.242.90(53783):postgres@mytest:[2034]:DETAIL:  parameters: $1 = '1000'
2023-08-12T05:46:54 2023-08-12 05:46:54 UTC:121.7.242.90(53783):postgres@mytest:[2034]:LOG:  duration: 0.547 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.014..0.184 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
2023-08-12T05:46:54 2023-08-12 05:46:54 UTC:121.7.242.90(53783):postgres@mytest:[2034]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:54 2023-08-12 05:46:54 UTC:121.7.242.90(53783):postgres@mytest:[2034]:DETAIL:  parameters: $1 = '7'
2023-08-12T05:46:54 2023-08-12 05:46:54 UTC:121.7.242.90(53783):postgres@mytest:[2034]:LOG:  duration: 0.019 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.013..0.015 rows=1 loops=1)
	  Index Cond: (id = 7)
2023-08-12T05:46:54 2023-08-12 05:46:54 UTC:121.7.242.90(53783):postgres@mytest:[2034]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:54 2023-08-12 05:46:54 UTC:121.7.242.90(53783):postgres@mytest:[2034]:DETAIL:  parameters: $1 = '1000'
2023-08-12T05:46:54 2023-08-12 05:46:54 UTC:121.7.242.90(53783):postgres@mytest:[2034]:LOG:  duration: 0.605 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.014..0.240 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
```



### Test 15: PrepareThreshold10CacheModeForceGeneric + PreparedStatementsStart1000

#### Sample Code
```java
props.setProperty("ApplicationName", "JDBCConnection: PrepareThreshold10CacheModeForceGeneric");
props.setProperty("options", "-c plan_cache_mode=force_generic_plan -c log_statement=all -c auto_explain.log_analyze=1 -c auto_explain.log_min_duration=0");
props.setProperty("prepareThreshold", "10");
```

#### Output
```sql
2023-08-12T05:46:56 2023-08-12 05:46:56 UTC:121.7.242.90(53790):postgres@mytest:[2043]:LOG:  execute <unnamed>: SET extra_float_digits = 3
2023-08-12T05:46:57 2023-08-12 05:46:57 UTC:121.7.242.90(53790):postgres@mytest:[2043]:LOG:  execute <unnamed>: SET application_name = 'JDBCConnection: PrepareThreshold10CacheModeForceGeneric'
2023-08-12T05:46:57 2023-08-12 05:46:57 UTC:121.7.242.90(53790):postgres@mytest:[2043]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:57 2023-08-12 05:46:57 UTC:121.7.242.90(53790):postgres@mytest:[2043]:DETAIL:  parameters: $1 = '1000'
2023-08-12T05:46:57 2023-08-12 05:46:57 UTC:121.7.242.90(53790):postgres@mytest:[2043]:LOG:  duration: 486.827 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.026..0.208 rows=990 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:46:58 2023-08-12 05:46:58 UTC:121.7.242.90(53790):postgres@mytest:[2043]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:58 2023-08-12 05:46:58 UTC:121.7.242.90(53790):postgres@mytest:[2043]:DETAIL:  parameters: $1 = '2'
2023-08-12T05:46:58 2023-08-12 05:46:58 UTC:121.7.242.90(53790):postgres@mytest:[2043]:LOG:  duration: 0.023 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.018..0.019 rows=1 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:46:58 2023-08-12 05:46:58 UTC:121.7.242.90(53790):postgres@mytest:[2043]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:58 2023-08-12 05:46:58 UTC:121.7.242.90(53790):postgres@mytest:[2043]:DETAIL:  parameters: $1 = '3'
2023-08-12T05:46:58 2023-08-12 05:46:58 UTC:121.7.242.90(53790):postgres@mytest:[2043]:LOG:  duration: 0.022 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.016..0.017 rows=1 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:46:58 2023-08-12 05:46:58 UTC:121.7.242.90(53790):postgres@mytest:[2043]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:58 2023-08-12 05:46:58 UTC:121.7.242.90(53790):postgres@mytest:[2043]:DETAIL:  parameters: $1 = '4'
2023-08-12T05:46:58 2023-08-12 05:46:58 UTC:121.7.242.90(53790):postgres@mytest:[2043]:LOG:  duration: 0.021 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.016..0.017 rows=1 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:46:59 2023-08-12 05:46:59 UTC:121.7.242.90(53790):postgres@mytest:[2043]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:59 2023-08-12 05:46:59 UTC:121.7.242.90(53790):postgres@mytest:[2043]:DETAIL:  parameters: $1 = '5'
2023-08-12T05:46:59 2023-08-12 05:46:59 UTC:121.7.242.90(53790):postgres@mytest:[2043]:LOG:  duration: 0.022 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.017..0.018 rows=1 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:46:59 2023-08-12 05:46:59 UTC:121.7.242.90(53790):postgres@mytest:[2043]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:59 2023-08-12 05:46:59 UTC:121.7.242.90(53790):postgres@mytest:[2043]:DETAIL:  parameters: $1 = '6'
2023-08-12T05:46:59 2023-08-12 05:46:59 UTC:121.7.242.90(53790):postgres@mytest:[2043]:LOG:  duration: 0.025 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.019..0.021 rows=1 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:46:59 2023-08-12 05:46:59 UTC:121.7.242.90(53790):postgres@mytest:[2043]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:59 2023-08-12 05:46:59 UTC:121.7.242.90(53790):postgres@mytest:[2043]:DETAIL:  parameters: $1 = '1000'
2023-08-12T05:46:59 2023-08-12 05:46:59 UTC:121.7.242.90(53790):postgres@mytest:[2043]:LOG:  duration: 0.553 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.020..0.184 rows=990 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:46:59 2023-08-12 05:46:59 UTC:121.7.242.90(53790):postgres@mytest:[2043]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:59 2023-08-12 05:46:59 UTC:121.7.242.90(53790):postgres@mytest:[2043]:DETAIL:  parameters: $1 = '7'
2023-08-12T05:46:59 2023-08-12 05:46:59 UTC:121.7.242.90(53790):postgres@mytest:[2043]:LOG:  duration: 0.022 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.016..0.018 rows=1 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:47:00 2023-08-12 05:47:00 UTC:121.7.242.90(53790):postgres@mytest:[2043]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:47:00 2023-08-12 05:47:00 UTC:121.7.242.90(53790):postgres@mytest:[2043]:DETAIL:  parameters: $1 = '1000'
2023-08-12T05:47:00 2023-08-12 05:47:00 UTC:121.7.242.90(53790):postgres@mytest:[2043]:LOG:  duration: 0.768 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.022..0.196 rows=990 loops=1)
	  Index Cond: (id = $1)
```


### Test 16: PrepareThreshold1CacheModeAuto + PreparedStatementsStart1000

#### Sample Code
```java
props.setProperty("ApplicationName", "JDBCConnection: PrepareThreshold1CacheModeAuto");
props.setProperty("options", "-c plan_cache_mode=auto -c log_statement=all -c auto_explain.log_analyze=1 -c auto_explain.log_min_duration=0");
props.setProperty("prepareThreshold", "1");
```

#### Output
```sql
2023-08-12T05:47:02 2023-08-12 05:47:02 UTC:121.7.242.90(53802):postgres@mytest:[2045]:LOG:  execute <unnamed>: SET extra_float_digits = 3
2023-08-12T05:47:02 2023-08-12 05:47:02 UTC:121.7.242.90(53802):postgres@mytest:[2045]:LOG:  execute <unnamed>: SET application_name = 'JDBCConnection: PrepareThreshold1CacheModeAuto'
2023-08-12T05:47:02 2023-08-12 05:47:02 UTC:121.7.242.90(53802):postgres@mytest:[2045]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:47:02 2023-08-12 05:47:02 UTC:121.7.242.90(53802):postgres@mytest:[2045]:DETAIL:  parameters: $1 = '1000'
2023-08-12T05:47:03 2023-08-12 05:47:03 UTC:121.7.242.90(53802):postgres@mytest:[2045]:LOG:  duration: 491.577 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.024..0.188 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
2023-08-12T05:47:03 2023-08-12 05:47:03 UTC:121.7.242.90(53802):postgres@mytest:[2045]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:47:03 2023-08-12 05:47:03 UTC:121.7.242.90(53802):postgres@mytest:[2045]:DETAIL:  parameters: $1 = '2'
2023-08-12T05:47:03 2023-08-12 05:47:03 UTC:121.7.242.90(53802):postgres@mytest:[2045]:LOG:  duration: 0.032 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.026..0.027 rows=1 loops=1)
	  Index Cond: (id = 2)
2023-08-12T05:47:03 2023-08-12 05:47:03 UTC:121.7.242.90(53802):postgres@mytest:[2045]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:47:03 2023-08-12 05:47:03 UTC:121.7.242.90(53802):postgres@mytest:[2045]:DETAIL:  parameters: $1 = '3'
2023-08-12T05:47:03 2023-08-12 05:47:03 UTC:121.7.242.90(53802):postgres@mytest:[2045]:LOG:  duration: 0.021 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.015..0.017 rows=1 loops=1)
	  Index Cond: (id = 3)
2023-08-12T05:47:04 2023-08-12 05:47:04 UTC:121.7.242.90(53802):postgres@mytest:[2045]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:47:04 2023-08-12 05:47:04 UTC:121.7.242.90(53802):postgres@mytest:[2045]:DETAIL:  parameters: $1 = '4'
2023-08-12T05:47:04 2023-08-12 05:47:04 UTC:121.7.242.90(53802):postgres@mytest:[2045]:LOG:  duration: 0.021 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.014..0.015 rows=1 loops=1)
	  Index Cond: (id = 4)
2023-08-12T05:47:04 2023-08-12 05:47:04 UTC:121.7.242.90(53802):postgres@mytest:[2045]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:47:04 2023-08-12 05:47:04 UTC:121.7.242.90(53802):postgres@mytest:[2045]:DETAIL:  parameters: $1 = '5'
2023-08-12T05:47:04 2023-08-12 05:47:04 UTC:121.7.242.90(53802):postgres@mytest:[2045]:LOG:  duration: 0.019 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.013..0.015 rows=1 loops=1)
	  Index Cond: (id = 5)
2023-08-12T05:47:04 2023-08-12 05:47:04 UTC:121.7.242.90(53802):postgres@mytest:[2045]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:47:04 2023-08-12 05:47:04 UTC:121.7.242.90(53802):postgres@mytest:[2045]:DETAIL:  parameters: $1 = '6'
2023-08-12T05:47:04 2023-08-12 05:47:04 UTC:121.7.242.90(53802):postgres@mytest:[2045]:LOG:  duration: 0.034 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.017..0.018 rows=1 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:47:04 2023-08-12 05:47:04 UTC:121.7.242.90(53802):postgres@mytest:[2045]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:47:04 2023-08-12 05:47:04 UTC:121.7.242.90(53802):postgres@mytest:[2045]:DETAIL:  parameters: $1 = '1000'
2023-08-12T05:47:04 2023-08-12 05:47:04 UTC:121.7.242.90(53802):postgres@mytest:[2045]:LOG:  duration: 0.613 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.035..0.205 rows=990 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:47:05 2023-08-12 05:47:05 UTC:121.7.242.90(53802):postgres@mytest:[2045]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:47:05 2023-08-12 05:47:05 UTC:121.7.242.90(53802):postgres@mytest:[2045]:DETAIL:  parameters: $1 = '7'
2023-08-12T05:47:05 2023-08-12 05:47:05 UTC:121.7.242.90(53802):postgres@mytest:[2045]:LOG:  duration: 0.024 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.018..0.020 rows=1 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:47:05 2023-08-12 05:47:05 UTC:121.7.242.90(53802):postgres@mytest:[2045]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:47:05 2023-08-12 05:47:05 UTC:121.7.242.90(53802):postgres@mytest:[2045]:DETAIL:  parameters: $1 = '1000'
2023-08-12T05:47:05 2023-08-12 05:47:05 UTC:121.7.242.90(53802):postgres@mytest:[2045]:LOG:  duration: 0.625 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.023..0.190 rows=990 loops=1)
	  Index Cond: (id = $1)
```

### Test 17: PrepareThreshold1CacheModeForceCustom + PreparedStatementsStart1000

#### Sample Code
```java
props.setProperty("ApplicationName", "JDBCConnection: PrepareThreshold1CacheModeForceCustom");
props.setProperty("options", "-c plan_cache_mode=force_custom_plan -c log_statement=all -c auto_explain.log_analyze=1 -c auto_explain.log_min_duration=0");
props.setProperty("prepareThreshold", "1");
```

#### Output
```sql
2023-08-12T05:47:07 2023-08-12 05:47:07 UTC:121.7.242.90(53809):postgres@mytest:[2048]:LOG:  execute <unnamed>: SET extra_float_digits = 3
2023-08-12T05:47:07 2023-08-12 05:47:07 UTC:121.7.242.90(53809):postgres@mytest:[2048]:LOG:  execute <unnamed>: SET application_name = 'JDBCConnection: PrepareThreshold1CacheModeForceCustom'
2023-08-12T05:47:07 2023-08-12 05:47:07 UTC:121.7.242.90(53809):postgres@mytest:[2048]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:47:07 2023-08-12 05:47:07 UTC:121.7.242.90(53809):postgres@mytest:[2048]:DETAIL:  parameters: $1 = '1000'
2023-08-12T05:47:08 2023-08-12 05:47:08 UTC:121.7.242.90(53809):postgres@mytest:[2048]:LOG:  duration: 475.858 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.013..0.215 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
2023-08-12T05:47:08 2023-08-12 05:47:08 UTC:121.7.242.90(53809):postgres@mytest:[2048]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:47:08 2023-08-12 05:47:08 UTC:121.7.242.90(53809):postgres@mytest:[2048]:DETAIL:  parameters: $1 = '2'
2023-08-12T05:47:08 2023-08-12 05:47:08 UTC:121.7.242.90(53809):postgres@mytest:[2048]:LOG:  duration: 0.031 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.025..0.026 rows=1 loops=1)
	  Index Cond: (id = 2)
2023-08-12T05:47:09 2023-08-12 05:47:09 UTC:121.7.242.90(53809):postgres@mytest:[2048]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:47:09 2023-08-12 05:47:09 UTC:121.7.242.90(53809):postgres@mytest:[2048]:DETAIL:  parameters: $1 = '3'
2023-08-12T05:47:09 2023-08-12 05:47:09 UTC:121.7.242.90(53809):postgres@mytest:[2048]:LOG:  duration: 0.023 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.016..0.018 rows=1 loops=1)
	  Index Cond: (id = 3)
2023-08-12T05:47:09 2023-08-12 05:47:09 UTC:121.7.242.90(53809):postgres@mytest:[2048]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:47:09 2023-08-12 05:47:09 UTC:121.7.242.90(53809):postgres@mytest:[2048]:DETAIL:  parameters: $1 = '4'
2023-08-12T05:47:09 2023-08-12 05:47:09 UTC:121.7.242.90(53809):postgres@mytest:[2048]:LOG:  duration: 0.020 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.014..0.016 rows=1 loops=1)
	  Index Cond: (id = 4)
2023-08-12T05:47:09 2023-08-12 05:47:09 UTC:121.7.242.90(53809):postgres@mytest:[2048]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:47:09 2023-08-12 05:47:09 UTC:121.7.242.90(53809):postgres@mytest:[2048]:DETAIL:  parameters: $1 = '5'
2023-08-12T05:47:09 2023-08-12 05:47:09 UTC:121.7.242.90(53809):postgres@mytest:[2048]:LOG:  duration: 0.021 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.015..0.016 rows=1 loops=1)
	  Index Cond: (id = 5)
2023-08-12T05:47:09 2023-08-12 05:47:09 UTC:121.7.242.90(53809):postgres@mytest:[2048]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:47:09 2023-08-12 05:47:09 UTC:121.7.242.90(53809):postgres@mytest:[2048]:DETAIL:  parameters: $1 = '6'
2023-08-12T05:47:09 2023-08-12 05:47:09 UTC:121.7.242.90(53809):postgres@mytest:[2048]:LOG:  duration: 0.023 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.017..0.018 rows=1 loops=1)
	  Index Cond: (id = 6)
2023-08-12T05:47:10 2023-08-12 05:47:10 UTC:121.7.242.90(53809):postgres@mytest:[2048]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:47:10 2023-08-12 05:47:10 UTC:121.7.242.90(53809):postgres@mytest:[2048]:DETAIL:  parameters: $1 = '1000'
2023-08-12T05:47:10 2023-08-12 05:47:10 UTC:121.7.242.90(53809):postgres@mytest:[2048]:LOG:  duration: 1.665 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.014..0.243 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
2023-08-12T05:47:10 2023-08-12 05:47:10 UTC:121.7.242.90(53809):postgres@mytest:[2048]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:47:10 2023-08-12 05:47:10 UTC:121.7.242.90(53809):postgres@mytest:[2048]:DETAIL:  parameters: $1 = '7'
2023-08-12T05:47:10 2023-08-12 05:47:10 UTC:121.7.242.90(53809):postgres@mytest:[2048]:LOG:  duration: 0.022 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.015..0.017 rows=1 loops=1)
	  Index Cond: (id = 7)
2023-08-12T05:47:10 2023-08-12 05:47:10 UTC:121.7.242.90(53809):postgres@mytest:[2048]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:47:10 2023-08-12 05:47:10 UTC:121.7.242.90(53809):postgres@mytest:[2048]:DETAIL:  parameters: $1 = '1000'
2023-08-12T05:47:10 2023-08-12 05:47:10 UTC:121.7.242.90(53809):postgres@mytest:[2048]:LOG:  duration: 0.534 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.013..0.154 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
```

### Test 18: PrepareThreshold1CacheModeForceGeneric + PreparedStatementsStart1000

#### Sample Code
```java
props.setProperty("ApplicationName", "JDBCConnection: PrepareThreshold1CacheModeForceGeneric");
props.setProperty("options", "-c plan_cache_mode=force_generic_plan -c log_statement=all -c auto_explain.log_analyze=1 -c auto_explain.log_min_duration=0");
props.setProperty("prepareThreshold", "1");
```

#### Output
```sql
2023-08-12T05:47:12 2023-08-12 05:47:12 UTC:121.7.242.90(53817):postgres@mytest:[2056]:LOG:  execute <unnamed>: SET extra_float_digits = 3
2023-08-12T05:47:12 2023-08-12 05:47:12 UTC:121.7.242.90(53817):postgres@mytest:[2056]:LOG:  execute <unnamed>: SET application_name = 'JDBCConnection: PrepareThreshold1CacheModeForceGeneric'
2023-08-12T05:47:13 2023-08-12 05:47:13 UTC:121.7.242.90(53817):postgres@mytest:[2056]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:47:13 2023-08-12 05:47:13 UTC:121.7.242.90(53817):postgres@mytest:[2056]:DETAIL:  parameters: $1 = '1000'
2023-08-12T05:47:13 2023-08-12 05:47:13 UTC:121.7.242.90(53817):postgres@mytest:[2056]:LOG:  duration: 481.728 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.026..0.200 rows=990 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:47:14 2023-08-12 05:47:14 UTC:121.7.242.90(53817):postgres@mytest:[2056]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:47:14 2023-08-12 05:47:14 UTC:121.7.242.90(53817):postgres@mytest:[2056]:DETAIL:  parameters: $1 = '2'
2023-08-12T05:47:14 2023-08-12 05:47:14 UTC:121.7.242.90(53817):postgres@mytest:[2056]:LOG:  duration: 0.029 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.022..0.024 rows=1 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:47:14 2023-08-12 05:47:14 UTC:121.7.242.90(53817):postgres@mytest:[2056]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:47:14 2023-08-12 05:47:14 UTC:121.7.242.90(53817):postgres@mytest:[2056]:DETAIL:  parameters: $1 = '3'
2023-08-12T05:47:14 2023-08-12 05:47:14 UTC:121.7.242.90(53817):postgres@mytest:[2056]:LOG:  duration: 0.025 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.018..0.021 rows=1 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:47:14 2023-08-12 05:47:14 UTC:121.7.242.90(53817):postgres@mytest:[2056]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:47:14 2023-08-12 05:47:14 UTC:121.7.242.90(53817):postgres@mytest:[2056]:DETAIL:  parameters: $1 = '4'
2023-08-12T05:47:14 2023-08-12 05:47:14 UTC:121.7.242.90(53817):postgres@mytest:[2056]:LOG:  duration: 0.023 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.018..0.019 rows=1 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:47:14 2023-08-12 05:47:14 UTC:121.7.242.90(53817):postgres@mytest:[2056]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:47:14 2023-08-12 05:47:14 UTC:121.7.242.90(53817):postgres@mytest:[2056]:DETAIL:  parameters: $1 = '5'
2023-08-12T05:47:14 2023-08-12 05:47:14 UTC:121.7.242.90(53817):postgres@mytest:[2056]:LOG:  duration: 0.025 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.019..0.021 rows=1 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:47:14 2023-08-12 05:47:14 UTC:121.7.242.90(53817):postgres@mytest:[2056]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:47:14 2023-08-12 05:47:14 UTC:121.7.242.90(53817):postgres@mytest:[2056]:DETAIL:  parameters: $1 = '6'
2023-08-12T05:47:14 2023-08-12 05:47:14 UTC:121.7.242.90(53817):postgres@mytest:[2056]:LOG:  duration: 0.025 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.019..0.020 rows=1 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:47:15 2023-08-12 05:47:15 UTC:121.7.242.90(53817):postgres@mytest:[2056]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:47:15 2023-08-12 05:47:15 UTC:121.7.242.90(53817):postgres@mytest:[2056]:DETAIL:  parameters: $1 = '1000'
2023-08-12T05:47:15 2023-08-12 05:47:15 UTC:121.7.242.90(53817):postgres@mytest:[2056]:LOG:  duration: 0.669 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.025..0.227 rows=990 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:47:15 2023-08-12 05:47:15 UTC:121.7.242.90(53817):postgres@mytest:[2056]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:47:15 2023-08-12 05:47:15 UTC:121.7.242.90(53817):postgres@mytest:[2056]:DETAIL:  parameters: $1 = '7'
2023-08-12T05:47:15 2023-08-12 05:47:15 UTC:121.7.242.90(53817):postgres@mytest:[2056]:LOG:  duration: 0.026 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.020..0.022 rows=1 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:47:15 2023-08-12 05:47:15 UTC:121.7.242.90(53817):postgres@mytest:[2056]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:47:15 2023-08-12 05:47:15 UTC:121.7.242.90(53817):postgres@mytest:[2056]:DETAIL:  parameters: $1 = '1000'
2023-08-12T05:47:15 2023-08-12 05:47:15 UTC:121.7.242.90(53817):postgres@mytest:[2056]:LOG:  duration: 0.669 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.023..0.219 rows=990 loops=1)
	  Index Cond: (id = $1)
```
