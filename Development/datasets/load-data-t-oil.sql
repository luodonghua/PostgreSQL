
CREATE TABLE t_oil ( region text,
     country     text,
     year        int,
     production  int,
     consumption int
   );

/*
ERROR:  must be superuser or a member of the pg_execute_server_program role to COPY to or from an external program
HINT:  Anyone can COPY to stdout or from stdin. psql's \copy command also works for anyone.
*/

\COPY t_oil FROM PROGRAM 'curl https://www.cybertec-postgresql.com/secret/oil_ext.txt';

create index t_oil_country on t_oil(country);

vacuum analyze t_oil;

SELECT region, country, avg(production) FROM t_oil
WHERE  country IN ('USA', 'Canada', 'Iran', 'Oman')
GROUP BY ROLLUP (region, country);


EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS)
SELECT region, country, avg(production) FROM t_oil
WHERE  country IN ('USA', 'Canada', 'Iran', 'Oman')
GROUP BY ROLLUP (region, country);