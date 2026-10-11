# JDBC Prepared Statements & PostgreSQL Plan Cache

A hands-on demo of how the PostgreSQL JDBC driver's `prepareThreshold` interacts
with the server's `plan_cache_mode` to decide whether a query uses a **custom
plan** (re-planned for the actual parameter value) or a **generic plan**
(planned once, parameter-agnostic). The practical question: *when does a prepared
statement switch to a generic plan, and when does that hurt?*

- Full source: [`JdbcPreparedPlanCacheModeDemo.java`](JdbcPreparedPlanCacheModeDemo.java)
- Full raw server logs (per scenario): [`server-logs/`](server-logs/)

## Background

- **Custom plan** — PostgreSQL re-plans the statement for each specific parameter value, so the plan can be optimal for that value (e.g. index scan for a selective value, seq scan for a non-selective one).
- **Generic plan** — PostgreSQL plans the statement once with no knowledge of the parameter, and reuses that plan for every execution. Cheaper to plan, but can be wrong for skewed data.
- **`prepareThreshold=n`** (pgjdbc) — the driver issues a server-side *named* prepared statement after the same statement has been executed `n` times. Before that it uses unnamed/one-off execution.
- **`plan_cache_mode`** (server) — `auto` (default; lets PostgreSQL choose generic vs custom after a few executions), `force_custom_plan`, or `force_generic_plan`. **It only affects server-side prepared statements**, not literal SQL.

### The data

A table where `id` is highly skewed: values `1..10` each match a single row,
while `id = 1000` matches the other ~990 rows. So `id = 5` wants an **index
scan** and `id = 1000` wants a **seq scan** — the perfect setup to show when a
cached plan picks the wrong strategy.

```sql
CREATE TABLE t (id INT, c TEXT);
INSERT INTO t
  SELECT CASE WHEN x <= 10 THEN x ELSE 1000 END, RPAD('x', 100, 'x')
  FROM generate_series(1, 1000) x;
CREATE INDEX t_id_n1 ON t (id);
```

Each test connection sets the mode via JDBC `options`, e.g.:

```java
props.setProperty("prepareThreshold", "5");
props.setProperty("options",
    "-c plan_cache_mode=auto -c log_statement=all "
  + "-c auto_explain.log_analyze=1 -c auto_explain.log_min_duration=0");
```

## Key observations

1. The **first** execution of `id = 1000` is much more expensive than later ones (≈483 ms vs ≈0.7 ms) even though the **same plan** is used — first-touch cost (cache warming), not a plan difference.
2. With prepared statements under `plan_cache_mode=auto`, after about `n + 5 − 1` executions a **generic plan** may be chosen *if "its cost is not so much higher than the average custom-plan cost"* ([docs: PREPARE](https://www.postgresql.org/docs/current/sql-prepare.html)).
3. **`plan_cache_mode` only affects prepared statements** — it has no effect on literal queries.
4. To make the optimizer always pick the best plan per value, **`plan_cache_mode=force_custom_plan`** produces consistent (per-value) plans.

## Scenarios and results

Four execution patterns were each run against 9 config combinations
(`prepareThreshold` ∈ {5, 10, 1} × `plan_cache_mode` ∈ {auto, force_custom,
force_generic}). Plan legend:

- **BIS** — Bitmap Index Scan
- **IS** — Index Scan
- **SEQ** — Seq Scan

### Scenario 1 — Prepared statements (`id` sequence 1..6, 1000, 7, 1000)

```java
PreparedStatement ps = conn.prepareStatement("SELECT * FROM t WHERE id = ?");
// setInt + executeQuery for: 1, 2, 3, 4, 5, 6, 1000, 7, 1000
```

Full log: [`server-logs/prepared-statements.md`](server-logs/prepared-statements.md)

| Config | `1` | `2` | `3` | `4` | `5` | `6` | `1000` | `7` | `1000` |
| :-- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1. PrepareThreshold5 / auto         | BIS | IS | IS | IS | IS | IS | SEQ | IS | SEQ |
| 2. PrepareThreshold5 / forceCustom  | IS  | IS | IS | IS | IS | IS | SEQ | IS | SEQ |
| 3. PrepareThreshold5 / forceGeneric | IS  | IS | IS | IS | IS | IS | IS  | IS | IS  |
| 4. PrepareThreshold10 / auto        | IS  | IS | IS | IS | IS | IS | SEQ | IS | SEQ |
| 5. PrepareThreshold10 / forceCustom | IS  | IS | IS | IS | IS | IS | SEQ | IS | SEQ |
| 6. PrepareThreshold10 / forceGeneric| IS  | IS | IS | IS | IS | IS | IS  | IS | IS  |
| 7. PrepareThreshold1 / auto         | IS  | IS | IS | IS | IS | IS | IS  | IS | IS  |
| 8. PrepareThreshold1 / forceCustom  | IS  | IS | IS | IS | IS | IS | SEQ | IS | SEQ |
| 9. PrepareThreshold1 / forceGeneric | IS  | IS | IS | IS | IS | IS | IS  | IS | IS  |

### Scenario 2 — Prepared statements starting with 1000 (1000, 2..6, 1000, 7, 1000)

```java
PreparedStatement ps = conn.prepareStatement("SELECT * FROM t WHERE id = ?");
// setInt + executeQuery for: 1000, 2, 3, 4, 5, 6, 1000, 7, 1000
```

Full log: [`server-logs/prepared-statements-start-1000.md`](server-logs/prepared-statements-start-1000.md)

| Config | `1000` | `2` | `3` | `4` | `5` | `6` | `1000` | `7` | `1000` |
| :-- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 10. PrepareThreshold5 / auto         | SEQ | IS | IS | IS | IS | IS | SEQ | IS | SEQ |
| 11. PrepareThreshold5 / forceCustom  | SEQ | IS | IS | IS | IS | IS | SEQ | IS | SEQ |
| 12. PrepareThreshold5 / forceGeneric | IS  | IS | IS | IS | IS | IS | IS  | IS | IS  |
| 13. PrepareThreshold10 / auto        | SEQ | IS | IS | IS | IS | IS | SEQ | IS | SEQ |
| 14. PrepareThreshold10 / forceCustom | SEQ | IS | IS | IS | IS | IS | SEQ | IS | SEQ |
| 15. PrepareThreshold10 / forceGeneric| IS  | IS | IS | IS | IS | IS | IS  | IS | IS  |
| 16. PrepareThreshold1 / auto         | SEQ | IS | IS | IS | IS | IS | IS  | IS | IS  |
| 17. PrepareThreshold1 / forceCustom  | SEQ | IS | IS | IS | IS | IS | SEQ | IS | SEQ |
| 18. PrepareThreshold1 / forceGeneric | IS  | IS | IS | IS | IS | IS | IS  | IS | IS  |

### Scenario 3 — Literal statements (`id` sequence 1..6, 1000, 7, 1000)

```java
Statement stmt = conn.createStatement();
stmt.execute("SELECT * FROM t WHERE id = 1");   // ... 2..6, 1000, 7, 1000
```

Full log: [`server-logs/statements.md`](server-logs/statements.md)

| Config | `1` | `2` | `3` | `4` | `5` | `6` | `1000` | `7` | `1000` |
| :-- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 19. PrepareThreshold5 / auto         | IS | IS | IS | IS | IS | IS | SEQ | IS | SEQ |
| 20. PrepareThreshold5 / forceCustom  | IS | IS | IS | IS | IS | IS | SEQ | IS | SEQ |
| 21. PrepareThreshold5 / forceGeneric | IS | IS | IS | IS | IS | IS | SEQ | IS | SEQ |
| 22. PrepareThreshold10 / auto        | IS | IS | IS | IS | IS | IS | SEQ | IS | SEQ |
| 23. PrepareThreshold10 / forceCustom | IS | IS | IS | IS | IS | IS | SEQ | IS | SEQ |
| 24. PrepareThreshold10 / forceGeneric| IS | IS | IS | IS | IS | IS | SEQ | IS | SEQ |
| 25. PrepareThreshold1 / auto         | IS | IS | IS | IS | IS | IS | SEQ | IS | SEQ |
| 26. PrepareThreshold1 / forceCustom  | IS | IS | IS | IS | IS | IS | SEQ | IS | SEQ |
| 27. PrepareThreshold1 / forceGeneric | IS | IS | IS | IS | IS | IS | SEQ | IS | SEQ |

Note how **every** config picks the right plan per value — `plan_cache_mode`
has no effect because these are literal (non-prepared) statements. This confirms
observation 3.

### Scenario 4 — Literal statements starting with 1000 (1000, 2..6, 1000, 7, 1000)

```java
Statement stmt = conn.createStatement();
stmt.execute("SELECT * FROM t WHERE id = 1000");  // ... 2..6, 1000, 7, 1000
```

Full log: [`server-logs/statements-start-1000.md`](server-logs/statements-start-1000.md)

| Config | `1000` | `2` | `3` | `4` | `5` | `6` | `1000` | `7` | `1000` |
| :-- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 28. PrepareThreshold5 / auto         | SEQ | IS | IS | IS | IS | IS | SEQ | IS | SEQ |
| 29. PrepareThreshold5 / forceCustom  | SEQ | IS | IS | IS | IS | IS | SEQ | IS | SEQ |
| 30. PrepareThreshold5 / forceGeneric | SEQ | IS | IS | IS | IS | IS | SEQ | IS | SEQ |
| 31. PrepareThreshold10 / auto        | SEQ | IS | IS | IS | IS | IS | SEQ | IS | SEQ |
| 32. PrepareThreshold10 / forceCustom | SEQ | IS | IS | IS | IS | IS | SEQ | IS | SEQ |
| 33. PrepareThreshold10 / forceGeneric| SEQ | IS | IS | IS | IS | IS | SEQ | IS | SEQ |
| 34. PrepareThreshold1 / auto         | SEQ | IS | IS | IS | IS | IS | SEQ | IS | SEQ |
| 35. PrepareThreshold1 / forceCustom  | SEQ | IS | IS | IS | IS | IS | SEQ | IS | SEQ |
| 36. PrepareThreshold1 / forceGeneric | SEQ | IS | IS | IS | IS | IS | SEQ | IS | SEQ |

## How to read the raw logs

Each file in [`server-logs/`](server-logs/) contains, per test, the connection
settings and the `auto_explain` plan output for every execution. The driver
switches from unnamed execution (`execute <unnamed>`) to a named prepared
statement (`execute S_1`) once `prepareThreshold` is reached — that is the point
where `plan_cache_mode` starts to matter.

A representative excerpt from Scenario 1, config 1 (`prepareThreshold=5`,
`plan_cache_mode=auto`), showing the switch to `S_1` and then the generic
seq-scan plan reused for `id = 1000`:

```text
LOG:  execute S_1: SELECT * FROM t WHERE id = $1
DETAIL:  parameters: $1 = '6'
LOG:  duration: 0.020 ms  plan:
    Index Scan using t_id_n1 on t  (cost=0.15..8.17 rows=1 width=105) ...
      Index Cond: (id = 6)

LOG:  execute S_1: SELECT * FROM t WHERE id = $1
DETAIL:  parameters: $1 = '1000'
LOG:  duration: 483.130 ms  plan:
    Seq Scan on t  (cost=0.00..30.50 rows=990 width=105) ...
      Filter: (id = 1000)
      Rows Removed by Filter: 10
```

Here the plan has become generic after the threshold, so `id = 1000` correctly
seq-scans — but note the first such execution's 483 ms is first-touch cost
(observation 1), not the plan itself.

## Takeaways

- Under `plan_cache_mode=auto`, a prepared statement can flip to a **generic plan** after ~`prepareThreshold + 5 − 1` executions; on skewed data that generic plan may be wrong for some values.
- Use **`force_custom_plan`** when per-value plan quality matters more than planning cost (skewed predicates). Use **`force_generic_plan`** when planning cost dominates and data is uniform.
- `plan_cache_mode` is irrelevant to literal SQL (Scenarios 3 & 4) — it only governs server-side prepared statements.
- Watch out for first-execution cost when micro-benchmarking: the same plan can look 100×+ slower on its first run.

## Running it

Edit the connection details in `JdbcPreparedPlanCacheModeDemo.java` (host, user,
password — the committed values are placeholders), then compile and run with the
pgjdbc driver on the classpath:

```bash
javac JdbcPreparedPlanCacheModeDemo.java
java -cp .:postgresql-<version>.jar JdbcPreparedPlanCacheModeDemo
```

The program creates table `t`, runs all 36 test combinations (logging each plan
via `auto_explain`), and drops the table at the end.
