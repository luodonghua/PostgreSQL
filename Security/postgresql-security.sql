/* 
   Objects need owners. 
   Whenever a user creates an object, they become the owner by default. 
   Users can also create an object on behalf of another user. 
   The owner has full control over the object. 
   Only the owner of an object can drop the object.
*/

/*
DB object privileges allow a user to take specific actions. These privileges are:
   - CREATE:   The user can create a new database. This should be reserved for DBAs.
   - CONNECT:  The user can connect to the database. 
               This privilege is typically used for the general user 
               because all users need to connect to the database to use PostgreSQL.
   - TEMP:     The user can create temporary tables while using the database.
*/


-- PostgreSQL super users and any role created with the BYPASSRLS attribute aren’t subject to table policies.

create table t (id int, owner varchar(10));
alter table t enable row level security;
insert into t values (1,'postgres'),(2,'abc');
create policy pol1 on t for select using (owner=current_user);


-- Enable Auditing
-- Sure following parameters are included in the parameter groups
--    - pgaudit.role: 'rds_pgaudit'
--    - shared_preload_libraries: 'pgaudit'
create role rds_pgaudit;
create extension pgaudit;


/*
-- Sample PGAudit Entry:
--   clent ip:                116.14.204.216    
--   client login username:   postgres          
--   database:                mytest           
--   action:                  drop table t3  

2021-10-30 07:23:56 UTC:116.14.204.216(50222):postgres@mytest:[28180]:LOG:  AUDIT: SESSION,1,1,DDL,DROP TABLE,TABLE,public.t3,drop table t3;,<not logged>

*/

