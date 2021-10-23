-- set the variable start_date, later can be refereced as :'start_date'
\set start_date '2020-01-01'


-- date:'start_date' has the same cast effect as :'start_date'::date
-- format patterns:
--   - Value with specificd number of digits
--   - L is the currrency symbol based on locale
--   - G is the group seperator, based on locale

select trade_date, to_char(consolidated_type_a,'999G999.99') as "consolidated type a" 
  from daily_equaity_volumes
where trade_date > date:'start_date'
 and  trade_date < date:'start_date' + interval '1 month'
order by trade_date;

select trade_date, to_char(consolidated_type_a,'999G999.99') as "consolidated type a" 
 from daily_equaity_volumes
where trade_date >= :'start_date'::date
 and  trade_date < :'start_date'::date + interval '7 day'
order by trade_date;

-- deallocate prepare foo if exists
deallocate prepare foo;

prepare foo as
 select trade_date, to_char(consolidated_type_a,'999G999.99') as "consolidated type a" 
   from daily_equaity_volumes
where trade_date >= $1::date
 and  trade_date < $1::date + interval '7 day'
order by trade_date;

execute foo('2020-01-01');


select calendar.entry as trade_date,
       to_char(coalesce(consolidated_type_a,0),'999G999.99') as "consolidated type a",
       to_char(coalesce(consolidated_type_b,0),'L000G000D00') as "consolidated type b",
       coalesce(consolidated_type_c,0) as "consolidated type c"   
from generate_series (date:'start_date', 
                      date:'start_date' + interval '6 day',
                      interval '1 day'
     ) as calendar(entry)
     left join daily_equaity_volumes dev
            on dev.trade_date = calendar.entry
order by calendar.entry;

