create table p1 (id int, name varchar(100));
create table p2 (id int, name varchar(100));
create table c (id int, name varchar(100),pid1 int, pid2 int);
alter table p1 add constraint p1_pk primary key (id);
alter table p2 add constraint p2_pk primary key (id);
alter table c  add constraint c_pk  primary key (id);
create index idx_c_pid1 on c(pid1);
create index idx_c_pid2 on c(pid2);

insert into p1
select generate_series,'p1-'||generate_series::text from generate_series(1,10000);


insert into p2
select generate_series,'p2-'||generate_series::text from generate_series(1,1000);

insert into c
select generate_series,'p1-'||generate_series::text,
       floor(random()*10000+1), floor(random()*1000+1) from generate_series(1,10000000);



explain analyze verbose
select c.id,c.name,p1.name from c,p1 where c.pid1=p1.id and p1.id=100;

/*+ MergeJoin (c p1) */
explain analyze verbose
select c.id,c.name,p1.name from c,p1 where c.pid1=p1.id;

/*+ HashJoin (c p1) */
explain analyze verbose
select c.id,c.name,p1.name from c,p1 where c.pid1=p1.id;

explain analyze verbose
select c.id,c.name,p1.name,p2.name from c,p1,p2 
where c.pid1=p1.id and c.pid2=p2.id and p1.id=100 and p2.id=100;

explain 
select c.id,c.name,p1.name,p2.name from c,p1,p2 
where c.pid1=p1.id and c.pid2=p2.id and p1.id=100 and p2.id=100;

explain
with v as materialized (select c.id,c.name,c.pid2,p1.name pname1 
                          from c,p1 where c.pid1=p1.id and p1.id=100) 
select v.id,v.name,v.pname1,p2.name from v,p2 
where v.pid2=p2.id and p2.id=100;


