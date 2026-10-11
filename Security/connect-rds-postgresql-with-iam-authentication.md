# IAM Authentication to RDS for PostgreSQL

Amazon RDS for PostgreSQL can authenticate database users with AWS IAM instead
of a stored password. Instead of a static password, the client generates a
short-lived authentication **token** with the AWS CLI and passes it where psql
expects the password. This walkthrough enables IAM auth, grants the role,
generates a token, connects with `psql`, and inspects the SSL properties of the
session.

> The demonstration used an A Cloud Guru sandbox; all accounts and tokens have
> since been reset.

## Confirm identity and IAM-auth status

Check the current IAM caller, then confirm the DB instance has IAM database
authentication enabled:

```bash
aws sts get-caller-identity --query 'Arn' --output text
```

```text
arn:aws:iam::853595176342:user/cloud_user
```

```bash
aws rds describe-db-instances --db-instance-identifier postgres-instance1 \
 --query 'DBInstances[0].{Dbi:DbiResourceId,Arn:DBInstanceArn,Iam:IAMDatabaseAuthenticationEnabled}'
```

```text
{
    "Dbi": "db-IYF56K6FHWKHL2MAPU6TQPOTSE",
    "Arn": "arn:aws:rds:us-east-1:853595176342:db:postgres-instance1",
    "Iam": true
}
```

The `DbiResourceId` (`db-IYF56K6FHWKHL2MAPU6TQPOTSE`) is the stable resource id
used to scope the IAM policy below.

## The `rds-db:connect` IAM policy

The IAM principal needs permission to request a connection token. The policy
action is `rds-db:connect`, and the resource ARN combines the instance resource
id with the database username:

```json
{
   "Version": "2012-10-17",
   "Statement": [
      {
         "Effect": "Allow",
         "Action": [
             "rds-db:connect"
         ],
         "Resource": [
             "arn:aws:rds-db:us-east-1:853595176342:dbuser:db-IYF56K6FHWKHL2MAPU6TQPOTSE/cloud_user",
         ]
      }
   ]
}
```

In the A Cloud Guru sandbox attaching this policy was not strictly necessary,
since `cloud_user` already has broad privileges — but this is the policy you
would attach to the IAM user `853595176342:user/cloud_user` in a real account.

## Create the database role and grant `rds_iam`

The database side needs a role that is allowed to authenticate via IAM. Granting
the predefined `rds_iam` role to a user tells RDS to authenticate that user with
IAM tokens:

```sql
create user cloud_user;
grant rds_iam to cloud_user;
```

```text
mytest=> create user cloud_user;
CREATE ROLE
mytest=> grant rds_iam to cloud_user;
GRANT ROLE
```

## Generate an auth token as `PGPASSWORD`

`aws rds generate-db-auth-token` produces a signed, time-limited token. Export
it as `PGPASSWORD` so psql picks it up transparently:

```bash
export RDSHOST="postgres-instance1.ck4o6l6o9kyg.us-east-1.rds.amazonaws.com"
export PGPASSWORD="$(aws rds generate-db-auth-token --hostname $RDSHOST --port 5432 --region us-east-1 --username cloud_user )"
```

The token is a presigned URL-style string (shown here manually wrapped across
several lines for readability). Note the `Action=connect`, the signing
credential, and `X-Amz-Expires=900` — the token is valid for 15 minutes:

```text
# output below manually broken into multiple lines for reading
echo $PGPASSWORD 
postgres-instance1.ck4o6l6o9kyg.us-east-1.rds.amazonaws.com:5432/?
Action=connect&DBUser=cloud_user&X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=
AKIA4NPR4XWLDEIKZQLQ%2F20211030%2Fus-east-1%2Frds-db%2Faws4_request&X-Amz-Date=20211030T025117Z&
X-Amz-Expires=900&X-Amz-SignedHeaders=host&
X-Amz-Signature=99b4b724ff566e2a30db834b5f49727a4cf2de4da91ac6a721711cd3bc506499
```

## Connect with psql

With `PGPASSWORD` set to the token, connect normally:

```bash
psql "host=$RDSHOST port=5432 dbname=mytest user=cloud_user password=$PGPASSWORD"
```

```text
psql (13.4)
SSL connection (protocol: TLSv1.2, cipher: ECDHE-RSA-AES256-GCM-SHA384, bits: 256, compression: off)
Type "help" for help.
```

IAM authentication **requires** SSL/TLS, so the connection is encrypted. Confirm
with the server functions `ssl_is_used()` and `ssl_cipher()`:

```sql
select ssl_is_used(), ssl_cipher();
```

```text
 ssl_is_used |         ssl_cipher          
-------------+-----------------------------
 t           | ECDHE-RSA-AES256-GCM-SHA384
(1 row)
```

## SSL mode descriptions

libpq offers several `sslmode` settings, trading overhead for assurance:

```text
 - disable: I don't care about security, and I don't want to pay the overhead of encryption.
 - allow: I don't care about security, but I will pay the overhead of encryption if the server insists on it.
 - prefer: I don't care about encryption, but I wish to pay the overhead of encryption if the server supports it.
 - require: I want my data to be encrypted, and I accept the overhead. I trust that the network will make sure I always connect to the server I want.
 - verify-ca: I want my data encrypted, and I accept the overhead. I want to be sure that I connect to a server that I trust.
 - verify-full: I want my data encrypted, and I accept the overhead. I want to be sure that I connect to a server I trust, and that it's the one I specify.
```

`prefer` is the default mode.

The difference between `verify-ca` and `verify-full` depends on the policy of
the root CA. If a public CA is used, `verify-ca` allows connections to a server
that somebody else may have registered with the CA. In this case, `verify-full`
should always be used. If a local CA is used, or even a self-signed certificate,
using `verify-ca` often provides enough protection.

## Connect with `sslmode=verify-full`

For the strongest guarantee, use `sslmode=verify-full` with the RDS global CA
bundle (`global-bundle.pem`) as `sslrootcert`. This verifies both the
certificate chain and that the server hostname matches the certificate:

```bash
psql "host=$RDSHOST port=5432 sslmode=verify-full sslrootcert=./global-bundle.pem dbname=mytest user=cloud_user password=$PGPASSWORD"
```

```text
psql (13.4)
SSL connection (protocol: TLSv1.2, cipher: ECDHE-RSA-AES256-GCM-SHA384, bits: 256, compression: off)
Type "help" for help.
```

```sql
select ssl_is_used(), ssl_cipher();
```

```text
 ssl_is_used |         ssl_cipher          
-------------+-----------------------------
 t           | ECDHE-RSA-AES256-GCM-SHA384
(1 row)
```

`\conninfo` confirms the host, address, and the negotiated TLS parameters:

```text
mytest=> \conninfo
You are connected to database "mytest" as user "cloud_user" on host "postgres-instance1.ck4o6l6o9kyg.us-east-1.rds.amazonaws.com" (address "44.198.93.36") at port "5432".
SSL connection (protocol: TLSv1.2, cipher: ECDHE-RSA-AES256-GCM-SHA384, bits: 256, compression: off)
```

## Takeaways

- IAM auth replaces the static database password with a short-lived token
  (`X-Amz-Expires=900`, i.e. 15 minutes) generated by
  `aws rds generate-db-auth-token`, exported as `PGPASSWORD`.
- Two sides must be configured: an IAM policy allowing `rds-db:connect` on the
  `dbuser` ARN (scoped by the instance `DbiResourceId` and username), and a
  database role granted the predefined `rds_iam` role.
- IAM authentication requires an encrypted connection — `ssl_is_used()` returns
  `t`, here over TLSv1.2 with `ECDHE-RSA-AES256-GCM-SHA384`.
- Use `sslmode=verify-full` with the RDS `global-bundle.pem` CA bundle to verify
  both the certificate chain and the server hostname; `prefer` is the libpq
  default and does no verification.
