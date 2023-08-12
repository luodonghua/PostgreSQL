### Prepare Statements:
```java
Statement stmt = conn.createStatement();
stmt.execute("SELECT * FROM t WHERE id = 1");  
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

| Config | `1` | `2` | `3` | `4` | `5` | `6` | `1000` | `7` | `1000`|
| :-- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
|19.PrepareThreshold5CacheModeAuto|IS|IS|IS|IS|IS|IS|SEQ|IS|SEQ|
|20.PrepareThreshold5CacheModeForceCustom|IS|IS|IS|IS|IS|IS|SEQ|IS|SEQ|
|21.PrepareThreshold5CacheModeForceGeneric|IS|IS|IS|IS|IS|IS|SEQ|IS|SEQ|
|22.PrepareThreshold10CacheModeAuto|IS|IS|IS|IS|IS|IS|SEQ|IS|SEQ|
|23.PrepareThreshold10CacheModeForceCustom|IS|IS|IS|IS|IS|IS|SEQ|IS|SEQ|
|24.PrepareThreshold10CacheModeForceGeneric|IS|IS|IS|IS|IS|IS|SEQ|IS|SEQ|
|25.PrepareThreshold1CacheModeAuto|IS|IS|IS|IS|IS|IS|SEQ|IS|SEQ|
|26.PrepareThreshold1CacheModeForceCustom|IS|IS|IS|IS|IS|IS|SEQ|IS|SEQ|
|27.PrepareThreshold1CacheModeForceGeneric|IS|IS|IS|IS|IS|IS|SEQ|IS|SEQ|

- BIS: Bitmap Index Scan
- IS: Index Scan
- SEQ: Seq Scan

### Test 19: PrepareThreshold5CacheModeAuto + Statements

#### Sample Code
```java
 props.setProperty("ApplicationName", "JDBCConnection: PrepareThreshold5CacheModeAuto");
props.setProperty("options", "-c plan_cache_mode=auto -c log_statement=all -c auto_explain.log_analyze=1 -c auto_explain.log_min_duration=0");
props.setProperty("prepareThreshold", "5");
```

#### Output
```sql
2023-08-12T05:47:18 2023-08-12 05:47:18 UTC:121.7.242.90(53824):postgres@mytest:[2059]:LOG:  execute <unnamed>: SET extra_float_digits = 3
2023-08-12T05:47:18 2023-08-12 05:47:18 UTC:121.7.242.90(53824):postgres@mytest:[2059]:LOG:  execute <unnamed>: SET application_name = 'JDBCConnection: PrepareThreshold5CacheModeAuto'
2023-08-12T05:47:19 2023-08-12 05:47:19 UTC:121.7.242.90(53824):postgres@mytest:[2059]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 1
2023-08-12T05:47:19 2023-08-12 05:47:19 UTC:121.7.242.90(53824):postgres@mytest:[2059]:LOG:  duration: 0.056 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.050..0.051 rows=1 loops=1)
	  Index Cond: (id = 1)
2023-08-12T05:47:19 2023-08-12 05:47:19 UTC:121.7.242.90(53824):postgres@mytest:[2059]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 2
2023-08-12T05:47:19 2023-08-12 05:47:19 UTC:121.7.242.90(53824):postgres@mytest:[2059]:LOG:  duration: 0.020 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 2
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.013..0.014 rows=1 loops=1)
	  Index Cond: (id = 2)
2023-08-12T05:47:19 2023-08-12 05:47:19 UTC:121.7.242.90(53824):postgres@mytest:[2059]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 3
2023-08-12T05:47:19 2023-08-12 05:47:19 UTC:121.7.242.90(53824):postgres@mytest:[2059]:LOG:  duration: 0.023 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 3
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.016..0.017 rows=1 loops=1)
	  Index Cond: (id = 3)
2023-08-12T05:47:19 2023-08-12 05:47:19 UTC:121.7.242.90(53824):postgres@mytest:[2059]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 4
2023-08-12T05:47:19 2023-08-12 05:47:19 UTC:121.7.242.90(53824):postgres@mytest:[2059]:LOG:  duration: 0.023 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 4
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.015..0.017 rows=1 loops=1)
	  Index Cond: (id = 4)
2023-08-12T05:47:20 2023-08-12 05:47:20 UTC:121.7.242.90(53824):postgres@mytest:[2059]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 5
2023-08-12T05:47:20 2023-08-12 05:47:20 UTC:121.7.242.90(53824):postgres@mytest:[2059]:LOG:  duration: 0.021 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 5
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.014..0.016 rows=1 loops=1)
	  Index Cond: (id = 5)
2023-08-12T05:47:20 2023-08-12 05:47:20 UTC:121.7.242.90(53824):postgres@mytest:[2059]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 6
2023-08-12T05:47:20 2023-08-12 05:47:20 UTC:121.7.242.90(53824):postgres@mytest:[2059]:LOG:  duration: 0.022 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 6
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.015..0.017 rows=1 loops=1)
	  Index Cond: (id = 6)
2023-08-12T05:47:20 2023-08-12 05:47:20 UTC:121.7.242.90(53824):postgres@mytest:[2059]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 1000
2023-08-12T05:47:21 2023-08-12 05:47:21 UTC:121.7.242.90(53824):postgres@mytest:[2059]:LOG:  duration: 478.107 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 1000
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.013..0.185 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
2023-08-12T05:47:21 2023-08-12 05:47:21 UTC:121.7.242.90(53824):postgres@mytest:[2059]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 7
2023-08-12T05:47:21 2023-08-12 05:47:21 UTC:121.7.242.90(53824):postgres@mytest:[2059]:LOG:  duration: 0.022 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 7
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.015..0.017 rows=1 loops=1)
	  Index Cond: (id = 7)
2023-08-12T05:47:21 2023-08-12 05:47:21 UTC:121.7.242.90(53824):postgres@mytest:[2059]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 1000
2023-08-12T05:47:21 2023-08-12 05:47:21 UTC:121.7.242.90(53824):postgres@mytest:[2059]:LOG:  duration: 0.584 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 1000
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.014..0.220 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
```


### Test 20: PrepareThreshold5CacheModeForceCustom + Statements

#### Sample Code
```java
props.setProperty("ApplicationName", "JDBCConnection: PrepareThreshold5CacheModeForceCustom");
props.setProperty("options", "-c plan_cache_mode=force_custom_plan -c log_statement=all -c auto_explain.log_analyze=1 -c auto_explain.log_min_duration=0");
props.setProperty("prepareThreshold", "5");
```

#### Output
```sql
2023-08-12T05:47:24 2023-08-12 05:47:24 UTC:121.7.242.90(53835):postgres@mytest:[2062]:LOG:  execute <unnamed>: SET extra_float_digits = 3
2023-08-12T05:47:24 2023-08-12 05:47:24 UTC:121.7.242.90(53835):postgres@mytest:[2062]:LOG:  execute <unnamed>: SET application_name = 'JDBCConnection: PrepareThreshold5CacheModeForceCustom'
2023-08-12T05:47:24 2023-08-12 05:47:24 UTC:121.7.242.90(53835):postgres@mytest:[2062]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 1
2023-08-12T05:47:24 2023-08-12 05:47:24 UTC:121.7.242.90(53835):postgres@mytest:[2062]:LOG:  duration: 0.019 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.013..0.014 rows=1 loops=1)
	  Index Cond: (id = 1)
2023-08-12T05:47:25 2023-08-12 05:47:25 UTC:121.7.242.90(53835):postgres@mytest:[2062]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 2
2023-08-12T05:47:25 2023-08-12 05:47:25 UTC:121.7.242.90(53835):postgres@mytest:[2062]:LOG:  duration: 0.021 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 2
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.013..0.016 rows=1 loops=1)
	  Index Cond: (id = 2)
2023-08-12T05:47:25 2023-08-12 05:47:25 UTC:121.7.242.90(53835):postgres@mytest:[2062]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 3
2023-08-12T05:47:25 2023-08-12 05:47:25 UTC:121.7.242.90(53835):postgres@mytest:[2062]:LOG:  duration: 0.022 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 3
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.015..0.016 rows=1 loops=1)
	  Index Cond: (id = 3)
2023-08-12T05:47:25 2023-08-12 05:47:25 UTC:121.7.242.90(53835):postgres@mytest:[2062]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 4
2023-08-12T05:47:25 2023-08-12 05:47:25 UTC:121.7.242.90(53835):postgres@mytest:[2062]:LOG:  duration: 0.020 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 4
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.014..0.015 rows=1 loops=1)
	  Index Cond: (id = 4)
2023-08-12T05:47:25 2023-08-12 05:47:25 UTC:121.7.242.90(53835):postgres@mytest:[2062]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 5
2023-08-12T05:47:25 2023-08-12 05:47:25 UTC:121.7.242.90(53835):postgres@mytest:[2062]:LOG:  duration: 0.021 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 5
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.014..0.016 rows=1 loops=1)
	  Index Cond: (id = 5)
2023-08-12T05:47:26 2023-08-12 05:47:26 UTC:121.7.242.90(53835):postgres@mytest:[2062]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 6
2023-08-12T05:47:26 2023-08-12 05:47:26 UTC:121.7.242.90(53835):postgres@mytest:[2062]:LOG:  duration: 0.021 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 6
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.014..0.016 rows=1 loops=1)
	  Index Cond: (id = 6)
2023-08-12T05:47:26 2023-08-12 05:47:26 UTC:121.7.242.90(53835):postgres@mytest:[2062]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 1000
2023-08-12T05:47:27 2023-08-12 05:47:27 UTC:121.7.242.90(53835):postgres@mytest:[2062]:LOG:  duration: 526.466 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 1000
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.014..0.216 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
2023-08-12T05:47:27 2023-08-12 05:47:27 UTC:121.7.242.90(53835):postgres@mytest:[2062]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 7
2023-08-12T05:47:27 2023-08-12 05:47:27 UTC:121.7.242.90(53835):postgres@mytest:[2062]:LOG:  duration: 0.022 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 7
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.015..0.017 rows=1 loops=1)
	  Index Cond: (id = 7)
2023-08-12T05:47:27 2023-08-12 05:47:27 UTC:121.7.242.90(53835):postgres@mytest:[2062]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 1000
2023-08-12T05:47:27 2023-08-12 05:47:27 UTC:121.7.242.90(53835):postgres@mytest:[2062]:LOG:  duration: 0.562 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 1000
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.016..0.164 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
```


### Test 21: PrepareThreshold5CacheModeForceGeneric + Statements

#### Sample Code
```java
props.setProperty("ApplicationName", "JDBCConnection: PrepareThreshold5CacheModeForceGeneric");
props.setProperty("options", "-c plan_cache_mode=force_generic_plan -c log_statement=all -c auto_explain.log_analyze=1 -c auto_explain.log_min_duration=0");
props.setProperty("prepareThreshold", "5");
```

#### Output
```sql
2023-08-12T05:47:29 2023-08-12 05:47:29 UTC:121.7.242.90(53844):postgres@mytest:[2070]:LOG:  execute <unnamed>: SET extra_float_digits = 3
2023-08-12T05:47:30 2023-08-12 05:47:30 UTC:121.7.242.90(53844):postgres@mytest:[2070]:LOG:  execute <unnamed>: SET application_name = 'JDBCConnection: PrepareThreshold5CacheModeForceGeneric'
2023-08-12T05:47:30 2023-08-12 05:47:30 UTC:121.7.242.90(53844):postgres@mytest:[2070]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 1
2023-08-12T05:47:30 2023-08-12 05:47:30 UTC:121.7.242.90(53844):postgres@mytest:[2070]:LOG:  duration: 0.019 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.013..0.014 rows=1 loops=1)
	  Index Cond: (id = 1)
2023-08-12T05:47:30 2023-08-12 05:47:30 UTC:121.7.242.90(53844):postgres@mytest:[2070]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 2
2023-08-12T05:47:30 2023-08-12 05:47:30 UTC:121.7.242.90(53844):postgres@mytest:[2070]:LOG:  duration: 0.022 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 2
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.015..0.016 rows=1 loops=1)
	  Index Cond: (id = 2)
2023-08-12T05:47:30 2023-08-12 05:47:30 UTC:121.7.242.90(53844):postgres@mytest:[2070]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 3
2023-08-12T05:47:30 2023-08-12 05:47:30 UTC:121.7.242.90(53844):postgres@mytest:[2070]:LOG:  duration: 0.021 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 3
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.014..0.016 rows=1 loops=1)
	  Index Cond: (id = 3)
2023-08-12T05:47:31 2023-08-12 05:47:31 UTC:121.7.242.90(53844):postgres@mytest:[2070]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 4
2023-08-12T05:47:31 2023-08-12 05:47:31 UTC:121.7.242.90(53844):postgres@mytest:[2070]:LOG:  duration: 0.024 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 4
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.017..0.019 rows=1 loops=1)
	  Index Cond: (id = 4)
2023-08-12T05:47:31 2023-08-12 05:47:31 UTC:121.7.242.90(53844):postgres@mytest:[2070]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 5
2023-08-12T05:47:31 2023-08-12 05:47:31 UTC:121.7.242.90(53844):postgres@mytest:[2070]:LOG:  duration: 0.021 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 5
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.014..0.015 rows=1 loops=1)
	  Index Cond: (id = 5)
2023-08-12T05:47:31 2023-08-12 05:47:31 UTC:121.7.242.90(53844):postgres@mytest:[2070]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 6
2023-08-12T05:47:31 2023-08-12 05:47:31 UTC:121.7.242.90(53844):postgres@mytest:[2070]:LOG:  duration: 0.022 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 6
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.015..0.017 rows=1 loops=1)
	  Index Cond: (id = 6)
2023-08-12T05:47:31 2023-08-12 05:47:31 UTC:121.7.242.90(53844):postgres@mytest:[2070]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 1000
2023-08-12T05:47:32 2023-08-12 05:47:32 UTC:121.7.242.90(53844):postgres@mytest:[2070]:LOG:  duration: 574.825 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 1000
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.014..0.178 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
2023-08-12T05:47:32 2023-08-12 05:47:32 UTC:121.7.242.90(53844):postgres@mytest:[2070]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 7
2023-08-12T05:47:32 2023-08-12 05:47:32 UTC:121.7.242.90(53844):postgres@mytest:[2070]:LOG:  duration: 0.022 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 7
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.016..0.017 rows=1 loops=1)
	  Index Cond: (id = 7)
2023-08-12T05:47:33 2023-08-12 05:47:33 UTC:121.7.242.90(53844):postgres@mytest:[2070]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 1000
2023-08-12T05:47:33 2023-08-12 05:47:33 UTC:121.7.242.90(53844):postgres@mytest:[2070]:LOG:  duration: 256.734 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 1000
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.016..0.574 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
```



### Test 22: PrepareThreshold10CacheModeAuto + Statements

#### Sample Code
```java
props.setProperty("ApplicationName", "JDBCConnection: PrepareThreshold10CacheModeAuto");
props.setProperty("options", "-c plan_cache_mode=auto -c log_statement=all -c auto_explain.log_analyze=1 -c auto_explain.log_min_duration=0");
props.setProperty("prepareThreshold", "10");
```

#### Output
```sql
2023-08-12T05:47:35 2023-08-12 05:47:35 UTC:121.7.242.90(53853):postgres@mytest:[2073]:LOG:  execute <unnamed>: SET extra_float_digits = 3
2023-08-12T05:47:35 2023-08-12 05:47:35 UTC:121.7.242.90(53853):postgres@mytest:[2073]:LOG:  execute <unnamed>: SET application_name = 'JDBCConnection: PrepareThreshold10CacheModeAuto'
2023-08-12T05:47:35 2023-08-12 05:47:35 UTC:121.7.242.90(53853):postgres@mytest:[2073]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 1
2023-08-12T05:47:35 2023-08-12 05:47:35 UTC:121.7.242.90(53853):postgres@mytest:[2073]:LOG:  duration: 0.019 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.014..0.014 rows=1 loops=1)
	  Index Cond: (id = 1)
2023-08-12T05:47:36 2023-08-12 05:47:36 UTC:121.7.242.90(53853):postgres@mytest:[2073]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 2
2023-08-12T05:47:36 2023-08-12 05:47:36 UTC:121.7.242.90(53853):postgres@mytest:[2073]:LOG:  duration: 0.023 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 2
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.016..0.018 rows=1 loops=1)
	  Index Cond: (id = 2)
2023-08-12T05:47:36 2023-08-12 05:47:36 UTC:121.7.242.90(53853):postgres@mytest:[2073]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 3
2023-08-12T05:47:36 2023-08-12 05:47:36 UTC:121.7.242.90(53853):postgres@mytest:[2073]:LOG:  duration: 0.021 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 3
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.014..0.016 rows=1 loops=1)
	  Index Cond: (id = 3)
2023-08-12T05:47:36 2023-08-12 05:47:36 UTC:121.7.242.90(53853):postgres@mytest:[2073]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 4
2023-08-12T05:47:36 2023-08-12 05:47:36 UTC:121.7.242.90(53853):postgres@mytest:[2073]:LOG:  duration: 0.023 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 4
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.016..0.018 rows=1 loops=1)
	  Index Cond: (id = 4)
2023-08-12T05:47:36 2023-08-12 05:47:36 UTC:121.7.242.90(53853):postgres@mytest:[2073]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 5
2023-08-12T05:47:36 2023-08-12 05:47:36 UTC:121.7.242.90(53853):postgres@mytest:[2073]:LOG:  duration: 0.022 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 5
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.014..0.016 rows=1 loops=1)
	  Index Cond: (id = 5)
2023-08-12T05:47:37 2023-08-12 05:47:37 UTC:121.7.242.90(53853):postgres@mytest:[2073]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 6
2023-08-12T05:47:37 2023-08-12 05:47:37 UTC:121.7.242.90(53853):postgres@mytest:[2073]:LOG:  duration: 0.020 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 6
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.013..0.015 rows=1 loops=1)
	  Index Cond: (id = 6)
2023-08-12T05:47:37 2023-08-12 05:47:37 UTC:121.7.242.90(53853):postgres@mytest:[2073]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 1000
2023-08-12T05:47:37 2023-08-12 05:47:37 UTC:121.7.242.90(53853):postgres@mytest:[2073]:LOG:  duration: 486.281 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 1000
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.013..0.171 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
2023-08-12T05:47:38 2023-08-12 05:47:38 UTC:121.7.242.90(53853):postgres@mytest:[2073]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 7
2023-08-12T05:47:38 2023-08-12 05:47:38 UTC:121.7.242.90(53853):postgres@mytest:[2073]:LOG:  duration: 0.022 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 7
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.015..0.017 rows=1 loops=1)
	  Index Cond: (id = 7)
2023-08-12T05:47:38 2023-08-12 05:47:38 UTC:121.7.242.90(53853):postgres@mytest:[2073]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 1000
2023-08-12T05:47:38 2023-08-12 05:47:38 UTC:121.7.242.90(53853):postgres@mytest:[2073]:LOG:  duration: 0.543 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 1000
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.013..0.155 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
```



### Test 23: PrepareThreshold10CacheModeForceCustom + PreparedStatementsStatements

#### Sample Code
```java
props.setProperty("ApplicationName", "JDBCConnection: PrepareThreshold10CacheModeForceCustom");
props.setProperty("options", "-c plan_cache_mode=force_custom_plan -c log_statement=all -c auto_explain.log_analyze=1 -c auto_explain.log_min_duration=0");
props.setProperty("prepareThreshold", "10");
```

#### Output
```sql
2023-08-12T05:47:40 2023-08-12 05:47:40 UTC:121.7.242.90(53859):postgres@mytest:[2077]:LOG:  execute <unnamed>: SET extra_float_digits = 3
2023-08-12T05:47:40 2023-08-12 05:47:40 UTC:121.7.242.90(53859):postgres@mytest:[2077]:LOG:  execute <unnamed>: SET application_name = 'JDBCConnection: PrepareThreshold10CacheModeForceCustom'
2023-08-12T05:47:40 2023-08-12 05:47:40 UTC:121.7.242.90(53859):postgres@mytest:[2077]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 1
2023-08-12T05:47:40 2023-08-12 05:47:40 UTC:121.7.242.90(53859):postgres@mytest:[2077]:LOG:  duration: 0.018 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.013..0.014 rows=1 loops=1)
	  Index Cond: (id = 1)
2023-08-12T05:47:41 2023-08-12 05:47:41 UTC:121.7.242.90(53859):postgres@mytest:[2077]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 2
2023-08-12T05:47:41 2023-08-12 05:47:41 UTC:121.7.242.90(53859):postgres@mytest:[2077]:LOG:  duration: 0.019 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 2
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.013..0.014 rows=1 loops=1)
	  Index Cond: (id = 2)
2023-08-12T05:47:41 2023-08-12 05:47:41 UTC:121.7.242.90(53859):postgres@mytest:[2077]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 3
2023-08-12T05:47:41 2023-08-12 05:47:41 UTC:121.7.242.90(53859):postgres@mytest:[2077]:LOG:  duration: 0.020 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 3
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.013..0.015 rows=1 loops=1)
	  Index Cond: (id = 3)
2023-08-12T05:47:41 2023-08-12 05:47:41 UTC:121.7.242.90(53859):postgres@mytest:[2077]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 4
2023-08-12T05:47:41 2023-08-12 05:47:41 UTC:121.7.242.90(53859):postgres@mytest:[2077]:LOG:  duration: 0.021 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 4
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.014..0.016 rows=1 loops=1)
	  Index Cond: (id = 4)
2023-08-12T05:47:41 2023-08-12 05:47:41 UTC:121.7.242.90(53859):postgres@mytest:[2077]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 5
2023-08-12T05:47:41 2023-08-12 05:47:41 UTC:121.7.242.90(53859):postgres@mytest:[2077]:LOG:  duration: 0.022 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 5
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.016..0.017 rows=1 loops=1)
	  Index Cond: (id = 5)
2023-08-12T05:47:42 2023-08-12 05:47:42 UTC:121.7.242.90(53859):postgres@mytest:[2077]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 6
2023-08-12T05:47:42 2023-08-12 05:47:42 UTC:121.7.242.90(53859):postgres@mytest:[2077]:LOG:  duration: 0.023 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 6
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.016..0.018 rows=1 loops=1)
	  Index Cond: (id = 6)
2023-08-12T05:47:42 2023-08-12 05:47:42 UTC:121.7.242.90(53859):postgres@mytest:[2077]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 1000
2023-08-12T05:47:42 2023-08-12 05:47:42 UTC:121.7.242.90(53859):postgres@mytest:[2077]:LOG:  duration: 483.252 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 1000
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.016..0.179 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
2023-08-12T05:47:43 2023-08-12 05:47:43 UTC:121.7.242.90(53859):postgres@mytest:[2077]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 7
2023-08-12T05:47:43 2023-08-12 05:47:43 UTC:121.7.242.90(53859):postgres@mytest:[2077]:LOG:  duration: 0.022 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 7
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.015..0.017 rows=1 loops=1)
	  Index Cond: (id = 7)
2023-08-12T05:47:43 2023-08-12 05:47:43 UTC:121.7.242.90(53859):postgres@mytest:[2077]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 1000
2023-08-12T05:47:43 2023-08-12 05:47:43 UTC:121.7.242.90(53859):postgres@mytest:[2077]:LOG:  duration: 0.511 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 1000
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.011..0.150 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
```



### Test 24: PrepareThreshold10CacheModeForceGeneric + Statements

#### Sample Code
```java
props.setProperty("ApplicationName", "JDBCConnection: PrepareThreshold10CacheModeForceGeneric");
props.setProperty("options", "-c plan_cache_mode=force_generic_plan -c log_statement=all -c auto_explain.log_analyze=1 -c auto_explain.log_min_duration=0");
props.setProperty("prepareThreshold", "10");
```

#### Output
```sql

2023-08-12T05:47:45 2023-08-12 05:47:45 UTC:121.7.242.90(53872):postgres@mytest:[2085]:LOG:  execute <unnamed>: SET extra_float_digits = 3
2023-08-12T05:47:46 2023-08-12 05:47:46 UTC:121.7.242.90(53872):postgres@mytest:[2085]:LOG:  execute <unnamed>: SET application_name = 'JDBCConnection: PrepareThreshold10CacheModeForceGeneric'
2023-08-12T05:47:46 2023-08-12 05:47:46 UTC:121.7.242.90(53872):postgres@mytest:[2085]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 1
2023-08-12T05:47:46 2023-08-12 05:47:46 UTC:121.7.242.90(53872):postgres@mytest:[2085]:LOG:  duration: 0.020 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.014..0.015 rows=1 loops=1)
	  Index Cond: (id = 1)
2023-08-12T05:47:46 2023-08-12 05:47:46 UTC:121.7.242.90(53872):postgres@mytest:[2085]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 2
2023-08-12T05:47:46 2023-08-12 05:47:46 UTC:121.7.242.90(53872):postgres@mytest:[2085]:LOG:  duration: 0.020 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 2
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.013..0.015 rows=1 loops=1)
	  Index Cond: (id = 2)
2023-08-12T05:47:46 2023-08-12 05:47:46 UTC:121.7.242.90(53872):postgres@mytest:[2085]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 3
2023-08-12T05:47:46 2023-08-12 05:47:46 UTC:121.7.242.90(53872):postgres@mytest:[2085]:LOG:  duration: 0.021 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 3
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.014..0.016 rows=1 loops=1)
	  Index Cond: (id = 3)
2023-08-12T05:47:47 2023-08-12 05:47:47 UTC:121.7.242.90(53872):postgres@mytest:[2085]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 4
2023-08-12T05:47:47 2023-08-12 05:47:47 UTC:121.7.242.90(53872):postgres@mytest:[2085]:LOG:  duration: 0.024 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 4
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.017..0.019 rows=1 loops=1)
	  Index Cond: (id = 4)
2023-08-12T05:47:47 2023-08-12 05:47:47 UTC:121.7.242.90(53872):postgres@mytest:[2085]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 5
2023-08-12T05:47:47 2023-08-12 05:47:47 UTC:121.7.242.90(53872):postgres@mytest:[2085]:LOG:  duration: 0.021 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 5
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.015..0.016 rows=1 loops=1)
	  Index Cond: (id = 5)
2023-08-12T05:47:47 2023-08-12 05:47:47 UTC:121.7.242.90(53872):postgres@mytest:[2085]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 6
2023-08-12T05:47:47 2023-08-12 05:47:47 UTC:121.7.242.90(53872):postgres@mytest:[2085]:LOG:  duration: 0.022 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 6
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.014..0.016 rows=1 loops=1)
	  Index Cond: (id = 6)
2023-08-12T05:47:47 2023-08-12 05:47:47 UTC:121.7.242.90(53872):postgres@mytest:[2085]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 1000
2023-08-12T05:47:48 2023-08-12 05:47:48 UTC:121.7.242.90(53872):postgres@mytest:[2085]:LOG:  duration: 476.767 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 1000
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.013..0.239 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
2023-08-12T05:47:48 2023-08-12 05:47:48 UTC:121.7.242.90(53872):postgres@mytest:[2085]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 7
2023-08-12T05:47:48 2023-08-12 05:47:48 UTC:121.7.242.90(53872):postgres@mytest:[2085]:LOG:  duration: 0.019 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 7
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.013..0.015 rows=1 loops=1)
	  Index Cond: (id = 7)
2023-08-12T05:47:49 2023-08-12 05:47:49 UTC:121.7.242.90(53872):postgres@mytest:[2085]:LOG:  execute <unnamed>: SELECT * FROM t WHERE id = 1000
2023-08-12T05:47:49 2023-08-12 05:47:49 UTC:121.7.242.90(53872):postgres@mytest:[2085]:LOG:  duration: 0.548 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 1000
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.013..0.154 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
```


### Test 25: PrepareThreshold1CacheModeAuto + Statements

#### Sample Code
```java
props.setProperty("ApplicationName", "JDBCConnection: PrepareThreshold1CacheModeAuto");
props.setProperty("options", "-c plan_cache_mode=auto -c log_statement=all -c auto_explain.log_analyze=1 -c auto_explain.log_min_duration=0");
props.setProperty("prepareThreshold", "1");
```

#### Output
```sql
2023-08-12T05:47:50 2023-08-12 05:47:50 UTC:121.7.242.90(53879):postgres@mytest:[2087]:LOG:  execute <unnamed>: SET extra_float_digits = 3
2023-08-12T05:47:51 2023-08-12 05:47:51 UTC:121.7.242.90(53879):postgres@mytest:[2087]:LOG:  execute <unnamed>: SET application_name = 'JDBCConnection: PrepareThreshold1CacheModeAuto'
2023-08-12T05:47:51 2023-08-12 05:47:51 UTC:121.7.242.90(53879):postgres@mytest:[2087]:LOG:  execute S_1: SELECT * FROM t WHERE id = 1
2023-08-12T05:47:51 2023-08-12 05:47:51 UTC:121.7.242.90(53879):postgres@mytest:[2087]:LOG:  duration: 0.017 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.011..0.012 rows=1 loops=1)
	  Index Cond: (id = 1)
2023-08-12T05:47:51 2023-08-12 05:47:51 UTC:121.7.242.90(53879):postgres@mytest:[2087]:LOG:  execute S_2: SELECT * FROM t WHERE id = 2
2023-08-12T05:47:51 2023-08-12 05:47:51 UTC:121.7.242.90(53879):postgres@mytest:[2087]:LOG:  duration: 0.028 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 2
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.021..0.022 rows=1 loops=1)
	  Index Cond: (id = 2)
2023-08-12T05:47:51 2023-08-12 05:47:51 UTC:121.7.242.90(53879):postgres@mytest:[2087]:LOG:  execute S_3: SELECT * FROM t WHERE id = 3
2023-08-12T05:47:51 2023-08-12 05:47:51 UTC:121.7.242.90(53879):postgres@mytest:[2087]:LOG:  duration: 0.021 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 3
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.014..0.016 rows=1 loops=1)
	  Index Cond: (id = 3)
2023-08-12T05:47:52 2023-08-12 05:47:52 UTC:121.7.242.90(53879):postgres@mytest:[2087]:LOG:  execute S_4: SELECT * FROM t WHERE id = 4
2023-08-12T05:47:52 2023-08-12 05:47:52 UTC:121.7.242.90(53879):postgres@mytest:[2087]:LOG:  duration: 0.034 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 4
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.027..0.029 rows=1 loops=1)
	  Index Cond: (id = 4)
2023-08-12T05:47:52 2023-08-12 05:47:52 UTC:121.7.242.90(53879):postgres@mytest:[2087]:LOG:  execute S_5: SELECT * FROM t WHERE id = 5
2023-08-12T05:47:52 2023-08-12 05:47:52 UTC:121.7.242.90(53879):postgres@mytest:[2087]:LOG:  duration: 0.032 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 5
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.024..0.026 rows=1 loops=1)
	  Index Cond: (id = 5)
2023-08-12T05:47:52 2023-08-12 05:47:52 UTC:121.7.242.90(53879):postgres@mytest:[2087]:LOG:  execute S_6: SELECT * FROM t WHERE id = 6
2023-08-12T05:47:52 2023-08-12 05:47:52 UTC:121.7.242.90(53879):postgres@mytest:[2087]:LOG:  duration: 0.025 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 6
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.018..0.020 rows=1 loops=1)
	  Index Cond: (id = 6)
2023-08-12T05:47:52 2023-08-12 05:47:52 UTC:121.7.242.90(53879):postgres@mytest:[2087]:LOG:  execute S_7: SELECT * FROM t WHERE id = 1000
2023-08-12T05:47:53 2023-08-12 05:47:53 UTC:121.7.242.90(53879):postgres@mytest:[2087]:LOG:  duration: 485.288 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 1000
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.014..0.258 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
2023-08-12T05:47:53 2023-08-12 05:47:53 UTC:121.7.242.90(53879):postgres@mytest:[2087]:LOG:  execute S_8: SELECT * FROM t WHERE id = 7
2023-08-12T05:47:53 2023-08-12 05:47:53 UTC:121.7.242.90(53879):postgres@mytest:[2087]:LOG:  duration: 0.046 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 7
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.039..0.041 rows=1 loops=1)
	  Index Cond: (id = 7)
2023-08-12T05:47:54 2023-08-12 05:47:54 UTC:121.7.242.90(53879):postgres@mytest:[2087]:LOG:  execute S_9: SELECT * FROM t WHERE id = 1000
2023-08-12T05:47:54 2023-08-12 05:47:54 UTC:121.7.242.90(53879):postgres@mytest:[2087]:LOG:  duration: 1.605 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 1000
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.021..0.314 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
```

### Test 26: PrepareThreshold1CacheModeForceCustom + Statements

#### Sample Code
```java
props.setProperty("ApplicationName", "JDBCConnection: PrepareThreshold1CacheModeForceCustom");
props.setProperty("options", "-c plan_cache_mode=force_custom_plan -c log_statement=all -c auto_explain.log_analyze=1 -c auto_explain.log_min_duration=0");
props.setProperty("prepareThreshold", "1");
```

#### Output
```sql
2023-08-12T05:47:56 2023-08-12 05:47:56 UTC:121.7.242.90(53885):postgres@mytest:[2096]:LOG:  execute <unnamed>: SET extra_float_digits = 3
2023-08-12T05:47:56 2023-08-12 05:47:56 UTC:121.7.242.90(53885):postgres@mytest:[2096]:LOG:  execute <unnamed>: SET application_name = 'JDBCConnection: PrepareThreshold1CacheModeForceCustom'
2023-08-12T05:47:56 2023-08-12 05:47:56 UTC:121.7.242.90(53885):postgres@mytest:[2096]:LOG:  execute S_1: SELECT * FROM t WHERE id = 1
2023-08-12T05:47:56 2023-08-12 05:47:56 UTC:121.7.242.90(53885):postgres@mytest:[2096]:LOG:  duration: 0.028 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.010..0.011 rows=1 loops=1)
	  Index Cond: (id = 1)
2023-08-12T05:47:57 2023-08-12 05:47:57 UTC:121.7.242.90(53885):postgres@mytest:[2096]:LOG:  execute S_2: SELECT * FROM t WHERE id = 2
2023-08-12T05:47:57 2023-08-12 05:47:57 UTC:121.7.242.90(53885):postgres@mytest:[2096]:LOG:  duration: 0.024 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 2
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.018..0.019 rows=1 loops=1)
	  Index Cond: (id = 2)
2023-08-12T05:47:57 2023-08-12 05:47:57 UTC:121.7.242.90(53885):postgres@mytest:[2096]:LOG:  execute S_3: SELECT * FROM t WHERE id = 3
2023-08-12T05:47:57 2023-08-12 05:47:57 UTC:121.7.242.90(53885):postgres@mytest:[2096]:LOG:  duration: 0.024 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 3
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.016..0.018 rows=1 loops=1)
	  Index Cond: (id = 3)
2023-08-12T05:47:57 2023-08-12 05:47:57 UTC:121.7.242.90(53885):postgres@mytest:[2096]:LOG:  execute S_4: SELECT * FROM t WHERE id = 4
2023-08-12T05:47:57 2023-08-12 05:47:57 UTC:121.7.242.90(53885):postgres@mytest:[2096]:LOG:  duration: 0.032 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 4
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.024..0.026 rows=1 loops=1)
	  Index Cond: (id = 4)
2023-08-12T05:47:57 2023-08-12 05:47:57 UTC:121.7.242.90(53885):postgres@mytest:[2096]:LOG:  execute S_5: SELECT * FROM t WHERE id = 5
2023-08-12T05:47:57 2023-08-12 05:47:57 UTC:121.7.242.90(53885):postgres@mytest:[2096]:LOG:  duration: 0.040 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 5
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.033..0.034 rows=1 loops=1)
	  Index Cond: (id = 5)
2023-08-12T05:47:58 2023-08-12 05:47:58 UTC:121.7.242.90(53885):postgres@mytest:[2096]:LOG:  execute S_6: SELECT * FROM t WHERE id = 6
2023-08-12T05:47:58 2023-08-12 05:47:58 UTC:121.7.242.90(53885):postgres@mytest:[2096]:LOG:  duration: 0.026 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 6
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.019..0.021 rows=1 loops=1)
	  Index Cond: (id = 6)
2023-08-12T05:47:58 2023-08-12 05:47:58 UTC:121.7.242.90(53885):postgres@mytest:[2096]:LOG:  execute S_7: SELECT * FROM t WHERE id = 1000
2023-08-12T05:47:59 2023-08-12 05:47:59 UTC:121.7.242.90(53885):postgres@mytest:[2096]:LOG:  duration: 517.097 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 1000
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.016..0.211 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
2023-08-12T05:47:59 2023-08-12 05:47:59 UTC:121.7.242.90(53885):postgres@mytest:[2096]:LOG:  execute S_8: SELECT * FROM t WHERE id = 7
2023-08-12T05:47:59 2023-08-12 05:47:59 UTC:121.7.242.90(53885):postgres@mytest:[2096]:LOG:  duration: 0.048 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 7
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.040..0.042 rows=1 loops=1)
	  Index Cond: (id = 7)
2023-08-12T05:47:59 2023-08-12 05:47:59 UTC:121.7.242.90(53885):postgres@mytest:[2096]:LOG:  execute S_9: SELECT * FROM t WHERE id = 1000
2023-08-12T05:47:59 2023-08-12 05:47:59 UTC:121.7.242.90(53885):postgres@mytest:[2096]:LOG:  duration: 0.628 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 1000
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.016..0.199 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
```

### Test 27: PrepareThreshold1CacheModeForceGeneric + Statements

#### Sample Code
```java
props.setProperty("ApplicationName", "JDBCConnection: PrepareThreshold1CacheModeForceGeneric");
props.setProperty("options", "-c plan_cache_mode=force_generic_plan -c log_statement=all -c auto_explain.log_analyze=1 -c auto_explain.log_min_duration=0");
props.setProperty("prepareThreshold", "1");
```

#### Output
```sql
2023-08-12T05:48:01 2023-08-12 05:48:01 UTC:121.7.242.90(53893):postgres@mytest:[2098]:LOG:  execute <unnamed>: SET extra_float_digits = 3
2023-08-12T05:48:02 2023-08-12 05:48:02 UTC:121.7.242.90(53893):postgres@mytest:[2098]:LOG:  execute <unnamed>: SET application_name = 'JDBCConnection: PrepareThreshold1CacheModeForceGeneric'
2023-08-12T05:48:02 2023-08-12 05:48:02 UTC:121.7.242.90(53893):postgres@mytest:[2098]:LOG:  execute S_1: SELECT * FROM t WHERE id = 1
2023-08-12T05:48:02 2023-08-12 05:48:02 UTC:121.7.242.90(53893):postgres@mytest:[2098]:LOG:  duration: 0.017 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 1
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.010..0.011 rows=1 loops=1)
	  Index Cond: (id = 1)
2023-08-12T05:48:02 2023-08-12 05:48:02 UTC:121.7.242.90(53893):postgres@mytest:[2098]:LOG:  execute S_2: SELECT * FROM t WHERE id = 2
2023-08-12T05:48:02 2023-08-12 05:48:02 UTC:121.7.242.90(53893):postgres@mytest:[2098]:LOG:  duration: 0.027 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 2
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.020..0.022 rows=1 loops=1)
	  Index Cond: (id = 2)
2023-08-12T05:48:02 2023-08-12 05:48:02 UTC:121.7.242.90(53893):postgres@mytest:[2098]:LOG:  execute S_3: SELECT * FROM t WHERE id = 3
2023-08-12T05:48:02 2023-08-12 05:48:02 UTC:121.7.242.90(53893):postgres@mytest:[2098]:LOG:  duration: 0.020 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 3
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.013..0.015 rows=1 loops=1)
	  Index Cond: (id = 3)
2023-08-12T05:48:03 2023-08-12 05:48:03 UTC:121.7.242.90(53893):postgres@mytest:[2098]:LOG:  execute S_4: SELECT * FROM t WHERE id = 4
2023-08-12T05:48:03 2023-08-12 05:48:03 UTC:121.7.242.90(53893):postgres@mytest:[2098]:LOG:  duration: 0.031 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 4
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.023..0.026 rows=1 loops=1)
	  Index Cond: (id = 4)
2023-08-12T05:48:03 2023-08-12 05:48:03 UTC:121.7.242.90(53893):postgres@mytest:[2098]:LOG:  execute S_5: SELECT * FROM t WHERE id = 5
2023-08-12T05:48:03 2023-08-12 05:48:03 UTC:121.7.242.90(53893):postgres@mytest:[2098]:LOG:  duration: 0.032 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 5
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.024..0.027 rows=1 loops=1)
	  Index Cond: (id = 5)
2023-08-12T05:48:03 2023-08-12 05:48:03 UTC:121.7.242.90(53893):postgres@mytest:[2098]:LOG:  execute S_6: SELECT * FROM t WHERE id = 6
2023-08-12T05:48:03 2023-08-12 05:48:03 UTC:121.7.242.90(53893):postgres@mytest:[2098]:LOG:  duration: 0.023 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 6
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.016..0.018 rows=1 loops=1)
	  Index Cond: (id = 6)
2023-08-12T05:48:03 2023-08-12 05:48:03 UTC:121.7.242.90(53893):postgres@mytest:[2098]:LOG:  execute S_7: SELECT * FROM t WHERE id = 1000
2023-08-12T05:48:04 2023-08-12 05:48:04 UTC:121.7.242.90(53893):postgres@mytest:[2098]:LOG:  duration: 489.701 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 1000
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.039..0.210 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
2023-08-12T05:48:04 2023-08-12 05:48:04 UTC:121.7.242.90(53893):postgres@mytest:[2098]:LOG:  execute S_8: SELECT * FROM t WHERE id = 7
2023-08-12T05:48:04 2023-08-12 05:48:04 UTC:121.7.242.90(53893):postgres@mytest:[2098]:LOG:  duration: 0.047 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 7
	Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) (actual time=0.040..0.042 rows=1 loops=1)
	  Index Cond: (id = 7)
2023-08-12T05:48:04 2023-08-12 05:48:04 UTC:121.7.242.90(53893):postgres@mytest:[2098]:LOG:  execute S_9: SELECT * FROM t WHERE id = 1000
2023-08-12T05:48:04 2023-08-12 05:48:04 UTC:121.7.242.90(53893):postgres@mytest:[2098]:LOG:  duration: 0.586 ms  plan:
	Query Text: SELECT * FROM t WHERE id = 1000
	Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) (actual time=0.013..0.180 rows=990 loops=1)
	  Filter: (id = 1000)
	  Rows Removed by Filter: 10
```
