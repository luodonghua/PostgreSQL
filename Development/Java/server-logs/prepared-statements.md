
### Prepare Statements:
```java
PreparedStatement ps = conn.prepareStatement("SELECT * FROM t WHERE id = ?");

ps.setInt(1, 1);
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

| Config | `1` | `2` | `3` | `4` | `5` | `6` | `1000` | `7` | `1000`|
| :-- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
|1.PrepareThreshold5CacheModeAuto|BIS|IS|IS|IS|IS|IS|SEQ|IS|SEQ|
|2.PrepareThreshold5CacheModeForceCustom|IS|IS|IS|IS|IS|IS|SEQ|IS|SEQ|
|3.PrepareThreshold5CacheModeForceGeneric|IS|IS|IS|IS|IS|IS|IS|IS|IS|
|4.PrepareThreshold10CacheModeAuto|IS|IS|IS|IS|IS|IS|SEQ|IS|SEQ|
|5.PrepareThreshold10CacheModeForceCustom|IS|IS|IS|IS|IS|IS|SEQ|IS|SEQ|
|6.PrepareThreshold10CacheModeForceGeneric|IS|IS|IS|IS|IS|IS|IS|IS|IS|
|7.PrepareThreshold1CacheModeAuto|IS|IS|IS|IS|IS|IS|IS|IS|IS|
|8.PrepareThreshold1CacheModeForceCustom|IS|IS|IS|IS|IS|IS|SEQ|IS|SEQ|
|9.PrepareThreshold1CacheModeForceGeneric|IS|IS|IS|IS|IS|IS|IS|IS|IS|


- BIS: Bitmap Index Scan
- IS: Index Scan
- SEQ: Seq Scan

### Test 1: PrepareThreshold5CacheModeAuto + PreparedStatements

#### Sample Code
```java
 props.setProperty("ApplicationName", "JDBCConnection: PrepareThreshold5CacheModeAuto");
props.setProperty("options", "-c plan_cache_mode=auto -c log_statement=all -c auto_explain.log_analyze=1 -c auto_explain.log_min_duration=0");
props.setProperty("prepareThreshold", "5");

```

#### Output
```sql
2023-08-12T05:45:42 2023-08-12 05:45:42 UTC:121.7.242.90(53694):postgres@mytest:[1976]:LOG:  execute <unnamed>: SET extra_float_digits = 3
2023-08-12T05:45:42 2023-08-12 05:45:42 UTC:121.7.242.90(53694):postgres@mytest:[1976]:LOG:  execute <unnamed>: SET application_name = 'JDBCConnection: PrepareThreshold5CacheModeAuto'
2023-08-12T05:45:43 2023-08-12 05:45:43 UTC:121.7.242.90(53694):postgres@mytest:[1976]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:45:43 2023-08-12 05:45:43 UTC:121.7.242.90(53694):postgres@mytest:[1976]:DETAIL:  parameters: $1 = '1'
2023-08-12T05:45:43 2023-08-12 05:45:43 UTC:121.7.242.90(53694):postgres@mytest:[1976]:LOG:  duration: 0.030 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Bitmap Heap Scan on t  (cost=4.19..16.35 rows=5 width=36) (actual time=0.023..0.024 rows=1 loops=1)
	  Recheck Cond: (id = 1)
	  Heap Blocks: exact=1
	  ->  Bitmap Index Scan on t_id_n1  (cost=0.00..4.19 rows=5 width=0) (actual time=0.016..0.016 rows=1 loops=1)
	        Index Cond: (id = 1)
2023-08-12T05:45:43 2023-08-12 05:45:43 UTC:121.7.242.90(53694):postgres@mytest:[1976]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:45:43 2023-08-12 05:45:43 UTC:121.7.242.90(53694):postgres@mytest:[1976]:DETAIL:  parameters: $1 = '2'
2023-08-12T05:45:43 2023-08-12 05:45:43 UTC:121.7.242.90(53694):postgres@mytest:[1976]:LOG:  duration: 0.012 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.007..0.008 rows=1 loops=1)
	  Index Cond: (id = 2)
2023-08-12T05:45:43 2023-08-12 05:45:43 UTC:121.7.242.90(53694):postgres@mytest:[1976]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:45:43 2023-08-12 05:45:43 UTC:121.7.242.90(53694):postgres@mytest:[1976]:DETAIL:  parameters: $1 = '3'
2023-08-12T05:45:43 2023-08-12 05:45:43 UTC:121.7.242.90(53694):postgres@mytest:[1976]:LOG:  duration: 0.016 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.011..0.013 rows=1 loops=1)
	  Index Cond: (id = 3)
2023-08-12T05:45:43 2023-08-12 05:45:43 UTC:121.7.242.90(53694):postgres@mytest:[1976]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:45:43 2023-08-12 05:45:43 UTC:121.7.242.90(53694):postgres@mytest:[1976]:DETAIL:  parameters: $1 = '4'
2023-08-12T05:45:43 2023-08-12 05:45:43 UTC:121.7.242.90(53694):postgres@mytest:[1976]:LOG:  duration: 0.018 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.013..0.015 rows=1 loops=1)
	  Index Cond: (id = 4)
2023-08-12T05:45:44 2023-08-12 05:45:44 UTC:121.7.242.90(53694):postgres@mytest:[1976]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:45:44 2023-08-12 05:45:44 UTC:121.7.242.90(53694):postgres@mytest:[1976]:DETAIL:  parameters: $1 = '5'
2023-08-12T05:45:44 2023-08-12 05:45:44 UTC:121.7.242.90(53694):postgres@mytest:[1976]:LOG:  duration: 0.025 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.019..0.021 rows=1 loops=1)
	  Index Cond: (id = 5)
2023-08-12T05:45:44 2023-08-12 05:45:44 UTC:121.7.242.90(53694):postgres@mytest:[1976]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:45:44 2023-08-12 05:45:44 UTC:121.7.242.90(53694):postgres@mytest:[1976]:DETAIL:  parameters: $1 = '6'
2023-08-12T05:45:44 2023-08-12 05:45:44 UTC:121.7.242.90(53694):postgres@mytest:[1976]:LOG:  duration: 0.020 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.013..0.015 rows=1 loops=1)
	  Index Cond: (id = 6)
2023-08-12T05:45:44 2023-08-12 05:45:44 UTC:121.7.242.90(53694):postgres@mytest:[1976]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:45:44 2023-08-12 05:45:44 UTC:121.7.242.90(53694):postgres@mytest:[1976]:DETAIL:  parameters: $1 = '1000'
2023-08-12T05:45:45 2023-08-12 05:45:45 UTC:121.7.242.90(53694):postgres@mytest:[1976]:LOG:  duration: 483.130 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.014..0.211 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
2023-08-12T05:45:45 2023-08-12 05:45:45 UTC:121.7.242.90(53694):postgres@mytest:[1976]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:45:45 2023-08-12 05:45:45 UTC:121.7.242.90(53694):postgres@mytest:[1976]:DETAIL:  parameters: $1 = '7'
2023-08-12T05:45:45 2023-08-12 05:45:45 UTC:121.7.242.90(53694):postgres@mytest:[1976]:LOG:  duration: 0.022 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.016..0.018 rows=1 loops=1)
	  Index Cond: (id = 7)
2023-08-12T05:45:45 2023-08-12 05:45:45 UTC:121.7.242.90(53694):postgres@mytest:[1976]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:45:45 2023-08-12 05:45:45 UTC:121.7.242.90(53694):postgres@mytest:[1976]:DETAIL:  parameters: $1 = '1000'
2023-08-12T05:45:45 2023-08-12 05:45:45 UTC:121.7.242.90(53694):postgres@mytest:[1976]:LOG:  duration: 0.733 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.014..0.180 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10

```


### Test 2: PrepareThreshold5CacheModeForceCustom + PreparedStatements

#### Sample Code
```java
props.setProperty("ApplicationName", "JDBCConnection: PrepareThreshold5CacheModeForceCustom");
props.setProperty("options", "-c plan_cache_mode=force_custom_plan -c log_statement=all -c auto_explain.log_analyze=1 -c auto_explain.log_min_duration=0");
props.setProperty("prepareThreshold", "5");
```

#### Output
```sql
2023-08-12T05:45:47 2023-08-12 05:45:47 UTC:121.7.242.90(53704):postgres@mytest:[1979]:LOG:  execute <unnamed>: SET extra_float_digits = 3
2023-08-12T05:45:47 2023-08-12 05:45:47 UTC:121.7.242.90(53704):postgres@mytest:[1979]:LOG:  execute <unnamed>: SET application_name = 'JDBCConnection: PrepareThreshold5CacheModeForceCustom'
2023-08-12T05:45:48 2023-08-12 05:45:48 UTC:121.7.242.90(53704):postgres@mytest:[1979]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:45:48 2023-08-12 05:45:48 UTC:121.7.242.90(53704):postgres@mytest:[1979]:DETAIL:  parameters: $1 = '1'
2023-08-12T05:45:48 2023-08-12 05:45:48 UTC:121.7.242.90(53704):postgres@mytest:[1979]:LOG:  duration: 0.014 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.011..0.011 rows=1 loops=1)
	  Index Cond: (id = 1)
2023-08-12T05:45:48 2023-08-12 05:45:48 UTC:121.7.242.90(53704):postgres@mytest:[1979]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:45:48 2023-08-12 05:45:48 UTC:121.7.242.90(53704):postgres@mytest:[1979]:DETAIL:  parameters: $1 = '2'
2023-08-12T05:45:48 2023-08-12 05:45:48 UTC:121.7.242.90(53704):postgres@mytest:[1979]:LOG:  duration: 0.020 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.015..0.016 rows=1 loops=1)
	  Index Cond: (id = 2)
2023-08-12T05:45:48 2023-08-12 05:45:48 UTC:121.7.242.90(53704):postgres@mytest:[1979]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:45:48 2023-08-12 05:45:48 UTC:121.7.242.90(53704):postgres@mytest:[1979]:DETAIL:  parameters: $1 = '3'
2023-08-12T05:45:48 2023-08-12 05:45:48 UTC:121.7.242.90(53704):postgres@mytest:[1979]:LOG:  duration: 0.020 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.015..0.016 rows=1 loops=1)
	  Index Cond: (id = 3)
2023-08-12T05:45:48 2023-08-12 05:45:48 UTC:121.7.242.90(53704):postgres@mytest:[1979]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:45:48 2023-08-12 05:45:48 UTC:121.7.242.90(53704):postgres@mytest:[1979]:DETAIL:  parameters: $1 = '4'
2023-08-12T05:45:48 2023-08-12 05:45:48 UTC:121.7.242.90(53704):postgres@mytest:[1979]:LOG:  duration: 0.022 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.015..0.017 rows=1 loops=1)
	  Index Cond: (id = 4)
2023-08-12T05:45:49 2023-08-12 05:45:49 UTC:121.7.242.90(53704):postgres@mytest:[1979]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:45:49 2023-08-12 05:45:49 UTC:121.7.242.90(53704):postgres@mytest:[1979]:DETAIL:  parameters: $1 = '5'
2023-08-12T05:45:49 2023-08-12 05:45:49 UTC:121.7.242.90(53704):postgres@mytest:[1979]:LOG:  duration: 0.023 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.018..0.019 rows=1 loops=1)
	  Index Cond: (id = 5)
2023-08-12T05:45:49 2023-08-12 05:45:49 UTC:121.7.242.90(53704):postgres@mytest:[1979]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:45:49 2023-08-12 05:45:49 UTC:121.7.242.90(53704):postgres@mytest:[1979]:DETAIL:  parameters: $1 = '6'
2023-08-12T05:45:49 2023-08-12 05:45:49 UTC:121.7.242.90(53704):postgres@mytest:[1979]:LOG:  duration: 0.021 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.014..0.016 rows=1 loops=1)
	  Index Cond: (id = 6)
2023-08-12T05:45:49 2023-08-12 05:45:49 UTC:121.7.242.90(53704):postgres@mytest:[1979]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:45:49 2023-08-12 05:45:49 UTC:121.7.242.90(53704):postgres@mytest:[1979]:DETAIL:  parameters: $1 = '1000'
2023-08-12T05:45:50 2023-08-12 05:45:50 UTC:121.7.242.90(53704):postgres@mytest:[1979]:LOG:  duration: 472.711 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.021..0.174 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
2023-08-12T05:45:50 2023-08-12 05:45:50 UTC:121.7.242.90(53704):postgres@mytest:[1979]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:45:50 2023-08-12 05:45:50 UTC:121.7.242.90(53704):postgres@mytest:[1979]:DETAIL:  parameters: $1 = '7'
2023-08-12T05:45:50 2023-08-12 05:45:50 UTC:121.7.242.90(53704):postgres@mytest:[1979]:LOG:  duration: 0.022 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.016..0.018 rows=1 loops=1)
	  Index Cond: (id = 7)
2023-08-12T05:45:50 2023-08-12 05:45:50 UTC:121.7.242.90(53704):postgres@mytest:[1979]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:45:50 2023-08-12 05:45:50 UTC:121.7.242.90(53704):postgres@mytest:[1979]:DETAIL:  parameters: $1 = '1000'
2023-08-12T05:45:50 2023-08-12 05:45:50 UTC:121.7.242.90(53704):postgres@mytest:[1979]:LOG:  duration: 0.557 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.012..0.173 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
```


### Test 3: PrepareThreshold5CacheModeForceGeneric + PreparedStatements

#### Sample Code
```java
props.setProperty("ApplicationName", "JDBCConnection: PrepareThreshold5CacheModeForceGeneric");
props.setProperty("options", "-c plan_cache_mode=force_generic_plan -c log_statement=all -c auto_explain.log_analyze=1 -c auto_explain.log_min_duration=0");
props.setProperty("prepareThreshold", "5");
```

#### Output
```sql
2023-08-12T05:45:52 2023-08-12 05:45:52 UTC:121.7.242.90(53709):postgres@mytest:[1982]:LOG:  execute <unnamed>: SET extra_float_digits = 3
2023-08-12T05:45:53 2023-08-12 05:45:53 UTC:121.7.242.90(53709):postgres@mytest:[1982]:LOG:  execute <unnamed>: SET application_name = 'JDBCConnection: PrepareThreshold5CacheModeForceGeneric'
2023-08-12T05:45:53 2023-08-12 05:45:53 UTC:121.7.242.90(53709):postgres@mytest:[1982]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:45:53 2023-08-12 05:45:53 UTC:121.7.242.90(53709):postgres@mytest:[1982]:DETAIL:  parameters: $1 = '1'
2023-08-12T05:45:53 2023-08-12 05:45:53 UTC:121.7.242.90(53709):postgres@mytest:[1982]:LOG:  duration: 0.023 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.015..0.015 rows=1 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:45:53 2023-08-12 05:45:53 UTC:121.7.242.90(53709):postgres@mytest:[1982]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:45:53 2023-08-12 05:45:53 UTC:121.7.242.90(53709):postgres@mytest:[1982]:DETAIL:  parameters: $1 = '2'
2023-08-12T05:45:53 2023-08-12 05:45:53 UTC:121.7.242.90(53709):postgres@mytest:[1982]:LOG:  duration: 0.025 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.019..0.021 rows=1 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:45:53 2023-08-12 05:45:53 UTC:121.7.242.90(53709):postgres@mytest:[1982]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:45:53 2023-08-12 05:45:53 UTC:121.7.242.90(53709):postgres@mytest:[1982]:DETAIL:  parameters: $1 = '3'
2023-08-12T05:45:53 2023-08-12 05:45:53 UTC:121.7.242.90(53709):postgres@mytest:[1982]:LOG:  duration: 0.023 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.017..0.019 rows=1 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:45:54 2023-08-12 05:45:54 UTC:121.7.242.90(53709):postgres@mytest:[1982]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:45:54 2023-08-12 05:45:54 UTC:121.7.242.90(53709):postgres@mytest:[1982]:DETAIL:  parameters: $1 = '4'
2023-08-12T05:45:54 2023-08-12 05:45:54 UTC:121.7.242.90(53709):postgres@mytest:[1982]:LOG:  duration: 0.026 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.020..0.022 rows=1 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:45:54 2023-08-12 05:45:54 UTC:121.7.242.90(53709):postgres@mytest:[1982]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:45:54 2023-08-12 05:45:54 UTC:121.7.242.90(53709):postgres@mytest:[1982]:DETAIL:  parameters: $1 = '5'
2023-08-12T05:45:54 2023-08-12 05:45:54 UTC:121.7.242.90(53709):postgres@mytest:[1982]:LOG:  duration: 0.024 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.016..0.017 rows=1 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:45:54 2023-08-12 05:45:54 UTC:121.7.242.90(53709):postgres@mytest:[1982]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:45:54 2023-08-12 05:45:54 UTC:121.7.242.90(53709):postgres@mytest:[1982]:DETAIL:  parameters: $1 = '6'
2023-08-12T05:45:54 2023-08-12 05:45:54 UTC:121.7.242.90(53709):postgres@mytest:[1982]:LOG:  duration: 0.026 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.020..0.021 rows=1 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:45:54 2023-08-12 05:45:54 UTC:121.7.242.90(53709):postgres@mytest:[1982]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:45:54 2023-08-12 05:45:54 UTC:121.7.242.90(53709):postgres@mytest:[1982]:DETAIL:  parameters: $1 = '1000'
2023-08-12T05:45:55 2023-08-12 05:45:55 UTC:121.7.242.90(53709):postgres@mytest:[1982]:LOG:  duration: 493.251 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.034..0.268 rows=990 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:45:55 2023-08-12 05:45:55 UTC:121.7.242.90(53709):postgres@mytest:[1982]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:45:55 2023-08-12 05:45:55 UTC:121.7.242.90(53709):postgres@mytest:[1982]:DETAIL:  parameters: $1 = '7'
2023-08-12T05:45:55 2023-08-12 05:45:55 UTC:121.7.242.90(53709):postgres@mytest:[1982]:LOG:  duration: 0.030 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.022..0.024 rows=1 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:45:56 2023-08-12 05:45:56 UTC:121.7.242.90(53709):postgres@mytest:[1982]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:45:56 2023-08-12 05:45:56 UTC:121.7.242.90(53709):postgres@mytest:[1982]:DETAIL:  parameters: $1 = '1000'
2023-08-12T05:45:56 2023-08-12 05:45:56 UTC:121.7.242.90(53709):postgres@mytest:[1982]:LOG:  duration: 0.651 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.023..0.238 rows=990 loops=1)
	  Index Cond: (id = $1)
```



### Test 4: PrepareThreshold10CacheModeAuto + PreparedStatements

#### Sample Code
```java
props.setProperty("ApplicationName", "JDBCConnection: PrepareThreshold10CacheModeAuto");
props.setProperty("options", "-c plan_cache_mode=auto -c log_statement=all -c auto_explain.log_analyze=1 -c auto_explain.log_min_duration=0");
props.setProperty("prepareThreshold", "10");
```

#### Output
```sql
2023-08-12T05:45:58 2023-08-12 05:45:58 UTC:121.7.242.90(53718):postgres@mytest:[1990]:LOG:  execute <unnamed>: SET extra_float_digits = 3
2023-08-12T05:45:58 2023-08-12 05:45:58 UTC:121.7.242.90(53718):postgres@mytest:[1990]:LOG:  execute <unnamed>: SET application_name = 'JDBCConnection: PrepareThreshold10CacheModeAuto'
2023-08-12T05:45:58 2023-08-12 05:45:58 UTC:121.7.242.90(53718):postgres@mytest:[1990]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:45:58 2023-08-12 05:45:58 UTC:121.7.242.90(53718):postgres@mytest:[1990]:DETAIL:  parameters: $1 = '1'
2023-08-12T05:45:58 2023-08-12 05:45:58 UTC:121.7.242.90(53718):postgres@mytest:[1990]:LOG:  duration: 0.019 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.015..0.016 rows=1 loops=1)
	  Index Cond: (id = 1)
2023-08-12T05:45:59 2023-08-12 05:45:59 UTC:121.7.242.90(53718):postgres@mytest:[1990]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:45:59 2023-08-12 05:45:59 UTC:121.7.242.90(53718):postgres@mytest:[1990]:DETAIL:  parameters: $1 = '2'
2023-08-12T05:45:59 2023-08-12 05:45:59 UTC:121.7.242.90(53718):postgres@mytest:[1990]:LOG:  duration: 0.020 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.015..0.016 rows=1 loops=1)
	  Index Cond: (id = 2)
2023-08-12T05:45:59 2023-08-12 05:45:59 UTC:121.7.242.90(53718):postgres@mytest:[1990]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:45:59 2023-08-12 05:45:59 UTC:121.7.242.90(53718):postgres@mytest:[1990]:DETAIL:  parameters: $1 = '3'
2023-08-12T05:45:59 2023-08-12 05:45:59 UTC:121.7.242.90(53718):postgres@mytest:[1990]:LOG:  duration: 0.024 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.019..0.020 rows=1 loops=1)
	  Index Cond: (id = 3)
2023-08-12T05:45:59 2023-08-12 05:45:59 UTC:121.7.242.90(53718):postgres@mytest:[1990]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:45:59 2023-08-12 05:45:59 UTC:121.7.242.90(53718):postgres@mytest:[1990]:DETAIL:  parameters: $1 = '4'
2023-08-12T05:45:59 2023-08-12 05:45:59 UTC:121.7.242.90(53718):postgres@mytest:[1990]:LOG:  duration: 0.018 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.013..0.014 rows=1 loops=1)
	  Index Cond: (id = 4)
2023-08-12T05:45:59 2023-08-12 05:45:59 UTC:121.7.242.90(53718):postgres@mytest:[1990]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:45:59 2023-08-12 05:45:59 UTC:121.7.242.90(53718):postgres@mytest:[1990]:DETAIL:  parameters: $1 = '5'
2023-08-12T05:45:59 2023-08-12 05:45:59 UTC:121.7.242.90(53718):postgres@mytest:[1990]:LOG:  duration: 0.020 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.014..0.015 rows=1 loops=1)
	  Index Cond: (id = 5)
2023-08-12T05:46:00 2023-08-12 05:46:00 UTC:121.7.242.90(53718):postgres@mytest:[1990]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:00 2023-08-12 05:46:00 UTC:121.7.242.90(53718):postgres@mytest:[1990]:DETAIL:  parameters: $1 = '6'
2023-08-12T05:46:00 2023-08-12 05:46:00 UTC:121.7.242.90(53718):postgres@mytest:[1990]:LOG:  duration: 0.018 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.013..0.014 rows=1 loops=1)
	  Index Cond: (id = 6)
2023-08-12T05:46:00 2023-08-12 05:46:00 UTC:121.7.242.90(53718):postgres@mytest:[1990]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:00 2023-08-12 05:46:00 UTC:121.7.242.90(53718):postgres@mytest:[1990]:DETAIL:  parameters: $1 = '1000'
2023-08-12T05:46:01 2023-08-12 05:46:01 UTC:121.7.242.90(53718):postgres@mytest:[1990]:LOG:  duration: 653.396 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.016..0.220 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
2023-08-12T05:46:01 2023-08-12 05:46:01 UTC:121.7.242.90(53718):postgres@mytest:[1990]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:01 2023-08-12 05:46:01 UTC:121.7.242.90(53718):postgres@mytest:[1990]:DETAIL:  parameters: $1 = '7'
2023-08-12T05:46:01 2023-08-12 05:46:01 UTC:121.7.242.90(53718):postgres@mytest:[1990]:LOG:  duration: 0.044 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.038..0.039 rows=1 loops=1)
	  Index Cond: (id = 7)
2023-08-12T05:46:01 2023-08-12 05:46:01 UTC:121.7.242.90(53718):postgres@mytest:[1990]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:01 2023-08-12 05:46:01 UTC:121.7.242.90(53718):postgres@mytest:[1990]:DETAIL:  parameters: $1 = '1000'
2023-08-12T05:46:01 2023-08-12 05:46:01 UTC:121.7.242.90(53718):postgres@mytest:[1990]:LOG:  duration: 0.659 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.015..0.178 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
```



### Test 5: PrepareThreshold10CacheModeForceCustom + PreparedStatements

#### Sample Code
```java
props.setProperty("ApplicationName", "JDBCConnection: PrepareThreshold10CacheModeForceCustom");
props.setProperty("options", "-c plan_cache_mode=force_custom_plan -c log_statement=all -c auto_explain.log_analyze=1 -c auto_explain.log_min_duration=0");
props.setProperty("prepareThreshold", "10");
```

#### Output
```sql
2023-08-12T05:46:04 2023-08-12 05:46:04 UTC:121.7.242.90(53725):postgres@mytest:[1993]:LOG:  execute <unnamed>: SET extra_float_digits = 3
2023-08-12T05:46:04 2023-08-12 05:46:04 UTC:121.7.242.90(53725):postgres@mytest:[1993]:LOG:  execute <unnamed>: SET application_name = 'JDBCConnection: PrepareThreshold10CacheModeForceCustom'
2023-08-12T05:46:04 2023-08-12 05:46:04 UTC:121.7.242.90(53725):postgres@mytest:[1993]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:04 2023-08-12 05:46:04 UTC:121.7.242.90(53725):postgres@mytest:[1993]:DETAIL:  parameters: $1 = '1'
2023-08-12T05:46:04 2023-08-12 05:46:04 UTC:121.7.242.90(53725):postgres@mytest:[1993]:LOG:  duration: 0.022 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.017..0.018 rows=1 loops=1)
	  Index Cond: (id = 1)
2023-08-12T05:46:04 2023-08-12 05:46:04 UTC:121.7.242.90(53725):postgres@mytest:[1993]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:04 2023-08-12 05:46:04 UTC:121.7.242.90(53725):postgres@mytest:[1993]:DETAIL:  parameters: $1 = '2'
2023-08-12T05:46:04 2023-08-12 05:46:04 UTC:121.7.242.90(53725):postgres@mytest:[1993]:LOG:  duration: 0.016 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.012..0.013 rows=1 loops=1)
	  Index Cond: (id = 2)
2023-08-12T05:46:05 2023-08-12 05:46:05 UTC:121.7.242.90(53725):postgres@mytest:[1993]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:05 2023-08-12 05:46:05 UTC:121.7.242.90(53725):postgres@mytest:[1993]:DETAIL:  parameters: $1 = '3'
2023-08-12T05:46:05 2023-08-12 05:46:05 UTC:121.7.242.90(53725):postgres@mytest:[1993]:LOG:  duration: 0.022 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.016..0.018 rows=1 loops=1)
	  Index Cond: (id = 3)
2023-08-12T05:46:05 2023-08-12 05:46:05 UTC:121.7.242.90(53725):postgres@mytest:[1993]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:05 2023-08-12 05:46:05 UTC:121.7.242.90(53725):postgres@mytest:[1993]:DETAIL:  parameters: $1 = '4'
2023-08-12T05:46:05 2023-08-12 05:46:05 UTC:121.7.242.90(53725):postgres@mytest:[1993]:LOG:  duration: 0.019 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.013..0.015 rows=1 loops=1)
	  Index Cond: (id = 4)
2023-08-12T05:46:05 2023-08-12 05:46:05 UTC:121.7.242.90(53725):postgres@mytest:[1993]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:05 2023-08-12 05:46:05 UTC:121.7.242.90(53725):postgres@mytest:[1993]:DETAIL:  parameters: $1 = '5'
2023-08-12T05:46:05 2023-08-12 05:46:05 UTC:121.7.242.90(53725):postgres@mytest:[1993]:LOG:  duration: 0.019 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.013..0.015 rows=1 loops=1)
	  Index Cond: (id = 5)
2023-08-12T05:46:05 2023-08-12 05:46:05 UTC:121.7.242.90(53725):postgres@mytest:[1993]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:05 2023-08-12 05:46:05 UTC:121.7.242.90(53725):postgres@mytest:[1993]:DETAIL:  parameters: $1 = '6'
2023-08-12T05:46:05 2023-08-12 05:46:05 UTC:121.7.242.90(53725):postgres@mytest:[1993]:LOG:  duration: 0.019 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.014..0.015 rows=1 loops=1)
	  Index Cond: (id = 6)
2023-08-12T05:46:06 2023-08-12 05:46:06 UTC:121.7.242.90(53725):postgres@mytest:[1993]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:06 2023-08-12 05:46:06 UTC:121.7.242.90(53725):postgres@mytest:[1993]:DETAIL:  parameters: $1 = '1000'
2023-08-12T05:46:06 2023-08-12 05:46:06 UTC:121.7.242.90(53725):postgres@mytest:[1993]:LOG:  duration: 518.826 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.032..0.211 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
2023-08-12T05:46:07 2023-08-12 05:46:07 UTC:121.7.242.90(53725):postgres@mytest:[1993]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:07 2023-08-12 05:46:07 UTC:121.7.242.90(53725):postgres@mytest:[1993]:DETAIL:  parameters: $1 = '7'
2023-08-12T05:46:07 2023-08-12 05:46:07 UTC:121.7.242.90(53725):postgres@mytest:[1993]:LOG:  duration: 0.020 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.014..0.016 rows=1 loops=1)
	  Index Cond: (id = 7)
2023-08-12T05:46:07 2023-08-12 05:46:07 UTC:121.7.242.90(53725):postgres@mytest:[1993]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:07 2023-08-12 05:46:07 UTC:121.7.242.90(53725):postgres@mytest:[1993]:DETAIL:  parameters: $1 = '1000'
2023-08-12T05:46:07 2023-08-12 05:46:07 UTC:121.7.242.90(53725):postgres@mytest:[1993]:LOG:  duration: 0.649 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.016..0.189 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
```



### Test 6: PrepareThreshold10CacheModeForceGeneric + PreparedStatements

#### Sample Code
```java
props.setProperty("ApplicationName", "JDBCConnection: PrepareThreshold10CacheModeForceGeneric");
props.setProperty("options", "-c plan_cache_mode=force_generic_plan -c log_statement=all -c auto_explain.log_analyze=1 -c auto_explain.log_min_duration=0");
props.setProperty("prepareThreshold", "10");
```

#### Output
```sql
2023-08-12T05:46:11 2023-08-12 05:46:11 UTC:121.7.242.90(53732):postgres@mytest:[1997]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:11 2023-08-12 05:46:11 UTC:121.7.242.90(53732):postgres@mytest:[1997]:DETAIL:  parameters: $1 = '4'
2023-08-12T05:46:11 2023-08-12 05:46:11 UTC:121.7.242.90(53732):postgres@mytest:[1997]:LOG:  duration: 0.026 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.021..0.022 rows=1 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:46:11 2023-08-12 05:46:11 UTC:121.7.242.90(53732):postgres@mytest:[1997]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:11 2023-08-12 05:46:11 UTC:121.7.242.90(53732):postgres@mytest:[1997]:DETAIL:  parameters: $1 = '5'
2023-08-12T05:46:11 2023-08-12 05:46:11 UTC:121.7.242.90(53732):postgres@mytest:[1997]:LOG:  duration: 0.024 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.018..0.020 rows=1 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:46:11 2023-08-12 05:46:11 UTC:121.7.242.90(53732):postgres@mytest:[1997]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:11 2023-08-12 05:46:11 UTC:121.7.242.90(53732):postgres@mytest:[1997]:DETAIL:  parameters: $1 = '6'
2023-08-12T05:46:11 2023-08-12 05:46:11 UTC:121.7.242.90(53732):postgres@mytest:[1997]:LOG:  duration: 0.022 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.017..0.019 rows=1 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:46:11 2023-08-12 05:46:11 UTC:121.7.242.90(53732):postgres@mytest:[1997]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:11 2023-08-12 05:46:11 UTC:121.7.242.90(53732):postgres@mytest:[1997]:DETAIL:  parameters: $1 = '1000'
2023-08-12T05:46:12 2023-08-12 05:46:12 UTC:121.7.242.90(53732):postgres@mytest:[1997]:LOG:  duration: 482.017 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.033..0.236 rows=990 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:46:12 2023-08-12 05:46:12 UTC:121.7.242.90(53732):postgres@mytest:[1997]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:12 2023-08-12 05:46:12 UTC:121.7.242.90(53732):postgres@mytest:[1997]:DETAIL:  parameters: $1 = '7'
2023-08-12T05:46:12 2023-08-12 05:46:12 UTC:121.7.242.90(53732):postgres@mytest:[1997]:LOG:  duration: 0.024 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.019..0.021 rows=1 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:46:13 2023-08-12 05:46:13 UTC:121.7.242.90(53732):postgres@mytest:[1997]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:13 2023-08-12 05:46:13 UTC:121.7.242.90(53732):postgres@mytest:[1997]:DETAIL:  parameters: $1 = '1000'
2023-08-12T05:46:13 2023-08-12 05:46:13 UTC:121.7.242.90(53732):postgres@mytest:[1997]:LOG:  duration: 0.581 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.021..0.189 rows=990 loops=1)
	  Index Cond: (id = $1)
```


### Test 7: PrepareThreshold1CacheModeAuto + PreparedStatements

#### Sample Code
```java
props.setProperty("ApplicationName", "JDBCConnection: PrepareThreshold1CacheModeAuto");
props.setProperty("options", "-c plan_cache_mode=auto -c log_statement=all -c auto_explain.log_analyze=1 -c auto_explain.log_min_duration=0");
props.setProperty("prepareThreshold", "1");
```

#### Output
```sql
2023-08-12T05:46:15 2023-08-12 05:46:15 UTC:121.7.242.90(53745):postgres@mytest:[2005]:LOG:  execute <unnamed>: SET extra_float_digits = 3
2023-08-12T05:46:15 2023-08-12 05:46:15 UTC:121.7.242.90(53745):postgres@mytest:[2005]:LOG:  execute <unnamed>: SET application_name = 'JDBCConnection: PrepareThreshold1CacheModeAuto'
2023-08-12T05:46:15 2023-08-12 05:46:15 UTC:121.7.242.90(53745):postgres@mytest:[2005]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:15 2023-08-12 05:46:15 UTC:121.7.242.90(53745):postgres@mytest:[2005]:DETAIL:  parameters: $1 = '1'
2023-08-12T05:46:15 2023-08-12 05:46:15 UTC:121.7.242.90(53745):postgres@mytest:[2005]:LOG:  duration: 0.015 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.011..0.012 rows=1 loops=1)
	  Index Cond: (id = 1)
2023-08-12T05:46:15 2023-08-12 05:46:15 UTC:121.7.242.90(53745):postgres@mytest:[2005]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:15 2023-08-12 05:46:15 UTC:121.7.242.90(53745):postgres@mytest:[2005]:DETAIL:  parameters: $1 = '2'
2023-08-12T05:46:15 2023-08-12 05:46:15 UTC:121.7.242.90(53745):postgres@mytest:[2005]:LOG:  duration: 0.020 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.014..0.016 rows=1 loops=1)
	  Index Cond: (id = 2)
2023-08-12T05:46:16 2023-08-12 05:46:16 UTC:121.7.242.90(53745):postgres@mytest:[2005]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:16 2023-08-12 05:46:16 UTC:121.7.242.90(53745):postgres@mytest:[2005]:DETAIL:  parameters: $1 = '3'
2023-08-12T05:46:16 2023-08-12 05:46:16 UTC:121.7.242.90(53745):postgres@mytest:[2005]:LOG:  duration: 0.022 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.016..0.018 rows=1 loops=1)
	  Index Cond: (id = 3)
2023-08-12T05:46:16 2023-08-12 05:46:16 UTC:121.7.242.90(53745):postgres@mytest:[2005]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:16 2023-08-12 05:46:16 UTC:121.7.242.90(53745):postgres@mytest:[2005]:DETAIL:  parameters: $1 = '4'
2023-08-12T05:46:16 2023-08-12 05:46:16 UTC:121.7.242.90(53745):postgres@mytest:[2005]:LOG:  duration: 0.019 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.013..0.014 rows=1 loops=1)
	  Index Cond: (id = 4)
2023-08-12T05:46:16 2023-08-12 05:46:16 UTC:121.7.242.90(53745):postgres@mytest:[2005]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:16 2023-08-12 05:46:16 UTC:121.7.242.90(53745):postgres@mytest:[2005]:DETAIL:  parameters: $1 = '5'
2023-08-12T05:46:16 2023-08-12 05:46:16 UTC:121.7.242.90(53745):postgres@mytest:[2005]:LOG:  duration: 0.018 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.014..0.015 rows=1 loops=1)
	  Index Cond: (id = 5)
2023-08-12T05:46:16 2023-08-12 05:46:16 UTC:121.7.242.90(53745):postgres@mytest:[2005]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:16 2023-08-12 05:46:16 UTC:121.7.242.90(53745):postgres@mytest:[2005]:DETAIL:  parameters: $1 = '6'
2023-08-12T05:46:16 2023-08-12 05:46:16 UTC:121.7.242.90(53745):postgres@mytest:[2005]:LOG:  duration: 0.033 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.017..0.019 rows=1 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:46:17 2023-08-12 05:46:17 UTC:121.7.242.90(53745):postgres@mytest:[2005]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:17 2023-08-12 05:46:17 UTC:121.7.242.90(53745):postgres@mytest:[2005]:DETAIL:  parameters: $1 = '1000'
2023-08-12T05:46:17 2023-08-12 05:46:17 UTC:121.7.242.90(53745):postgres@mytest:[2005]:LOG:  duration: 502.341 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.036..0.246 rows=990 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:46:18 2023-08-12 05:46:18 UTC:121.7.242.90(53745):postgres@mytest:[2005]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:18 2023-08-12 05:46:18 UTC:121.7.242.90(53745):postgres@mytest:[2005]:DETAIL:  parameters: $1 = '7'
2023-08-12T05:46:18 2023-08-12 05:46:18 UTC:121.7.242.90(53745):postgres@mytest:[2005]:LOG:  duration: 0.024 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.018..0.020 rows=1 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:46:18 2023-08-12 05:46:18 UTC:121.7.242.90(53745):postgres@mytest:[2005]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:18 2023-08-12 05:46:18 UTC:121.7.242.90(53745):postgres@mytest:[2005]:DETAIL:  parameters: $1 = '1000'
2023-08-12T05:46:18 2023-08-12 05:46:18 UTC:121.7.242.90(53745):postgres@mytest:[2005]:LOG:  duration: 0.561 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.024..0.192 rows=990 loops=1)
	  Index Cond: (id = $1)
```

### Test 8: PrepareThreshold1CacheModeForceCustom + PreparedStatements

#### Sample Code
```java
props.setProperty("ApplicationName", "JDBCConnection: PrepareThreshold1CacheModeForceCustom");
props.setProperty("options", "-c plan_cache_mode=force_custom_plan -c log_statement=all -c auto_explain.log_analyze=1 -c auto_explain.log_min_duration=0");
props.setProperty("prepareThreshold", "1");
```

#### Output
```sql
2023-08-12T05:46:20 2023-08-12 05:46:20 UTC:121.7.242.90(53749):postgres@mytest:[2007]:LOG:  execute <unnamed>: SET extra_float_digits = 3
2023-08-12T05:46:20 2023-08-12 05:46:20 UTC:121.7.242.90(53749):postgres@mytest:[2007]:LOG:  execute <unnamed>: SET application_name = 'JDBCConnection: PrepareThreshold1CacheModeForceCustom'
2023-08-12T05:46:21 2023-08-12 05:46:21 UTC:121.7.242.90(53749):postgres@mytest:[2007]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:21 2023-08-12 05:46:21 UTC:121.7.242.90(53749):postgres@mytest:[2007]:DETAIL:  parameters: $1 = '1'
2023-08-12T05:46:21 2023-08-12 05:46:21 UTC:121.7.242.90(53749):postgres@mytest:[2007]:LOG:  duration: 0.017 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.012..0.013 rows=1 loops=1)
	  Index Cond: (id = 1)
2023-08-12T05:46:21 2023-08-12 05:46:21 UTC:121.7.242.90(53749):postgres@mytest:[2007]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:21 2023-08-12 05:46:21 UTC:121.7.242.90(53749):postgres@mytest:[2007]:DETAIL:  parameters: $1 = '2'
2023-08-12T05:46:21 2023-08-12 05:46:21 UTC:121.7.242.90(53749):postgres@mytest:[2007]:LOG:  duration: 0.025 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.017..0.018 rows=1 loops=1)
	  Index Cond: (id = 2)
2023-08-12T05:46:21 2023-08-12 05:46:21 UTC:121.7.242.90(53749):postgres@mytest:[2007]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:21 2023-08-12 05:46:21 UTC:121.7.242.90(53749):postgres@mytest:[2007]:DETAIL:  parameters: $1 = '3'
2023-08-12T05:46:21 2023-08-12 05:46:21 UTC:121.7.242.90(53749):postgres@mytest:[2007]:LOG:  duration: 0.033 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.015..0.028 rows=1 loops=1)
	  Index Cond: (id = 3)
2023-08-12T05:46:21 2023-08-12 05:46:21 UTC:121.7.242.90(53749):postgres@mytest:[2007]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:21 2023-08-12 05:46:21 UTC:121.7.242.90(53749):postgres@mytest:[2007]:DETAIL:  parameters: $1 = '4'
2023-08-12T05:46:21 2023-08-12 05:46:21 UTC:121.7.242.90(53749):postgres@mytest:[2007]:LOG:  duration: 0.022 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.015..0.017 rows=1 loops=1)
	  Index Cond: (id = 4)
2023-08-12T05:46:21 2023-08-12 05:46:21 UTC:121.7.242.90(53749):postgres@mytest:[2007]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:21 2023-08-12 05:46:21 UTC:121.7.242.90(53749):postgres@mytest:[2007]:DETAIL:  parameters: $1 = '5'
2023-08-12T05:46:21 2023-08-12 05:46:21 UTC:121.7.242.90(53749):postgres@mytest:[2007]:LOG:  duration: 0.018 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.013..0.015 rows=1 loops=1)
	  Index Cond: (id = 5)
2023-08-12T05:46:22 2023-08-12 05:46:22 UTC:121.7.242.90(53749):postgres@mytest:[2007]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:22 2023-08-12 05:46:22 UTC:121.7.242.90(53749):postgres@mytest:[2007]:DETAIL:  parameters: $1 = '6'
2023-08-12T05:46:22 2023-08-12 05:46:22 UTC:121.7.242.90(53749):postgres@mytest:[2007]:LOG:  duration: 0.021 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.015..0.016 rows=1 loops=1)
	  Index Cond: (id = 6)
2023-08-12T05:46:22 2023-08-12 05:46:22 UTC:121.7.242.90(53749):postgres@mytest:[2007]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:22 2023-08-12 05:46:22 UTC:121.7.242.90(53749):postgres@mytest:[2007]:DETAIL:  parameters: $1 = '1000'
2023-08-12T05:46:22 2023-08-12 05:46:22 UTC:121.7.242.90(53749):postgres@mytest:[2007]:LOG:  duration: 471.569 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.014..0.195 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
2023-08-12T05:46:23 2023-08-12 05:46:23 UTC:121.7.242.90(53749):postgres@mytest:[2007]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:23 2023-08-12 05:46:23 UTC:121.7.242.90(53749):postgres@mytest:[2007]:DETAIL:  parameters: $1 = '7'
2023-08-12T05:46:23 2023-08-12 05:46:23 UTC:121.7.242.90(53749):postgres@mytest:[2007]:LOG:  duration: 0.040 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.018..0.020 rows=1 loops=1)
	  Index Cond: (id = 7)
2023-08-12T05:46:23 2023-08-12 05:46:23 UTC:121.7.242.90(53749):postgres@mytest:[2007]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:23 2023-08-12 05:46:23 UTC:121.7.242.90(53749):postgres@mytest:[2007]:DETAIL:  parameters: $1 = '1000'
2023-08-12T05:46:23 2023-08-12 05:46:23 UTC:121.7.242.90(53749):postgres@mytest:[2007]:LOG:  duration: 0.717 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.015..0.214 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
```

### Test 9: PrepareThreshold1CacheModeForceGeneric + PreparedStatements

#### Sample Code
```java
props.setProperty("ApplicationName", "JDBCConnection: PrepareThreshold1CacheModeForceGeneric");
props.setProperty("options", "-c plan_cache_mode=force_generic_plan -c log_statement=all -c auto_explain.log_analyze=1 -c auto_explain.log_min_duration=0");
props.setProperty("prepareThreshold", "1");
```

#### Output
```sql
2023-08-12T05:46:25 2023-08-12 05:46:25 UTC:121.7.242.90(53752):postgres@mytest:[2015]:LOG:  execute <unnamed>: SET extra_float_digits = 3
2023-08-12T05:46:25 2023-08-12 05:46:25 UTC:121.7.242.90(53752):postgres@mytest:[2015]:LOG:  execute <unnamed>: SET application_name = 'JDBCConnection: PrepareThreshold1CacheModeForceGeneric'
2023-08-12T05:46:26 2023-08-12 05:46:26 UTC:121.7.242.90(53752):postgres@mytest:[2015]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:26 2023-08-12 05:46:26 UTC:121.7.242.90(53752):postgres@mytest:[2015]:DETAIL:  parameters: $1 = '1'
2023-08-12T05:46:26 2023-08-12 05:46:26 UTC:121.7.242.90(53752):postgres@mytest:[2015]:LOG:  duration: 0.024 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.016..0.017 rows=1 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:46:26 2023-08-12 05:46:26 UTC:121.7.242.90(53752):postgres@mytest:[2015]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:26 2023-08-12 05:46:26 UTC:121.7.242.90(53752):postgres@mytest:[2015]:DETAIL:  parameters: $1 = '2'
2023-08-12T05:46:26 2023-08-12 05:46:26 UTC:121.7.242.90(53752):postgres@mytest:[2015]:LOG:  duration: 0.024 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.018..0.020 rows=1 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:46:26 2023-08-12 05:46:26 UTC:121.7.242.90(53752):postgres@mytest:[2015]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:26 2023-08-12 05:46:26 UTC:121.7.242.90(53752):postgres@mytest:[2015]:DETAIL:  parameters: $1 = '3'
2023-08-12T05:46:26 2023-08-12 05:46:26 UTC:121.7.242.90(53752):postgres@mytest:[2015]:LOG:  duration: 0.024 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.019..0.020 rows=1 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:46:26 2023-08-12 05:46:26 UTC:121.7.242.90(53752):postgres@mytest:[2015]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:26 2023-08-12 05:46:26 UTC:121.7.242.90(53752):postgres@mytest:[2015]:DETAIL:  parameters: $1 = '4'
2023-08-12T05:46:26 2023-08-12 05:46:26 UTC:121.7.242.90(53752):postgres@mytest:[2015]:LOG:  duration: 0.025 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.019..0.021 rows=1 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:46:27 2023-08-12 05:46:27 UTC:121.7.242.90(53752):postgres@mytest:[2015]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:27 2023-08-12 05:46:27 UTC:121.7.242.90(53752):postgres@mytest:[2015]:DETAIL:  parameters: $1 = '5'
2023-08-12T05:46:27 2023-08-12 05:46:27 UTC:121.7.242.90(53752):postgres@mytest:[2015]:LOG:  duration: 0.025 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.019..0.020 rows=1 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:46:27 2023-08-12 05:46:27 UTC:121.7.242.90(53752):postgres@mytest:[2015]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:27 2023-08-12 05:46:27 UTC:121.7.242.90(53752):postgres@mytest:[2015]:DETAIL:  parameters: $1 = '6'
2023-08-12T05:46:27 2023-08-12 05:46:27 UTC:121.7.242.90(53752):postgres@mytest:[2015]:LOG:  duration: 0.023 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.017..0.019 rows=1 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:46:27 2023-08-12 05:46:27 UTC:121.7.242.90(53752):postgres@mytest:[2015]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:27 2023-08-12 05:46:27 UTC:121.7.242.90(53752):postgres@mytest:[2015]:DETAIL:  parameters: $1 = '1000'
2023-08-12T05:46:28 2023-08-12 05:46:28 UTC:121.7.242.90(53752):postgres@mytest:[2015]:LOG:  duration: 463.980 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.035..0.253 rows=990 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:46:28 2023-08-12 05:46:28 UTC:121.7.242.90(53752):postgres@mytest:[2015]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:28 2023-08-12 05:46:28 UTC:121.7.242.90(53752):postgres@mytest:[2015]:DETAIL:  parameters: $1 = '7'
2023-08-12T05:46:28 2023-08-12 05:46:28 UTC:121.7.242.90(53752):postgres@mytest:[2015]:LOG:  duration: 0.026 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.020..0.022 rows=1 loops=1)
	  Index Cond: (id = $1)
2023-08-12T05:46:28 2023-08-12 05:46:28 UTC:121.7.242.90(53752):postgres@mytest:[2015]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T05:46:28 2023-08-12 05:46:28 UTC:121.7.242.90(53752):postgres@mytest:[2015]:DETAIL:  parameters: $1 = '1000'
2023-08-12T05:46:28 2023-08-12 05:46:28 UTC:121.7.242.90(53752):postgres@mytest:[2015]:LOG:  duration: 0.606 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Index Scan using t_id_n1 on t  (cost=0.15..10.74 rows=91 width=105) (actual time=0.023..0.197 rows=990 loops=1)
	  Index Cond: (id = $1)
```

#### Special Test
```java
props.setProperty("ApplicationName", "JDBCConnection: PrepareThreshold5CacheModeAuto");
props.setProperty("options", "-c plan_cache_mode=auto -c log_statement=all -c auto_explain.log_analyze=1 -c auto_explain.log_min_duration=0");
props.setProperty("prepareThreshold", "5");

PreparedStatement ps = conn.prepareStatement("SELECT * FROM t WHERE id = ?");

ps.setInt(1, 1);
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
ps.setInt(1, 7);
ps.executeQuery().close();
ps.setInt(1, 8);
ps.executeQuery().close();
ps.setInt(1, 9);
ps.executeQuery().close();
ps.setInt(1, 10);
ps.executeQuery().close();
ps.setInt(1, 7);
ps.executeQuery().close();
ps.setInt(1, 1000);
ps.executeQuery().close();
ps.setInt(1, 7);
ps.executeQuery().close();
ps.setInt(1, 1000);
ps.executeQuery().close(); 

```

```sql
2023-08-12T07:07:37 2023-08-12 07:07:37 UTC:121.7.242.90(58638):postgres@mytest:[5527]:LOG:  execute <unnamed>: SET extra_float_digits = 3
2023-08-12T07:07:37 2023-08-12 07:07:37 UTC:121.7.242.90(58638):postgres@mytest:[5527]:LOG:  execute <unnamed>: SET application_name = 'DefaultJDBCConnection'
2023-08-12T07:07:37 2023-08-12 07:07:37 UTC:121.7.242.90(58638):postgres@mytest:[5527]:LOG:  execute <unnamed>: CREATE TABLE t (id INT, c TEXT)
2023-08-12T07:07:38 2023-08-12 07:07:38 UTC:121.7.242.90(58638):postgres@mytest:[5527]:LOG:  execute <unnamed>: INSERT INTO t SELECT CASE WHEN x<=10 THEN x ELSE 1000 END, RPAD('x',100,'x') FROM generate_series(1,1000) x
2023-08-12T07:07:38 2023-08-12 07:07:38 UTC:121.7.242.90(58638):postgres@mytest:[5527]:LOG:  execute <unnamed>: CREATE INDEX t_id_n1 ON t (id)
2023-08-12T07:07:40 2023-08-12 07:07:40 UTC:121.7.242.90(58647):postgres@mytest:[5531]:LOG:  execute <unnamed>: SET extra_float_digits = 3
2023-08-12T07:07:40 2023-08-12 07:07:40 UTC:121.7.242.90(58647):postgres@mytest:[5531]:LOG:  execute <unnamed>: SET application_name = 'JDBCConnection: PrepareThreshold5CacheModeAuto'
2023-08-12T07:07:41 2023-08-12 07:07:41 UTC:121.7.242.90(58647):postgres@mytest:[5531]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T07:07:41 2023-08-12 07:07:41 UTC:121.7.242.90(58647):postgres@mytest:[5531]:DETAIL:  parameters: $1 = '1'
2023-08-12T07:07:41 2023-08-12 07:07:41 UTC:121.7.242.90(58647):postgres@mytest:[5531]:LOG:  duration: 0.023 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Bitmap Heap Scan on t  (cost=4.19..16.35 rows=5 width=36) (actual time=0.014..0.015 rows=1 loops=1)
	  Recheck Cond: (id = 1)
	  Heap Blocks: exact=1
	  ->  Bitmap Index Scan on t_id_n1  (cost=0.00..4.19 rows=5 width=0) (actual time=0.011..0.011 rows=1 loops=1)
	        Index Cond: (id = 1)
2023-08-12T07:07:41 2023-08-12 07:07:41 UTC:121.7.242.90(58647):postgres@mytest:[5531]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T07:07:41 2023-08-12 07:07:41 UTC:121.7.242.90(58647):postgres@mytest:[5531]:DETAIL:  parameters: $1 = '2'
2023-08-12T07:07:41 2023-08-12 07:07:41 UTC:121.7.242.90(58647):postgres@mytest:[5531]:LOG:  duration: 0.020 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Bitmap Heap Scan on t  (cost=4.19..16.35 rows=5 width=36) (actual time=0.016..0.017 rows=1 loops=1)
	  Recheck Cond: (id = 2)
	  Heap Blocks: exact=1
	  ->  Bitmap Index Scan on t_id_n1  (cost=0.00..4.19 rows=5 width=0) (actual time=0.011..0.011 rows=1 loops=1)
	        Index Cond: (id = 2)
2023-08-12T07:07:41 2023-08-12 07:07:41 UTC:121.7.242.90(58647):postgres@mytest:[5531]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T07:07:41 2023-08-12 07:07:41 UTC:121.7.242.90(58647):postgres@mytest:[5531]:DETAIL:  parameters: $1 = '3'
2023-08-12T07:07:41 2023-08-12 07:07:41 UTC:121.7.242.90(58647):postgres@mytest:[5531]:LOG:  duration: 0.019 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Bitmap Heap Scan on t  (cost=4.19..16.35 rows=5 width=36) (actual time=0.014..0.015 rows=1 loops=1)
	  Recheck Cond: (id = 3)
	  Heap Blocks: exact=1
	  ->  Bitmap Index Scan on t_id_n1  (cost=0.00..4.19 rows=5 width=0) (actual time=0.010..0.010 rows=1 loops=1)
	        Index Cond: (id = 3)
2023-08-12T07:07:41 2023-08-12 07:07:41 UTC:121.7.242.90(58647):postgres@mytest:[5531]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = $1
2023-08-12T07:07:41 2023-08-12 07:07:41 UTC:121.7.242.90(58647):postgres@mytest:[5531]:DETAIL:  parameters: $1 = '4'
2023-08-12T07:07:41 2023-08-12 07:07:41 UTC:121.7.242.90(58647):postgres@mytest:[5531]:LOG:  duration: 0.069 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Bitmap Heap Scan on t  (cost=4.19..16.35 rows=5 width=36) (actual time=0.059..0.061 rows=1 loops=1)
	  Recheck Cond: (id = 4)
	  Heap Blocks: exact=1
	  ->  Bitmap Index Scan on t_id_n1  (cost=0.00..4.19 rows=5 width=0) (actual time=0.049..0.050 rows=1 loops=1)
	        Index Cond: (id = 4)
2023-08-12T07:07:42 2023-08-12 07:07:42 UTC:121.7.242.90(58647):postgres@mytest:[5531]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T07:07:42 2023-08-12 07:07:42 UTC:121.7.242.90(58647):postgres@mytest:[5531]:DETAIL:  parameters: $1 = '5'
2023-08-12T07:07:42 2023-08-12 07:07:42 UTC:121.7.242.90(58647):postgres@mytest:[5531]:LOG:  duration: 0.027 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Bitmap Heap Scan on t  (cost=4.19..16.35 rows=5 width=36) (actual time=0.021..0.023 rows=1 loops=1)
	  Recheck Cond: (id = 5)
	  Heap Blocks: exact=1
	  ->  Bitmap Index Scan on t_id_n1  (cost=0.00..4.19 rows=5 width=0) (actual time=0.017..0.017 rows=1 loops=1)
	        Index Cond: (id = 5)
2023-08-12T07:07:42 2023-08-12 07:07:42 UTC:121.7.242.90(58647):postgres@mytest:[5531]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T07:07:42 2023-08-12 07:07:42 UTC:121.7.242.90(58647):postgres@mytest:[5531]:DETAIL:  parameters: $1 = '6'
2023-08-12T07:07:42 2023-08-12 07:07:42 UTC:121.7.242.90(58647):postgres@mytest:[5531]:LOG:  duration: 0.022 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Bitmap Heap Scan on t  (cost=4.19..16.35 rows=5 width=36) (actual time=0.017..0.018 rows=1 loops=1)
	  Recheck Cond: (id = 6)
	  Heap Blocks: exact=1
	  ->  Bitmap Index Scan on t_id_n1  (cost=0.00..4.19 rows=5 width=0) (actual time=0.011..0.012 rows=1 loops=1)
	        Index Cond: (id = 6)
2023-08-12T07:07:42 2023-08-12 07:07:42 UTC:121.7.242.90(58647):postgres@mytest:[5531]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T07:07:42 2023-08-12 07:07:42 UTC:121.7.242.90(58647):postgres@mytest:[5531]:DETAIL:  parameters: $1 = '7'
2023-08-12T07:07:42 2023-08-12 07:07:42 UTC:121.7.242.90(58647):postgres@mytest:[5531]:LOG:  duration: 0.022 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Bitmap Heap Scan on t  (cost=4.19..16.35 rows=5 width=36) (actual time=0.017..0.018 rows=1 loops=1)
	  Recheck Cond: (id = 7)
	  Heap Blocks: exact=1
	  ->  Bitmap Index Scan on t_id_n1  (cost=0.00..4.19 rows=5 width=0) (actual time=0.010..0.010 rows=1 loops=1)
	        Index Cond: (id = 7)
2023-08-12T07:07:42 2023-08-12 07:07:42 UTC:121.7.242.90(58647):postgres@mytest:[5531]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T07:07:42 2023-08-12 07:07:42 UTC:121.7.242.90(58647):postgres@mytest:[5531]:DETAIL:  parameters: $1 = '8'
2023-08-12T07:07:42 2023-08-12 07:07:42 UTC:121.7.242.90(58647):postgres@mytest:[5531]:LOG:  duration: 0.022 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Bitmap Heap Scan on t  (cost=4.19..16.35 rows=5 width=36) (actual time=0.015..0.016 rows=1 loops=1)
	  Recheck Cond: (id = 8)
	  Heap Blocks: exact=1
	  ->  Bitmap Index Scan on t_id_n1  (cost=0.00..4.19 rows=5 width=0) (actual time=0.011..0.011 rows=1 loops=1)
	        Index Cond: (id = 8)
2023-08-12T07:07:43 2023-08-12 07:07:43 UTC:121.7.242.90(58647):postgres@mytest:[5531]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T07:07:43 2023-08-12 07:07:43 UTC:121.7.242.90(58647):postgres@mytest:[5531]:DETAIL:  parameters: $1 = '9'
2023-08-12T07:07:43 2023-08-12 07:07:43 UTC:121.7.242.90(58647):postgres@mytest:[5531]:LOG:  duration: 0.020 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Bitmap Heap Scan on t  (cost=4.19..16.35 rows=5 width=36) (actual time=0.015..0.016 rows=1 loops=1)
	  Recheck Cond: (id = 9)
	  Heap Blocks: exact=1
	  ->  Bitmap Index Scan on t_id_n1  (cost=0.00..4.19 rows=5 width=0) (actual time=0.010..0.011 rows=1 loops=1)
	        Index Cond: (id = 9)
2023-08-12T07:07:43 2023-08-12 07:07:43 UTC:121.7.242.90(58647):postgres@mytest:[5531]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T07:07:43 2023-08-12 07:07:43 UTC:121.7.242.90(58647):postgres@mytest:[5531]:DETAIL:  parameters: $1 = '10'
2023-08-12T07:07:43 2023-08-12 07:07:43 UTC:121.7.242.90(58647):postgres@mytest:[5531]:LOG:  duration: 0.099 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Bitmap Heap Scan on t  (cost=4.19..16.35 rows=5 width=36) (actual time=0.088..0.090 rows=1 loops=1)
	  Recheck Cond: (id = $1)
	  Heap Blocks: exact=1
	  ->  Bitmap Index Scan on t_id_n1  (cost=0.00..4.19 rows=5 width=0) (actual time=0.023..0.024 rows=1 loops=1)
	        Index Cond: (id = $1)
2023-08-12T07:07:43 2023-08-12 07:07:43 UTC:121.7.242.90(58647):postgres@mytest:[5531]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T07:07:43 2023-08-12 07:07:43 UTC:121.7.242.90(58647):postgres@mytest:[5531]:DETAIL:  parameters: $1 = '7'
2023-08-12T07:07:43 2023-08-12 07:07:43 UTC:121.7.242.90(58647):postgres@mytest:[5531]:LOG:  duration: 0.024 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Bitmap Heap Scan on t  (cost=4.19..16.35 rows=5 width=36) (actual time=0.018..0.019 rows=1 loops=1)
	  Recheck Cond: (id = $1)
	  Heap Blocks: exact=1
	  ->  Bitmap Index Scan on t_id_n1  (cost=0.00..4.19 rows=5 width=0) (actual time=0.013..0.014 rows=1 loops=1)
	        Index Cond: (id = $1)
2023-08-12T07:07:43 2023-08-12 07:07:43 UTC:121.7.242.90(58647):postgres@mytest:[5531]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T07:07:43 2023-08-12 07:07:43 UTC:121.7.242.90(58647):postgres@mytest:[5531]:DETAIL:  parameters: $1 = '1000'
2023-08-12T07:07:44 2023-08-12 07:07:44 UTC:121.7.242.90(58647):postgres@mytest:[5531]:LOG:  duration: 494.028 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Bitmap Heap Scan on t  (cost=4.19..16.35 rows=5 width=36) (actual time=0.060..0.261 rows=990 loops=1)
	  Recheck Cond: (id = $1)
	  Heap Blocks: exact=18
	  ->  Bitmap Index Scan on t_id_n1  (cost=0.00..4.19 rows=5 width=0) (actual time=0.049..0.049 rows=990 loops=1)
	        Index Cond: (id = $1)
2023-08-12T07:07:44 2023-08-12 07:07:44 UTC:121.7.242.90(58647):postgres@mytest:[5531]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T07:07:44 2023-08-12 07:07:44 UTC:121.7.242.90(58647):postgres@mytest:[5531]:DETAIL:  parameters: $1 = '7'
2023-08-12T07:07:44 2023-08-12 07:07:44 UTC:121.7.242.90(58647):postgres@mytest:[5531]:LOG:  duration: 0.022 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Bitmap Heap Scan on t  (cost=4.19..16.35 rows=5 width=36) (actual time=0.017..0.018 rows=1 loops=1)
	  Recheck Cond: (id = $1)
	  Heap Blocks: exact=1
	  ->  Bitmap Index Scan on t_id_n1  (cost=0.00..4.19 rows=5 width=0) (actual time=0.012..0.013 rows=1 loops=1)
	        Index Cond: (id = $1)
2023-08-12T07:07:45 2023-08-12 07:07:45 UTC:121.7.242.90(58647):postgres@mytest:[5531]:LOG:  execute S_1: SELECT * FROM t WHERE id = $1
2023-08-12T07:07:45 2023-08-12 07:07:45 UTC:121.7.242.90(58647):postgres@mytest:[5531]:DETAIL:  parameters: $1 = '1000'
2023-08-12T07:07:45 2023-08-12 07:07:45 UTC:121.7.242.90(58647):postgres@mytest:[5531]:LOG:  duration: 1.142 ms  plan:
	Query Text: SELECT * FROM t WHERE id = $1
	Bitmap Heap Scan on t  (cost=4.19..16.35 rows=5 width=36) (actual time=0.091..0.491 rows=990 loops=1)
	  Recheck Cond: (id = $1)
	  Heap Blocks: exact=18
	  ->  Bitmap Index Scan on t_id_n1  (cost=0.00..4.19 rows=5 width=0) (actual time=0.079..0.079 rows=990 loops=1)
	        Index Cond: (id = $1)
2023-08-12T07:07:47 2023-08-12 07:07:47 UTC:121.7.242.90(58652):postgres@mytest:[5539]:LOG:  execute <unnamed>: SET extra_float_digits = 3
2023-08-12T07:07:47 2023-08-12 07:07:47 UTC:121.7.242.90(58652):postgres@mytest:[5539]:LOG:  execute <unnamed>: SET application_name = 'DefaultJDBCConnection'
2023-08-12T07:07:47 2023-08-12 07:07:47 UTC:121.7.242.90(58652):postgres@mytest:[5539]:LOG:  execute <unnamed>: DROP TABLE t
```
