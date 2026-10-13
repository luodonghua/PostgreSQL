# Maintenance parameters and how they relate

Vacuum, analyze, and autovacuum are controlled by a web of GUCs (server
settings) that interact in ways that are easy to misconfigure. This page lists
them by role and — more importantly — explains **how they relate**. Defaults
below are PostgreSQL's shipped values; confirm yours with
`SHOW name;` or `SELECT name, setting, unit FROM pg_settings WHERE name LIKE '%vacuum%';`.

## The big picture

```
                       autovacuum = on
                             │
         launcher wakes every autovacuum_naptime
                             │  (divided among databases)
                             ▼
   pick a database ──► pick tables over threshold ──► run vacuum/analyze
   (datfrozenxid /       (scale_factor + threshold)      under a shared
    oldest attention)     per-table counters             I/O cost budget
                             │                                 │
          ┌──────────────────┼───────────────────┐            │
          ▼                  ▼                   ▼             ▼
   dead-tuple vacuum   insert vacuum         analyze     cost_delay / cost_limit
   (bloat)             (freeze/VM)           (planner       balanced across
                                             stats)         max_workers
                             │
                   age(relfrozenxid) ≥ freeze_max_age
                             ▼
                FORCED anti-wraparound vacuum (always, even if off)
```

Three independent questions drive everything:

1. **Is there too much bloat?** → dead-tuple and insert thresholds.
2. **Are the planner's statistics stale?** → analyze threshold.
3. **Is the table too old (wraparound risk)?** → freeze ages.

Each has a "normal" knob and a "safety" knob, and the safety knob always wins.

## Enabling / scheduling

| Parameter | Default | Role |
|-----------|---------|------|
| `autovacuum` | `on` | master switch. **Leave on.** Even `off` still forces anti-wraparound vacuums. |
| `track_counts` | `on` | required for autovacuum to see dead/modified counts. Off ⇒ autovacuum is effectively blind. |
| `autovacuum_naptime` | `60s` | launcher sleep between wakeups; **split across databases**. Many databases ⇒ each is visited less often; lower it if you have dozens of busy DBs. |
| `autovacuum_max_workers` | `3` | max concurrent workers cluster-wide. More workers ≠ more total I/O (budget is shared), but ≠ free either (each needs `autovacuum_work_mem`). |

## Trigger thresholds (which tables get processed)

These feed `relation_needs_vacanalyze()` — see
[autovacuum.md](autovacuum.md#picking-tables-the-worker).

### Dead-tuple vacuum

```
vacuum threshold = autovacuum_vacuum_threshold
                 + autovacuum_vacuum_scale_factor * reltuples
                 (clamped to autovacuum_vacuum_max_threshold, if ≥ 0)
```

| Parameter | Default | Role |
|-----------|---------|------|
| `autovacuum_vacuum_threshold` | `50` | flat floor so tiny tables still vacuum |
| `autovacuum_vacuum_scale_factor` | `0.2` | fraction of the table's rows of dead tuples before vacuuming |
| `autovacuum_vacuum_max_threshold` | `100000000` *(20devel; `-1` disables cap)* | upper bound so huge tables don't wait for an absurd dead-tuple count |

### Insert vacuum (freezing append-heavy tables)

```
insert threshold = autovacuum_vacuum_insert_threshold
                 + autovacuum_vacuum_insert_scale_factor * reltuples * pct_unfrozen
```

| Parameter | Default | Role |
|-----------|---------|------|
| `autovacuum_vacuum_insert_threshold` | `1000` (`-1` disables) | vacuum after this many inserts, to set VM bits / freeze |
| `autovacuum_vacuum_insert_scale_factor` | `0.2` | insert fraction, weighted by the still-unfrozen portion |

### Analyze

```
analyze threshold = autovacuum_analyze_threshold
                  + autovacuum_analyze_scale_factor * reltuples
```

| Parameter | Default | Role |
|-----------|---------|------|
| `autovacuum_analyze_threshold` | `50` | flat floor |
| `autovacuum_analyze_scale_factor` | `0.1` | fraction of rows changed before re-analyzing |

**Relationship — scale_factor vs. table size.** Because the trigger scales with
`reltuples`, the *absolute* amount of tolerated bloat grows with the table. A
0.2 scale factor means a 1k-row table vacuums at ~250 dead rows but a
100M-row table waits for ~20M. This is the single most common tuning mistake.
See [large, busy tables](#large-busy-tables).

## Freeze / wraparound (the safety layer)

| Parameter | Default | Role |
|-----------|---------|------|
| `vacuum_freeze_min_age` | `50000000` | minimum tuple age to freeze during any vacuum |
| `vacuum_freeze_table_age` | `150000000` | table age that makes the next vacuum **aggressive** (scan all unfrozen pages) |
| `autovacuum_freeze_max_age` | `200000000` | age of `relfrozenxid` that **forces** an anti-wraparound autovacuum |
| `vacuum_failsafe_age` | `1600000000` | age at which vacuum drops cost delay and **skips index cleanup** to race wraparound |
| `vacuum_multixact_freeze_min_age` | `5000000` | MultiXact equivalent of `freeze_min_age` |
| `vacuum_multixact_freeze_table_age` | `150000000` | MultiXact equivalent of `freeze_table_age` |
| `autovacuum_multixact_freeze_max_age` | `400000000` | MultiXact equivalent of `freeze_max_age` |
| `vacuum_multixact_failsafe_age` | `1600000000` | MultiXact failsafe |

**Required ordering** (PostgreSQL enforces/clamps these; keep them sane):

```
vacuum_freeze_min_age  <  vacuum_freeze_table_age  <  autovacuum_freeze_max_age  <  vacuum_failsafe_age
```

If you raise `autovacuum_freeze_max_age` to reduce how often anti-wraparound
vacuums fire on a huge, slowly-changing table, keep plenty of headroom below the
~2-billion hard limit — and remember it makes each forced vacuum **bigger**.
`vacuum_freeze_min_age` too high ⇒ tuples rarely freeze ⇒ `relfrozenxid` barely
advances ⇒ more frequent forced vacuums. Too low ⇒ you freeze tuples that may be
updated again soon, wasting work.

See [vacuum.md](vacuum.md#freezing-and-xid-wraparound) for the mechanism and
[freeze.gif](animations/freeze.gif) for the picture.

## Cost-based delay

Autovacuum throttles itself so background maintenance doesn't saturate disk I/O.
It accumulates a **cost** as it touches buffers and sleeps when the cost crosses
a limit.

| Parameter | Default | Role |
|-----------|---------|------|
| `autovacuum_vacuum_cost_limit` | `-1` → inherits `vacuum_cost_limit` (`200`) | cost budget before sleeping |
| `autovacuum_vacuum_cost_delay` | `2ms` | sleep length when the budget is spent |
| `vacuum_cost_page_hit` / `_miss` / `_dirty` | `1` / `2` / `20` | cost charged per shared-buffer hit, miss, dirty |

**Relationship — balancing across workers.** The limit is a **cluster-wide
budget shared by all active workers**. With 3 workers running, each gets ~1/3
the throughput — so raising `autovacuum_max_workers` does **not** multiply I/O
impact; it mostly spreads the same budget thinner. To make autovacuum *faster*
on a big table, **raise `cost_limit`** or **lower `cost_delay`**, don't just add
workers. Setting a per-table `autovacuum_vacuum_cost_delay`/`_limit` opts that
table **out** of the shared balancing.

## Memory

| Parameter | Default | Role |
|-----------|---------|------|
| `maintenance_work_mem` | `64MB` | memory for a **manual** `VACUUM`'s dead-TID store and for index builds |
| `autovacuum_work_mem` | `-1` → inherits `maintenance_work_mem` | per-worker memory for autovacuum's dead-TID store |

**Relationship — memory vs. index passes.** If the dead-TID store fills up,
vacuum must do Phase II/III and resume Phase I (an extra index pass per fill —
see [vacuum.md](vacuum.md#the-tid-store-can-fill-mid-scan)). More memory ⇒ fewer
passes ⇒ faster vacuum of very bloated tables. But remember each of
`autovacuum_max_workers` can use `autovacuum_work_mem`, so budget
`max_workers × autovacuum_work_mem` of RAM.

## Statistics detail

| Parameter | Default | Role |
|-----------|---------|------|
| `default_statistics_target` | `100` | sample size = `300 × target` rows; also # of MCV/histogram entries |
| per-column `SET STATISTICS n` | — | override the target for one column |

See [analyze.md](analyze.md#tuning-the-sample-statistics_target).

## Prioritization score weights *(20devel)*

| Parameter | Default | Role |
|-----------|---------|------|
| `autovacuum_vacuum_score_weight` | `1.0` | weight of the dead-tuple ratio in the sort score |
| `autovacuum_vacuum_insert_score_weight` | `1.0` | weight of the insert ratio |
| `autovacuum_analyze_score_weight` | `1.0` | weight of the analyze ratio |
| `autovacuum_freeze_score_weight` | `1.0` | weight of the XID-age ratio |
| `autovacuum_multixact_freeze_score_weight` | `1.0` | weight of the MultiXact-age ratio |

Each ranges `0.0`–`10.0`. All `0.0` ⇒ pre-v19 ordering. Raise one to make that
dimension dominate the order in which overdue tables are picked. See
[autovacuum.md](autovacuum.md#prioritizing-scores).

## Worked tuning recipes

### Large, busy tables

The default scale factor lets big tables bloat badly. Override per table:

```sql
ALTER TABLE events SET (
    autovacuum_vacuum_scale_factor  = 0.01,   -- 1% instead of 20%
    autovacuum_vacuum_threshold     = 10000,
    autovacuum_analyze_scale_factor = 0.005,
    autovacuum_analyze_threshold    = 10000
);
```

Or cluster-wide, cap the absolute dead-tuple count instead of chasing a
fraction (20devel):

```sql
ALTER SYSTEM SET autovacuum_vacuum_max_threshold = 1000000;  -- vacuum by ~1M dead rows
```

### Autovacuum can't keep up (bloat grows despite running)

Give it more throughput, not just more workers:

```sql
ALTER SYSTEM SET autovacuum_vacuum_cost_limit = 2000;  -- 10x the default budget
ALTER SYSTEM SET autovacuum_vacuum_cost_delay = '2ms';
ALTER SYSTEM SET autovacuum_work_mem = '512MB';        -- fewer index passes
SELECT pg_reload_conf();
```

### `relfrozenxid` age keeps climbing

First check for something **holding back the xmin horizon** — autovacuum cannot
reclaim or freeze what an old snapshot still needs:

```sql
-- long-running transactions
SELECT pid, state, xact_start, now() - xact_start AS age, query
FROM   pg_stat_activity
WHERE  state <> 'idle' AND xact_start IS NOT NULL
ORDER  BY xact_start;

-- abandoned replication slots and prepared transactions pin the horizon too
SELECT slot_name, active, age(xmin) AS xmin_age FROM pg_replication_slots;
SELECT gid, prepared, age(transaction) AS age FROM pg_prepared_xacts;
```

No amount of autovacuum tuning helps until the holder is released.

### Insert-only / append tables

They have few dead tuples (so dead-tuple vacuum rarely triggers) but still need
freezing and VM bits. The **insert threshold** handles this out of the box
(default on). Make sure `autovacuum_vacuum_insert_threshold` is not set to `-1`.

## Where to look next

- Mechanism: [vacuum.md](vacuum.md), [analyze.md](analyze.md)
- Decision logic + animations: [autovacuum.md](autovacuum.md)
- Operational monitoring:
  [`monitor-autovacuum.md`](monitor-autovacuum.md),
  [`postgresql-maintenance.md`](postgresql-maintenance.md)
