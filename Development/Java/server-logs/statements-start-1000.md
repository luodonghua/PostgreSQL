### Prepare Statements:
```java
Statement stmt = conn.createStatement();
stmt.execute("SELECT * FROM t WHERE id = 1000");  
stmt.execute("SELECT * FROM t WHERE id = 2");  
stmt.execute("SELECT * FROM t WHERE id = 3");
stmt.execute("SELECT * FROM t WHERE id = 4");
stmt.execute("SELECT * FROM t WHERE id = 5");
stmt.execute("SELECT * FROM t WHERE id = 6");
stmt.execute("SELECT * FROM t WHERE id = 1000");
stmt.execute("SELECT * FROM t WHERE id = 7");
stmt.execute("SELECT * FROM t WHERE id = 1000");
stmt.close();
```

#### Result

| Config | `1000` | `2` | `3` | `4` | `5` | `6` | `1000` | `7` | `1000`|
| :-- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
|28.PrepareThreshold5CacheModeAuto|SEQ|IS|IS|IS|IS|IS|SEQ|IS|SEQ|
|29.PrepareThreshold5CacheModeForceCustom|SEQ|IS|IS|IS|IS|IS|SEQ|IS|SEQ|
|30.PrepareThreshold5CacheModeForceGeneric|SEQ|IS|IS|IS|IS|IS|SEQ|IS|SEQ|
|31.PrepareThreshold10CacheModeAuto|SEQ|IS|IS|IS|IS|IS|SEQ|IS|SEQ|
|32.PrepareThreshold10CacheModeForceCustom|SEQ|IS|IS|IS|IS|IS|SEQ|IS|SEQ|
|33.PrepareThreshold10CacheModeForceGeneric|SEQ|IS|IS|IS|IS|IS|SEQ|IS|SEQ|
|34.PrepareThreshold1CacheModeAuto|SEQ|IS|IS|IS|IS|IS|SEQ|IS|SEQ|
|35.PrepareThreshold1CacheModeForceCustom|SEQ|IS|IS|IS|IS|IS|SEQ|IS|SEQ|
|36.PrepareThreshold1CacheModeForceGeneric|SEQ|IS|IS|IS|IS|IS|SEQ|IS|SEQ|

- BIS: Bitmap Index Scan
- IS: Index Scan
- SEQ: Seq Scan

### Test 28: PrepareThreshold5CacheModeAuto + StatementsStart1000

#### Sample Code
```java
 props.setProperty("ApplicationName", "JDBCConnection: PrepareThreshold5CacheModeAuto");
props.setProperty("options", "-c plan_cache_mode=auto -c log_statement=all -c auto_explain.log_analyze=1 -c auto_explain.log_min_duration=0");
props.setProperty("prepareThreshold", "5");
```

#### Output
```sql
2023-08-12T05:48:06 2023-08-12 05:48:06 UTC:121.7.242.90(53900):postgres@mytest:[2100]:LOG:  execute <unnamed>: SET extra_float_digits = 3
2023-08-12T05:48:07 2023-08-12 05:48:07 UTC:121.7.242.90(53900):postgres@mytest:[2100]:LOG:  execute <unnamed>: SET application_name = 'JDBCConnection: PrepareThreshold5CacheModeAuto'
2023-08-12T05:48:07 2023-08-12 05:48:07 UTC:121.7.242.90(53900):postgres@mytest:[2100]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 1000
2023-08-12T05:48:07 2023-08-12 05:48:07 UTC:121.7.242.90(53900):postgres@mytest:[2100]:LOG:  duration: 493.694 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 1000
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.012..0.183 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
2023-08-12T05:48:08 2023-08-12 05:48:08 UTC:121.7.242.90(53900):postgres@mytest:[2100]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 2
2023-08-12T05:48:08 2023-08-12 05:48:08 UTC:121.7.242.90(53900):postgres@mytest:[2100]:LOG:  duration: 0.029 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 2
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.022..0.024 rows=1 loops=1)
	  Index Cond: (id = 2)
2023-08-12T05:48:08 2023-08-12 05:48:08 UTC:121.7.242.90(53900):postgres@mytest:[2100]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 3
2023-08-12T05:48:08 2023-08-12 05:48:08 UTC:121.7.242.90(53900):postgres@mytest:[2100]:LOG:  duration: 0.021 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 3
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.014..0.016 rows=1 loops=1)
	  Index Cond: (id = 3)
2023-08-12T05:48:08 2023-08-12 05:48:08 UTC:121.7.242.90(53900):postgres@mytest:[2100]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 4
2023-08-12T05:48:08 2023-08-12 05:48:08 UTC:121.7.242.90(53900):postgres@mytest:[2100]:LOG:  duration: 0.020 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 4
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.014..0.016 rows=1 loops=1)
	  Index Cond: (id = 4)
2023-08-12T05:48:09 2023-08-12 05:48:09 UTC:121.7.242.90(53900):postgres@mytest:[2100]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 5
2023-08-12T05:48:09 2023-08-12 05:48:09 UTC:121.7.242.90(53900):postgres@mytest:[2100]:LOG:  duration: 0.022 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 5
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.015..0.016 rows=1 loops=1)
	  Index Cond: (id = 5)
2023-08-12T05:48:09 2023-08-12 05:48:09 UTC:121.7.242.90(53900):postgres@mytest:[2100]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 6
2023-08-12T05:48:09 2023-08-12 05:48:09 UTC:121.7.242.90(53900):postgres@mytest:[2100]:LOG:  duration: 0.022 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 6
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.015..0.017 rows=1 loops=1)
	  Index Cond: (id = 6)
2023-08-12T05:48:09 2023-08-12 05:48:09 UTC:121.7.242.90(53900):postgres@mytest:[2100]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 7
2023-08-12T05:48:09 2023-08-12 05:48:09 UTC:121.7.242.90(53900):postgres@mytest:[2100]:LOG:  duration: 0.019 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 7
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.013..0.014 rows=1 loops=1)
	  Index Cond: (id = 7)
2023-08-12T05:48:10 2023-08-12 05:48:10 UTC:121.7.242.90(53900):postgres@mytest:[2100]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 1000
2023-08-12T05:48:10 2023-08-12 05:48:10 UTC:121.7.242.90(53900):postgres@mytest:[2100]:LOG:  duration: 0.803 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 1000
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.014..0.224 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10

```


### Test 29: PrepareThreshold5CacheModeForceCustom + StatementsStart1000

#### Sample Code
```java
props.setProperty("ApplicationName", "JDBCConnection: PrepareThreshold5CacheModeForceCustom");
props.setProperty("options", "-c plan_cache_mode=force_custom_plan -c log_statement=all -c auto_explain.log_analyze=1 -c auto_explain.log_min_duration=0");
props.setProperty("prepareThreshold", "5");
```

#### Output
```sql
2023-08-12T05:48:12 2023-08-12 05:48:12 UTC:121.7.242.90(53910):postgres@mytest:[2109]:LOG:  execute <unnamed>: SET extra_float_digits = 3
2023-08-12T05:48:12 2023-08-12 05:48:12 UTC:121.7.242.90(53910):postgres@mytest:[2109]:LOG:  execute <unnamed>: SET application_name = 'JDBCConnection: PrepareThreshold5CacheModeForceCustom'
2023-08-12T05:48:12 2023-08-12 05:48:12 UTC:121.7.242.90(53910):postgres@mytest:[2109]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 1000
2023-08-12T05:48:13 2023-08-12 05:48:13 UTC:121.7.242.90(53910):postgres@mytest:[2109]:LOG:  duration: 517.621 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 1000
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.014..0.212 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
2023-08-12T05:48:13 2023-08-12 05:48:13 UTC:121.7.242.90(53910):postgres@mytest:[2109]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 2
2023-08-12T05:48:13 2023-08-12 05:48:13 UTC:121.7.242.90(53910):postgres@mytest:[2109]:LOG:  duration: 0.029 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 2
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.023..0.024 rows=1 loops=1)
	  Index Cond: (id = 2)
2023-08-12T05:48:13 2023-08-12 05:48:13 UTC:121.7.242.90(53910):postgres@mytest:[2109]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 3
2023-08-12T05:48:13 2023-08-12 05:48:13 UTC:121.7.242.90(53910):postgres@mytest:[2109]:LOG:  duration: 0.066 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 3
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.053..0.056 rows=1 loops=1)
	  Index Cond: (id = 3)
2023-08-12T05:48:14 2023-08-12 05:48:14 UTC:121.7.242.90(53910):postgres@mytest:[2109]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 4
2023-08-12T05:48:14 2023-08-12 05:48:14 UTC:121.7.242.90(53910):postgres@mytest:[2109]:LOG:  duration: 0.020 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 4
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.014..0.016 rows=1 loops=1)
	  Index Cond: (id = 4)
2023-08-12T05:48:14 2023-08-12 05:48:14 UTC:121.7.242.90(53910):postgres@mytest:[2109]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 5
2023-08-12T05:48:14 2023-08-12 05:48:14 UTC:121.7.242.90(53910):postgres@mytest:[2109]:LOG:  duration: 0.022 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 5
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.015..0.017 rows=1 loops=1)
	  Index Cond: (id = 5)
2023-08-12T05:48:14 2023-08-12 05:48:14 UTC:121.7.242.90(53910):postgres@mytest:[2109]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 6
2023-08-12T05:48:14 2023-08-12 05:48:14 UTC:121.7.242.90(53910):postgres@mytest:[2109]:LOG:  duration: 0.020 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 6
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.013..0.015 rows=1 loops=1)
	  Index Cond: (id = 6)
2023-08-12T05:48:15 2023-08-12 05:48:15 UTC:121.7.242.90(53910):postgres@mytest:[2109]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 7
2023-08-12T05:48:15 2023-08-12 05:48:15 UTC:121.7.242.90(53910):postgres@mytest:[2109]:LOG:  duration: 0.022 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 7
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.015..0.017 rows=1 loops=1)
	  Index Cond: (id = 7)
2023-08-12T05:48:15 2023-08-12 05:48:15 UTC:121.7.242.90(53910):postgres@mytest:[2109]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 1000
2023-08-12T05:48:15 2023-08-12 05:48:15 UTC:121.7.242.90(53910):postgres@mytest:[2109]:LOG:  duration: 0.525 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 1000
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.014..0.179 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
```


### Test 30: PrepareThreshold5CacheModeForceGeneric + StatementsStart1000

#### Sample Code
```java
props.setProperty("ApplicationName", "JDBCConnection: PrepareThreshold5CacheModeForceGeneric");
props.setProperty("options", "-c plan_cache_mode=force_generic_plan -c log_statement=all -c auto_explain.log_analyze=1 -c auto_explain.log_min_duration=0");
props.setProperty("prepareThreshold", "5");
```

#### Output
```sql
2023-08-12T05:48:17 2023-08-12 05:48:17 UTC:121.7.242.90(53916):postgres@mytest:[2112]:LOG:  execute <unnamed>: SET extra_float_digits = 3
2023-08-12T05:48:17 2023-08-12 05:48:17 UTC:121.7.242.90(53916):postgres@mytest:[2112]:LOG:  execute <unnamed>: SET application_name = 'JDBCConnection: PrepareThreshold5CacheModeForceGeneric'
2023-08-12T05:48:18 2023-08-12 05:48:18 UTC:121.7.242.90(53916):postgres@mytest:[2112]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 1000
2023-08-12T05:48:18 2023-08-12 05:48:18 UTC:121.7.242.90(53916):postgres@mytest:[2112]:LOG:  duration: 544.432 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 1000
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.015..0.274 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
2023-08-12T05:48:19 2023-08-12 05:48:19 UTC:121.7.242.90(53916):postgres@mytest:[2112]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 2
2023-08-12T05:48:19 2023-08-12 05:48:19 UTC:121.7.242.90(53916):postgres@mytest:[2112]:LOG:  duration: 0.028 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 2
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.021..0.023 rows=1 loops=1)
	  Index Cond: (id = 2)
2023-08-12T05:48:19 2023-08-12 05:48:19 UTC:121.7.242.90(53916):postgres@mytest:[2112]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 3
2023-08-12T05:48:19 2023-08-12 05:48:19 UTC:121.7.242.90(53916):postgres@mytest:[2112]:LOG:  duration: 0.021 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 3
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.015..0.016 rows=1 loops=1)
	  Index Cond: (id = 3)
2023-08-12T05:48:19 2023-08-12 05:48:19 UTC:121.7.242.90(53916):postgres@mytest:[2112]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 4
2023-08-12T05:48:19 2023-08-12 05:48:19 UTC:121.7.242.90(53916):postgres@mytest:[2112]:LOG:  duration: 0.021 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 4
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.015..0.016 rows=1 loops=1)
	  Index Cond: (id = 4)
2023-08-12T05:48:19 2023-08-12 05:48:19 UTC:121.7.242.90(53916):postgres@mytest:[2112]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 5
2023-08-12T05:48:19 2023-08-12 05:48:19 UTC:121.7.242.90(53916):postgres@mytest:[2112]:LOG:  duration: 0.021 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 5
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.014..0.016 rows=1 loops=1)
	  Index Cond: (id = 5)
2023-08-12T05:48:20 2023-08-12 05:48:20 UTC:121.7.242.90(53916):postgres@mytest:[2112]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 6
2023-08-12T05:48:20 2023-08-12 05:48:20 UTC:121.7.242.90(53916):postgres@mytest:[2112]:LOG:  duration: 0.022 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 6
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.015..0.017 rows=1 loops=1)
	  Index Cond: (id = 6)
2023-08-12T05:48:20 2023-08-12 05:48:20 UTC:121.7.242.90(53916):postgres@mytest:[2112]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 7
2023-08-12T05:48:20 2023-08-12 05:48:20 UTC:121.7.242.90(53916):postgres@mytest:[2112]:LOG:  duration: 0.024 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 7
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.014..0.017 rows=1 loops=1)
	  Index Cond: (id = 7)
2023-08-12T05:48:20 2023-08-12 05:48:20 UTC:121.7.242.90(53916):postgres@mytest:[2112]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 1000
2023-08-12T05:48:20 2023-08-12 05:48:20 UTC:121.7.242.90(53916):postgres@mytest:[2112]:LOG:  duration: 0.543 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 1000
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.014..0.155 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
```



### Test 31: PrepareThreshold10CacheModeAuto + StatementsStart1000

#### Sample Code
```java
props.setProperty("ApplicationName", "JDBCConnection: PrepareThreshold10CacheModeAuto");
props.setProperty("options", "-c plan_cache_mode=auto -c log_statement=all -c auto_explain.log_analyze=1 -c auto_explain.log_min_duration=0");
props.setProperty("prepareThreshold", "10");
```

#### Output
```sql
2023-08-12T05:48:22 2023-08-12 05:48:22 UTC:121.7.242.90(53922):postgres@mytest:[2115]:LOG:  execute <unnamed>: SET extra_float_digits = 3
2023-08-12T05:48:22 2023-08-12 05:48:22 UTC:121.7.242.90(53922):postgres@mytest:[2115]:LOG:  execute <unnamed>: SET application_name = 'JDBCConnection: PrepareThreshold10CacheModeAuto'
2023-08-12T05:48:23 2023-08-12 05:48:23 UTC:121.7.242.90(53922):postgres@mytest:[2115]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 1000
2023-08-12T05:48:23 2023-08-12 05:48:23 UTC:121.7.242.90(53922):postgres@mytest:[2115]:LOG:  duration: 486.767 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 1000
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.013..0.176 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
2023-08-12T05:48:24 2023-08-12 05:48:24 UTC:121.7.242.90(53922):postgres@mytest:[2115]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 2
2023-08-12T05:48:24 2023-08-12 05:48:24 UTC:121.7.242.90(53922):postgres@mytest:[2115]:LOG:  duration: 0.030 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 2
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.023..0.025 rows=1 loops=1)
	  Index Cond: (id = 2)
2023-08-12T05:48:24 2023-08-12 05:48:24 UTC:121.7.242.90(53922):postgres@mytest:[2115]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 3
2023-08-12T05:48:24 2023-08-12 05:48:24 UTC:121.7.242.90(53922):postgres@mytest:[2115]:LOG:  duration: 0.020 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 3
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.013..0.015 rows=1 loops=1)
	  Index Cond: (id = 3)
2023-08-12T05:48:24 2023-08-12 05:48:24 UTC:121.7.242.90(53922):postgres@mytest:[2115]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 4
2023-08-12T05:48:24 2023-08-12 05:48:24 UTC:121.7.242.90(53922):postgres@mytest:[2115]:LOG:  duration: 0.020 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 4
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.013..0.015 rows=1 loops=1)
	  Index Cond: (id = 4)
2023-08-12T05:48:24 2023-08-12 05:48:24 UTC:121.7.242.90(53922):postgres@mytest:[2115]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 5
2023-08-12T05:48:24 2023-08-12 05:48:24 UTC:121.7.242.90(53922):postgres@mytest:[2115]:LOG:  duration: 0.020 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 5
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.014..0.015 rows=1 loops=1)
	  Index Cond: (id = 5)
2023-08-12T05:48:25 2023-08-12 05:48:25 UTC:121.7.242.90(53922):postgres@mytest:[2115]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 6
2023-08-12T05:48:25 2023-08-12 05:48:25 UTC:121.7.242.90(53922):postgres@mytest:[2115]:LOG:  duration: 0.023 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 6
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.016..0.018 rows=1 loops=1)
	  Index Cond: (id = 6)
2023-08-12T05:48:25 2023-08-12 05:48:25 UTC:121.7.242.90(53922):postgres@mytest:[2115]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 7
2023-08-12T05:48:25 2023-08-12 05:48:25 UTC:121.7.242.90(53922):postgres@mytest:[2115]:LOG:  duration: 0.022 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 7
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.015..0.017 rows=1 loops=1)
	  Index Cond: (id = 7)
2023-08-12T05:48:25 2023-08-12 05:48:25 UTC:121.7.242.90(53922):postgres@mytest:[2115]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 1000
2023-08-12T05:48:25 2023-08-12 05:48:25 UTC:121.7.242.90(53922):postgres@mytest:[2115]:LOG:  duration: 0.507 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 1000
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.014..0.154 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
```



### Test 32: PrepareThreshold10CacheModeForceCustom + StatementsStart1000

#### Sample Code
```java
props.setProperty("ApplicationName", "JDBCConnection: PrepareThreshold10CacheModeForceCustom");
props.setProperty("options", "-c plan_cache_mode=force_custom_plan -c log_statement=all -c auto_explain.log_analyze=1 -c auto_explain.log_min_duration=0");
props.setProperty("prepareThreshold", "10");
```

#### Output
```sql
2023-08-12T05:48:27 2023-08-12 05:48:27 UTC:121.7.242.90(53929):postgres@mytest:[2123]:LOG:  execute <unnamed>: SET extra_float_digits = 3
2023-08-12T05:48:27 2023-08-12 05:48:27 UTC:121.7.242.90(53929):postgres@mytest:[2123]:LOG:  execute <unnamed>: SET application_name = 'JDBCConnection: PrepareThreshold10CacheModeForceCustom'
2023-08-12T05:48:28 2023-08-12 05:48:28 UTC:121.7.242.90(53929):postgres@mytest:[2123]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 1000
2023-08-12T05:48:28 2023-08-12 05:48:28 UTC:121.7.242.90(53929):postgres@mytest:[2123]:LOG:  duration: 521.210 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 1000
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.012..0.177 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
2023-08-12T05:48:29 2023-08-12 05:48:29 UTC:121.7.242.90(53929):postgres@mytest:[2123]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 2
2023-08-12T05:48:29 2023-08-12 05:48:29 UTC:121.7.242.90(53929):postgres@mytest:[2123]:LOG:  duration: 0.027 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 2
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.021..0.023 rows=1 loops=1)
	  Index Cond: (id = 2)
2023-08-12T05:48:29 2023-08-12 05:48:29 UTC:121.7.242.90(53929):postgres@mytest:[2123]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 3
2023-08-12T05:48:29 2023-08-12 05:48:29 UTC:121.7.242.90(53929):postgres@mytest:[2123]:LOG:  duration: 0.020 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 3
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.014..0.015 rows=1 loops=1)
	  Index Cond: (id = 3)
2023-08-12T05:48:29 2023-08-12 05:48:29 UTC:121.7.242.90(53929):postgres@mytest:[2123]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 4
2023-08-12T05:48:29 2023-08-12 05:48:29 UTC:121.7.242.90(53929):postgres@mytest:[2123]:LOG:  duration: 0.020 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 4
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.013..0.015 rows=1 loops=1)
	  Index Cond: (id = 4)
2023-08-12T05:48:29 2023-08-12 05:48:29 UTC:121.7.242.90(53929):postgres@mytest:[2123]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 5
2023-08-12T05:48:29 2023-08-12 05:48:29 UTC:121.7.242.90(53929):postgres@mytest:[2123]:LOG:  duration: 0.024 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 5
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.017..0.019 rows=1 loops=1)
	  Index Cond: (id = 5)
2023-08-12T05:48:30 2023-08-12 05:48:30 UTC:121.7.242.90(53929):postgres@mytest:[2123]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 6
2023-08-12T05:48:30 2023-08-12 05:48:30 UTC:121.7.242.90(53929):postgres@mytest:[2123]:LOG:  duration: 0.020 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 6
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.014..0.016 rows=1 loops=1)
	  Index Cond: (id = 6)
2023-08-12T05:48:30 2023-08-12 05:48:30 UTC:121.7.242.90(53929):postgres@mytest:[2123]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 7
2023-08-12T05:48:30 2023-08-12 05:48:30 UTC:121.7.242.90(53929):postgres@mytest:[2123]:LOG:  duration: 0.022 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 7
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.015..0.016 rows=1 loops=1)
	  Index Cond: (id = 7)
2023-08-12T05:48:30 2023-08-12 05:48:30 UTC:121.7.242.90(53929):postgres@mytest:[2123]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 1000
2023-08-12T05:48:30 2023-08-12 05:48:30 UTC:121.7.242.90(53929):postgres@mytest:[2123]:LOG:  duration: 0.519 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 1000
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.013..0.136 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
```



### Test 33: PrepareThreshold10CacheModeForceGeneric + StatementsStart1000

#### Sample Code
```java
props.setProperty("ApplicationName", "JDBCConnection: PrepareThreshold10CacheModeForceGeneric");
props.setProperty("options", "-c plan_cache_mode=force_generic_plan -c log_statement=all -c auto_explain.log_analyze=1 -c auto_explain.log_min_duration=0");
props.setProperty("prepareThreshold", "10");
```

#### Output
```sql
2023-08-12T05:48:32 2023-08-12 05:48:32 UTC:121.7.242.90(53938):postgres@mytest:[2125]:LOG:  execute <unnamed>: SET extra_float_digits = 3
2023-08-12T05:48:32 2023-08-12 05:48:32 UTC:121.7.242.90(53938):postgres@mytest:[2125]:LOG:  execute <unnamed>: SET application_name = 'JDBCConnection: PrepareThreshold10CacheModeForceGeneric'
2023-08-12T05:48:33 2023-08-12 05:48:33 UTC:121.7.242.90(53938):postgres@mytest:[2125]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 1000
2023-08-12T05:48:33 2023-08-12 05:48:33 UTC:121.7.242.90(53938):postgres@mytest:[2125]:LOG:  duration: 484.143 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 1000
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.013..0.167 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
2023-08-12T05:48:34 2023-08-12 05:48:34 UTC:121.7.242.90(53938):postgres@mytest:[2125]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 2
2023-08-12T05:48:34 2023-08-12 05:48:34 UTC:121.7.242.90(53938):postgres@mytest:[2125]:LOG:  duration: 0.029 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 2
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.022..0.024 rows=1 loops=1)
	  Index Cond: (id = 2)
2023-08-12T05:48:34 2023-08-12 05:48:34 UTC:121.7.242.90(53938):postgres@mytest:[2125]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 3
2023-08-12T05:48:34 2023-08-12 05:48:34 UTC:121.7.242.90(53938):postgres@mytest:[2125]:LOG:  duration: 0.020 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 3
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.014..0.015 rows=1 loops=1)
	  Index Cond: (id = 3)
2023-08-12T05:48:34 2023-08-12 05:48:34 UTC:121.7.242.90(53938):postgres@mytest:[2125]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 4
2023-08-12T05:48:34 2023-08-12 05:48:34 UTC:121.7.242.90(53938):postgres@mytest:[2125]:LOG:  duration: 0.038 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 4
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.031..0.033 rows=1 loops=1)
	  Index Cond: (id = 4)
2023-08-12T05:48:34 2023-08-12 05:48:34 UTC:121.7.242.90(53938):postgres@mytest:[2125]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 5
2023-08-12T05:48:34 2023-08-12 05:48:34 UTC:121.7.242.90(53938):postgres@mytest:[2125]:LOG:  duration: 0.057 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 5
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.016..0.018 rows=1 loops=1)
	  Index Cond: (id = 5)
2023-08-12T05:48:35 2023-08-12 05:48:35 UTC:121.7.242.90(53938):postgres@mytest:[2125]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 6
2023-08-12T05:48:35 2023-08-12 05:48:35 UTC:121.7.242.90(53938):postgres@mytest:[2125]:LOG:  duration: 0.023 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 6
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.017..0.018 rows=1 loops=1)
	  Index Cond: (id = 6)
2023-08-12T05:48:35 2023-08-12 05:48:35 UTC:121.7.242.90(53938):postgres@mytest:[2125]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 7
2023-08-12T05:48:35 2023-08-12 05:48:35 UTC:121.7.242.90(53938):postgres@mytest:[2125]:LOG:  duration: 0.021 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 7
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.015..0.016 rows=1 loops=1)
	  Index Cond: (id = 7)
2023-08-12T05:48:35 2023-08-12 05:48:35 UTC:121.7.242.90(53938):postgres@mytest:[2125]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 1000
2023-08-12T05:48:35 2023-08-12 05:48:35 UTC:121.7.242.90(53938):postgres@mytest:[2125]:LOG:  duration: 0.525 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 1000
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.014..0.157 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
```


### Test 34: PrepareThreshold1CacheModeAuto + StatementsStart1000

#### Sample Code
```java
props.setProperty("ApplicationName", "JDBCConnection: PrepareThreshold1CacheModeAuto");
props.setProperty("options", "-c plan_cache_mode=auto -c log_statement=all -c auto_explain.log_analyze=1 -c auto_explain.log_min_duration=0");
props.setProperty("prepareThreshold", "1");
```

#### Output
```sql
2023-08-12T05:48:37 2023-08-12 05:48:37 UTC:121.7.242.90(53946):postgres@mytest:[2128]:LOG:  execute <unnamed>: SET extra_float_digits = 3
2023-08-12T05:48:37 2023-08-12 05:48:37 UTC:121.7.242.90(53946):postgres@mytest:[2128]:LOG:  execute <unnamed>: SET application_name = 'JDBCConnection: PrepareThreshold1CacheModeAuto'
2023-08-12T05:48:38 2023-08-12 05:48:38 UTC:121.7.242.90(53946):postgres@mytest:[2128]:LOG:  execute S_1: SELECT * FROM t WHERE id = 1000
2023-08-12T05:48:38 2023-08-12 05:48:38 UTC:121.7.242.90(53946):postgres@mytest:[2128]:LOG:  duration: 486.576 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 1000
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.019..0.171 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
2023-08-12T05:48:39 2023-08-12 05:48:39 UTC:121.7.242.90(53946):postgres@mytest:[2128]:LOG:  execute S_2: SELECT * FROM t WHERE id = 2
2023-08-12T05:48:39 2023-08-12 05:48:39 UTC:121.7.242.90(53946):postgres@mytest:[2128]:LOG:  duration: 0.029 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 2
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.022..0.023 rows=1 loops=1)
	  Index Cond: (id = 2)
2023-08-12T05:48:39 2023-08-12 05:48:39 UTC:121.7.242.90(53946):postgres@mytest:[2128]:LOG:  execute S_3: SELECT * FROM t WHERE id = 3
2023-08-12T05:48:39 2023-08-12 05:48:39 UTC:121.7.242.90(53946):postgres@mytest:[2128]:LOG:  duration: 0.024 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 3
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.017..0.018 rows=1 loops=1)
	  Index Cond: (id = 3)
2023-08-12T05:48:39 2023-08-12 05:48:39 UTC:121.7.242.90(53946):postgres@mytest:[2128]:LOG:  execute S_4: SELECT * FROM t WHERE id = 4
2023-08-12T05:48:39 2023-08-12 05:48:39 UTC:121.7.242.90(53946):postgres@mytest:[2128]:LOG:  duration: 0.026 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 4
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.020..0.022 rows=1 loops=1)
	  Index Cond: (id = 4)
2023-08-12T05:48:39 2023-08-12 05:48:39 UTC:121.7.242.90(53946):postgres@mytest:[2128]:LOG:  execute S_5: SELECT * FROM t WHERE id = 5
2023-08-12T05:48:39 2023-08-12 05:48:39 UTC:121.7.242.90(53946):postgres@mytest:[2128]:LOG:  duration: 0.032 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 5
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.025..0.027 rows=1 loops=1)
	  Index Cond: (id = 5)
2023-08-12T05:48:40 2023-08-12 05:48:40 UTC:121.7.242.90(53946):postgres@mytest:[2128]:LOG:  execute S_6: SELECT * FROM t WHERE id = 6
2023-08-12T05:48:40 2023-08-12 05:48:40 UTC:121.7.242.90(53946):postgres@mytest:[2128]:LOG:  duration: 0.026 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 6
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.019..0.021 rows=1 loops=1)
	  Index Cond: (id = 6)
2023-08-12T05:48:40 2023-08-12 05:48:40 UTC:121.7.242.90(53946):postgres@mytest:[2128]:LOG:  execute S_7: SELECT * FROM t WHERE id = 7
2023-08-12T05:48:40 2023-08-12 05:48:40 UTC:121.7.242.90(53946):postgres@mytest:[2128]:LOG:  duration: 0.025 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 7
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.018..0.019 rows=1 loops=1)
	  Index Cond: (id = 7)
2023-08-12T05:48:40 2023-08-12 05:48:40 UTC:121.7.242.90(53946):postgres@mytest:[2128]:LOG:  execute S_8: SELECT * FROM t WHERE id = 1000
2023-08-12T05:48:40 2023-08-12 05:48:40 UTC:121.7.242.90(53946):postgres@mytest:[2128]:LOG:  duration: 0.560 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 1000
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.014..0.150 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
```

### Test 35: PrepareThreshold1CacheModeForceCustom + StatementsStart1000

#### Sample Code
```java
props.setProperty("ApplicationName", "JDBCConnection: PrepareThreshold1CacheModeForceCustom");
props.setProperty("options", "-c plan_cache_mode=force_custom_plan -c log_statement=all -c auto_explain.log_analyze=1 -c auto_explain.log_min_duration=0");
props.setProperty("prepareThreshold", "1");
```

#### Output
```sql
2023-08-12T05:48:42 2023-08-12 05:48:42 UTC:121.7.242.90(53952):postgres@mytest:[2136]:LOG:  execute <unnamed>: SET extra_float_digits = 3
2023-08-12T05:48:42 2023-08-12 05:48:42 UTC:121.7.242.90(53952):postgres@mytest:[2136]:LOG:  execute <unnamed>: SET application_name = 'JDBCConnection: PrepareThreshold1CacheModeForceCustom'
2023-08-12T05:48:43 2023-08-12 05:48:43 UTC:121.7.242.90(53952):postgres@mytest:[2136]:LOG:  execute S_1: SELECT * FROM t WHERE id = 1000
2023-08-12T05:48:43 2023-08-12 05:48:43 UTC:121.7.242.90(53952):postgres@mytest:[2136]:LOG:  duration: 505.901 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 1000
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.014..0.164 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
2023-08-12T05:48:44 2023-08-12 05:48:44 UTC:121.7.242.90(53952):postgres@mytest:[2136]:LOG:  execute S_2: SELECT * FROM t WHERE id = 2
2023-08-12T05:48:44 2023-08-12 05:48:44 UTC:121.7.242.90(53952):postgres@mytest:[2136]:LOG:  duration: 0.031 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 2
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.023..0.025 rows=1 loops=1)
	  Index Cond: (id = 2)
2023-08-12T05:48:44 2023-08-12 05:48:44 UTC:121.7.242.90(53952):postgres@mytest:[2136]:LOG:  execute S_3: SELECT * FROM t WHERE id = 3
2023-08-12T05:48:44 2023-08-12 05:48:44 UTC:121.7.242.90(53952):postgres@mytest:[2136]:LOG:  duration: 0.027 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 3
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.019..0.020 rows=1 loops=1)
	  Index Cond: (id = 3)
2023-08-12T05:48:44 2023-08-12 05:48:44 UTC:121.7.242.90(53952):postgres@mytest:[2136]:LOG:  execute S_4: SELECT * FROM t WHERE id = 4
2023-08-12T05:48:44 2023-08-12 05:48:44 UTC:121.7.242.90(53952):postgres@mytest:[2136]:LOG:  duration: 0.031 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 4
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.024..0.026 rows=1 loops=1)
	  Index Cond: (id = 4)
2023-08-12T05:48:45 2023-08-12 05:48:45 UTC:121.7.242.90(53952):postgres@mytest:[2136]:LOG:  execute S_5: SELECT * FROM t WHERE id = 5
2023-08-12T05:48:45 2023-08-12 05:48:45 UTC:121.7.242.90(53952):postgres@mytest:[2136]:LOG:  duration: 0.032 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 5
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.024..0.026 rows=1 loops=1)
	  Index Cond: (id = 5)
2023-08-12T05:48:45 2023-08-12 05:48:45 UTC:121.7.242.90(53952):postgres@mytest:[2136]:LOG:  execute S_6: SELECT * FROM t WHERE id = 6
2023-08-12T05:48:45 2023-08-12 05:48:45 UTC:121.7.242.90(53952):postgres@mytest:[2136]:LOG:  duration: 0.023 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 6
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.016..0.018 rows=1 loops=1)
	  Index Cond: (id = 6)
2023-08-12T05:48:45 2023-08-12 05:48:45 UTC:121.7.242.90(53952):postgres@mytest:[2136]:LOG:  execute S_7: SELECT * FROM t WHERE id = 7
2023-08-12T05:48:45 2023-08-12 05:48:45 UTC:121.7.242.90(53952):postgres@mytest:[2136]:LOG:  duration: 0.023 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 7
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.017..0.018 rows=1 loops=1)
	  Index Cond: (id = 7)
2023-08-12T05:48:45 2023-08-12 05:48:45 UTC:121.7.242.90(53952):postgres@mytest:[2136]:LOG:  execute S_8: SELECT * FROM t WHERE id = 1000
2023-08-12T05:48:45 2023-08-12 05:48:45 UTC:121.7.242.90(53952):postgres@mytest:[2136]:LOG:  duration: 0.623 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 1000
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.013..0.157 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
```

### Test 36: PrepareThreshold1CacheModeForceGeneric + StatementsStart1000

#### Sample Code
```java
props.setProperty("ApplicationName", "JDBCConnection: PrepareThreshold1CacheModeForceGeneric");
props.setProperty("options", "-c plan_cache_mode=force_generic_plan -c log_statement=all -c auto_explain.log_analyze=1 -c auto_explain.log_min_duration=0");
props.setProperty("prepareThreshold", "1");
```

#### Output
```sql

2023-08-12T05:48:48 2023-08-12 05:48:48 UTC:121.7.242.90(53959):postgres@mytest:[2139]:LOG:  execute <unnamed>: SET extra_float_digits = 3
2023-08-12T05:48:48 2023-08-12 05:48:48 UTC:121.7.242.90(53959):postgres@mytest:[2139]:LOG:  execute <unnamed>: SET application_name = 'JDBCConnection: PrepareThreshold1CacheModeForceGeneric'
2023-08-12T05:48:48 2023-08-12 05:48:48 UTC:121.7.242.90(53959):postgres@mytest:[2139]:LOG:  execute S_1: SELECT * FROM t WHERE id = 1000
2023-08-12T05:48:49 2023-08-12 05:48:49 UTC:121.7.242.90(53959):postgres@mytest:[2139]:LOG:  duration: 525.903 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 1000
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.012..0.190 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
2023-08-12T05:48:49 2023-08-12 05:48:49 UTC:121.7.242.90(53959):postgres@mytest:[2139]:LOG:  execute S_2: SELECT * FROM t WHERE id = 2
2023-08-12T05:48:49 2023-08-12 05:48:49 UTC:121.7.242.90(53959):postgres@mytest:[2139]:LOG:  duration: 0.030 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 2
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.023..0.025 rows=1 loops=1)
	  Index Cond: (id = 2)
2023-08-12T05:48:50 2023-08-12 05:48:50 UTC:121.7.242.90(53959):postgres@mytest:[2139]:LOG:  execute S_3: SELECT * FROM t WHERE id = 3
2023-08-12T05:48:50 2023-08-12 05:48:50 UTC:121.7.242.90(53959):postgres@mytest:[2139]:LOG:  duration: 0.024 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 3
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.016..0.018 rows=1 loops=1)
	  Index Cond: (id = 3)
2023-08-12T05:48:50 2023-08-12 05:48:50 UTC:121.7.242.90(53959):postgres@mytest:[2139]:LOG:  execute S_4: SELECT * FROM t WHERE id = 4
2023-08-12T05:48:50 2023-08-12 05:48:50 UTC:121.7.242.90(53959):postgres@mytest:[2139]:LOG:  duration: 0.033 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 4
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.025..0.028 rows=1 loops=1)
	  Index Cond: (id = 4)
2023-08-12T05:48:50 2023-08-12 05:48:50 UTC:121.7.242.90(53959):postgres@mytest:[2139]:LOG:  execute S_5: SELECT * FROM t WHERE id = 5
2023-08-12T05:48:50 2023-08-12 05:48:50 UTC:121.7.242.90(53959):postgres@mytest:[2139]:LOG:  duration: 0.028 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 5
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.021..0.023 rows=1 loops=1)
	  Index Cond: (id = 5)
2023-08-12T05:48:50 2023-08-12 05:48:50 UTC:121.7.242.90(53959):postgres@mytest:[2139]:LOG:  execute S_6: SELECT * FROM t WHERE id = 6
2023-08-12T05:48:50 2023-08-12 05:48:50 UTC:121.7.242.90(53959):postgres@mytest:[2139]:LOG:  duration: 0.025 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 6
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.018..0.019 rows=1 loops=1)
	  Index Cond: (id = 6)
2023-08-12T05:48:51 2023-08-12 05:48:51 UTC:121.7.242.90(53959):postgres@mytest:[2139]:LOG:  execute S_7: SELECT * FROM t WHERE id = 7
2023-08-12T05:48:51 2023-08-12 05:48:51 UTC:121.7.242.90(53959):postgres@mytest:[2139]:LOG:  duration: 0.023 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 7
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.016..0.018 rows=1 loops=1)
	  Index Cond: (id = 7)
2023-08-12T05:48:51 2023-08-12 05:48:51 UTC:121.7.242.90(53959):postgres@mytest:[2139]:LOG:  execute S_8: SELECT * FROM t WHERE id = 1000
2023-08-12T05:48:51 2023-08-12 05:48:51 UTC:121.7.242.90(53959):postgres@mytest:[2139]:LOG:  duration: 0.520 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 1000
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.015..0.159 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
```
