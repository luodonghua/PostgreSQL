sudo amazon-linux-extras list |grep -i postgres

# [ec2-user@ip-10-1-1-60 ~]$ sudo amazon-linux-extras list |grep -i postgres
#  5  postgresql9.6            available    \
#  6  postgresql10             available    [ =10  =stable ]
# 41  postgresql11             available    [ =11  =stable ]
# 58  postgresql12             available    [ =stable ]
# 59  postgresql13=latest      enabled      [ =stable ]


sudo amazon-linux-extras install postgresql13
sudo yum install postgresql-server postgresql postgresql-contrib -y
sudo /usr/bin/postgresql-setup initdb


# [ec2-user@ip-10-1-1-60 ~]$ sudo /usr/bin/postgresql-setup initdb
# WARNING: using obsoleted argument syntax, try --help
# WARNING: arguments transformed to: postgresql-setup --initdb --unit postgresql
# * Initializing database in '/var/lib/pgsql/data'
# * Initialized, logs are in /var/lib/pgsql/initdb_postgresql.log

sudo systemctl list-unit-files|grep postgresql

#
# [ec2-user@ip-10-1-1-60 ~]$ sudo systemctl list-unit-files|grep postgresql
# postgresql.service                            disabled
# postgresql@.service                           disabled
#

sudo systemctl enable postgresql.service 
sudo systemctl start postgresql.service   

# [ec2-user@ip-10-1-1-60 ~]$ sudo su - postgres

# -bash-4.2$ psql
# psql (13.3)
# Type "help" for help.

# postgres=# \conninfo
# You are connected to database "postgres" as user "postgres" via socket in "/var/run/postgresql" at port "5432".
# postgres=# select version();
#                                                  version                                                  
# -----------------------------------------------------------------------------------------------------------
# PostgreSQL 13.3 on x86_64-koji-linux-gnu, compiled by gcc (GCC) 7.3.1 20180712 (Red Hat 7.3.1-13), 64-bit
# (1 row)

