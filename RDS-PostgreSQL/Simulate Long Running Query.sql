/*
mytest=> create table t1 (id int);
CREATE TABLE
                                                              
i=1
while [ $i -le 100000 ]
do
psql -c "insert into t1 values ($i)" 
i=$(( $i + 1 ))
echo $i
done
*/

-- play with pg_sleep() function with different timing, query duration ~ sleep_time x row_count

mytest=> select t1.* from t1, (select *,pg_sleep(0.2) from t1 order by id desc limit 10) t where t1.id=t.id;
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



mytest=> explain analyze verbose select t1.* from t1, (select *,pg_sleep(0.2) from t1 order by id desc limit 10) t where t1.id=t.id;
                                                                   QUERY PLAN                                                                   
------------------------------------------------------------------------------------------------------------------------------------------------
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
