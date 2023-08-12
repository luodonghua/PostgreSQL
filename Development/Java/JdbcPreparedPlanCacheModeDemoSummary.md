
## Summary


####  Observations:
1. During testing, the first time execution with id=1000 is much more expensive comparing to subsequent execution (483 ms vs 0.7 ms), although same plan used.
2. In the situation with "prepared statements", the value for `prepareThreshold=n` and `plan_cache_mode=auto`, after `n+5-1` executions, generic plan could be used if " its cost is not so much higher than the average custom-plan cost". (Ref: https://www.postgresql.org/docs/current/sql-prepare.html)
3. `plan_cache_mode` only affects prepared statements, has no effects on literal queries.
4. The ensure optimizer always pick the best plan, `plan_cache_mode=force_custom_plan` produces consistent plans.


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




### Statements:
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

### Statements:
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





