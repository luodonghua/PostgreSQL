# Table Partitioning: Range, Sub-partitioning, and the Cost of Going Too Deep

A walkthrough of declarative range partitioning in PostgreSQL — creating
partitions and sub-partitions, inspecting the partition tree, attach/detach for
data lifecycle, and a cautionary benchmark showing how **deeply nested**
sub-partitioning wrecks planning time.

## Range-partitioned table

```sql
CREATE TABLE sales (
  id bigserial,
  sales_date date NOT NULL,
  sales_amount money,
  CONSTRAINT sales_pk PRIMARY KEY (id, sales_date)   -- PK must include the partition key
) PARTITION BY RANGE (sales_date);

CREATE TABLE sales_p_2020 PARTITION OF sales FOR VALUES FROM ('2020-01-01') TO ('2021-01-01');
CREATE TABLE sales_p_2021 PARTITION OF sales FOR VALUES FROM ('2021-01-01') TO ('2022-01-01');
```

```text
mytest=> \d+ sales
Partition key: RANGE (sales_date)
Indexes:
    "sales_pk" PRIMARY KEY, btree (id, sales_date)
Partitions: sales_p_2020 FOR VALUES FROM ('2020-01-01') TO ('2021-01-01'),
            sales_p_2021 FOR VALUES FROM ('2021-01-01') TO ('2022-01-01')
```

## Sub-partitioning (one level)

A partition can itself be partitioned — here 2022 is split by month:

```sql
CREATE TABLE sales_p_2022 PARTITION OF sales
  FOR VALUES FROM ('2022-01-01') TO ('2023-01-01') PARTITION BY RANGE (sales_date);

CREATE TABLE sales_p_2022_jan PARTITION OF sales_p_2022 FOR VALUES FROM ('2022-01-01') TO ('2022-02-01');
CREATE TABLE sales_p_2022_feb PARTITION OF sales_p_2022 FOR VALUES FROM ('2022-02-01') TO ('2022-03-01');
CREATE TABLE sales_p_2022_mar PARTITION OF sales_p_2022 FOR VALUES FROM ('2022-03-01') TO ('2022-04-01');
```

## Inspecting the partition tree

```sql
SELECT * FROM pg_partition_tree('sales');
```

```text
      relid       | parentrelid  | isleaf | level
------------------+--------------+--------+-------
 sales            |              | f      |     0
 sales_p_2020     | sales        | t      |     1
 sales_p_2021     | sales        | t      |     1
 sales_p_2022     | sales        | f      |     1
 sales_p_2022_jan | sales_p_2022 | t      |     2
 sales_p_2022_feb | sales_p_2022 | t      |     2
 sales_p_2022_mar | sales_p_2022 | t      |     2
(7 rows)
```

## Partition pruning

Load ~2.7M random rows, then query one month — only the matching leaf partition
is scanned:

```sql
WITH v AS (
  SELECT '2020-01-01'::date + (random()*(365*2+90))::int AS sales_date,
         random()*10000::money AS sales_amount
  FROM generate_series(1,2700000))
INSERT INTO sales(sales_date, sales_amount) SELECT * FROM v;

EXPLAIN (ANALYZE, VERBOSE)
SELECT sum(sales_amount) FROM sales WHERE sales_date='2022-02-01'::date;
```

```text
 Aggregate ...
   ->  Seq Scan on public.sales_p_2022_feb sales  (... rows=3244 ...)
         Filter: (sales.sales_date = '2022-02-01'::date)
         Rows Removed by Filter: 89575
 Execution Time: 8.522 ms
```

Row counts per partition via `tableoid`:

```sql
SELECT tableoid::regclass AS partition, count(*) FROM sales GROUP BY partition;
```

```text
    partition     |  count
------------------+---------
 sales_p_2020     | 1203782
 sales_p_2021     | 1201342
 sales_p_2022_jan |  101849
 sales_p_2022_feb |   92819
 sales_p_2022_mar |  100208
```

## Data lifecycle: drop, detach, attach

```sql
DROP TABLE sales_p_2020;                       -- drop old data instantly

ALTER TABLE sales DETACH PARTITION sales_p_2021;  -- keep data, remove from parent
-- sales_p_2021 still has its 1,201,342 rows as a standalone table

-- build a replacement table and attach it as the 2021 partition
CREATE TABLE sales_2021 (LIKE sales INCLUDING DEFAULTS INCLUDING CONSTRAINTS);
INSERT INTO sales_2021 SELECT * FROM sales_p_2021;
ALTER TABLE sales ATTACH PARTITION sales_2021 FOR VALUES FROM ('2021-01-01') TO ('2022-01-01');
```

Detach/attach is how you roll partitions in and out without touching the rest of
the table — ideal for time-based retention.

## Warning: deep nested sub-partitioning destroys planning time

Three tables holding the same data were compared:

- **`t1`** — not partitioned.
- **`t2`** — 1,000 sibling partitions (flat): `t2_p_1 .. t2_p_1000`, each `FOR VALUES FROM (i) TO (i+1)`.
- **`t3`** — 1,000 **levels** of nesting: `t3_p_1` partitions `t3`, `t3_p_2` partitions `t3_p_1`, … 1000 deep.

Both `t2` and `t3` were generated with a bash loop (sample):

```bash
# flat (t2)
for i in {1..1000}; do
  echo "create table t2_p_${i} partition of t2 for values from ($i) to ($((i+1)));"
done
```

### Single-row INSERT

```text
t1 (no partition):      Execution Time: 0.108 ms
t2 (1000 flat):         Execution Time: 4.936 ms
t3 (1000 nested):       Execution Time: 780.885 ms   <-- 7000x+ worse
```

### SELECT by key (`id=1000`)

```text
t1:   Planning 0.055 ms   Execution 0.057 ms
t2:   Planning 0.067 ms   Execution 0.065 ms   (pruned to t2_p_1000)
t3:   Planning 723.508 ms Execution 0.607 ms   <-- planning dominated by nesting depth
```

### Bulk insert of 1000 rows via PL/pgSQL loop

```text
t1:   Time: 250.741 ms
t2:   Time: 255.405 ms
t3:   Time: 129140.941 ms (02:09)   <-- pathological
```

## Takeaways

- Declarative range partitioning gives clean **pruning** (only relevant leaf partitions are scanned) and cheap data lifecycle via **DETACH/ATTACH/DROP**.
- The primary key must include the partition key.
- **A moderate number of flat partitions (`t2`) is fine** — planning/execution stay close to the non-partitioned table.
- **Deep nesting (`t3`) is pathological**: planning time grows with nesting depth because the planner must walk the whole tree, turning sub-millisecond operations into hundreds of ms (and a 1000-row loop into 2+ minutes). Keep partition hierarchies shallow (one, occasionally two, levels) and prefer a reasonable number of partitions over extreme counts.
