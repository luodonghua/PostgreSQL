

-- Verify that there are no open prepared transactions on your instance:

SELECT count(*) FROM pg_catalog.pg_prepared_xacts;

-- Verify that no uses of unsupported reg* data types
-- With the exception of regtype and regclass, reg* data types cannot be upgraded

select count(*) 
  from pg_catalog.pg_class c, pg_catalog.pg_namespace n, pg_catalog.pg_attribute a
 where c.oid = a.attributelid
   and not a.attisdropped
   and a.atttypid in ('pg_catalog.regproc'::pg_catalog.regtype,
                      'pg_catalog.regprocedure'::pg_catalog.regtype,
                      'pg_catalog.regoper'::pg_catalog.regtype,
                      'pg_catalog.regoperator'::pg_catalog.regtype,
                      'pg_catalog.regconfig'::pg_catalog.regtype,
                      'pg_catalog.regdictionary'::pg_catalog.regtype)
    and c.relnamespace = n.oid
    and n.nspname not in ('pg_catalog','information_schema');

-- List currently installed extensions
select * from pg_extention;

-- View a list of specific extension versions
-- use below SQL to update the extension:
--   alter extension pg-extenstion update to 'new-version'
select * from pg_aailable_extension_versions;

-- PostgreSQL version 10 stopped supporting the 'unknown' data type
-- drop unknown data types before upgrading

-- The key word ILIKE can be used instead of LIKE to make the match case-insensitive according to the active locale. 
select distinct data_type from information_schema.columns where data_type ilike 'unknown';



