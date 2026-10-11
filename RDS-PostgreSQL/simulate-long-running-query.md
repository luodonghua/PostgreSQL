# Simulating a Long-Running Query

A small recipe for generating a controllable long-running query on PostgreSQL —
useful for testing statement timeouts, lock/replication conflicts, monitoring
views (`pg_stat_activity`), and read-replica cancellation behavior.

The trick is `pg_sleep()` inside a correlated subquery so that total query
duration ≈ `sleep_time × row_count`.

## Setup: a table with some rows

```sql
CREATE TABLE t1 (id int);
```

Load rows with a quick shell loop (any volume works; a few hundred is enough):

```bash
i=1
while [ $i -le 100000 ]
do
  psql -c "insert into t1 values ($i)"
  i=$(( $i + 1 ))
  echo $i
done
```

## Generate a long-running query

`pg_sleep(0.2)` runs for each of the 10 rows produced by the subquery, so the
statement takes ~2 seconds:

```sql
SELECT t1.*
FROM t1,
     (SELECT *, pg_sleep(0.2) FROM t1 ORDER BY id DESC LIMIT 10) t
WHERE t1.id = t.id;
```

```text
 id
-----
 248
 249
 250
 251
 252
 253
 254
 255
 256
 257
(10 rows)

Time: 2256.299 ms (00:02.256)
```

Tune the duration by changing the sleep interval or the `LIMIT`
(duration ≈ `sleep_time × row_count`).

## Confirm where the time goes with EXPLAIN ANALYZE

```sql
EXPLAIN (ANALYZE, VERBOSE)
SELECT t1.*
FROM t1,
     (SELECT *, pg_sleep(0.2) FROM t1 ORDER BY id DESC LIMIT 10) t
WHERE t1.id = t.id;
```

```text
                                                 QUERY PLAN
------------------------------------------------------------------------------------------------------------
 Hash Join  (cost=14.77..22.26 rows=10 width=4) (actual time=2021.169..2021.174 rows=10 loops=1)
   Output: t1.id
   Hash Cond: (t1.id = t.id)
   ->  Seq Scan on public.t1  (cost=0.00..5.92 rows=392 width=4) (actual time=0.015..0.037 rows=246 loops=1)
         Output: t1.id
   ->  Hash  (cost=14.64..14.64 rows=10 width=4) (actual time=2021.083..2021.084 rows=10 loops=1)
         Output: t.id
         Buckets: 1024  Batches: 1  Memory Usage: 9kB
         ->  Subquery Scan on t  (cost=14.39..14.64 rows=10 width=4) (actual time=202.171..2021.041 rows=10 loops=1)
               Output: t.id
               ->  Limit  (cost=14.39..14.54 rows=10 width=8) (actual time=202.170..2020.979 rows=10 loops=1)
                     Output: t1_1.id, (pg_sleep('0.2'::double precision))
                     ->  Result  (cost=14.39..20.27 rows=392 width=8) (actual time=202.169..2020.966 rows=10 loops=1)
                           Output: t1_1.id, pg_sleep('0.2'::double precision)
                           ->  Sort  (cost=14.39..15.37 rows=392 width=4) (actual time=0.087..0.096 rows=10 loops=1)
                                 Output: t1_1.id
                                 Sort Key: t1_1.id DESC
                                 Sort Method: top-N heapsort  Memory: 25kB
                                 ->  Seq Scan on public.t1 t1_1  (cost=0.00..5.92 rows=392 width=4) (actual time=0.006..0.034 rows=246 loops=1)
                                       Output: t1_1.id
 Planning time: 0.131 ms
 Execution time: 2021.212 ms
(22 rows)

Time: 2255.492 ms (00:02.255)
```

The ~2 s is spent in the `Result` node evaluating `pg_sleep` for the 10 limited
rows (`actual time=202.169..2020.966`), confirming the duration is driven by the
sleep calls rather than data volume.
