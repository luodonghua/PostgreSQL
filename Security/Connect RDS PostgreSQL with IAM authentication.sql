-- Demostration here used Acloudguru sandbox, all accounts and token will be reset

$ aws sts get-caller-identity --query 'Arn' --output text
arn:aws:iam::853595176342:user/cloud_user


$ aws rds describe-db-instances --db-instance-identifier postgres-instance1 \
 --query 'DBInstances[0].{Dbi:DbiResourceId,Arn:DBInstanceArn,Iam:IAMDatabaseAuthenticationEnabled}'

{
    "Dbi": "db-IYF56K6FHWKHL2MAPU6TQPOTSE",
    "Arn": "arn:aws:rds:us-east-1:853595176342:db:postgres-instance1",
    "Iam": true
}


-- attach this policy to IAM user "853595176342:user/cloud_user"
-- although it's not necessary for acloudguru sandbox, as cloud_user has all privileges
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


mytest=> create user cloud_user;
CREATE ROLE
mytest=> grant rds_iam to cloud_user;
GRANT ROLE

export RDSHOST="postgres-instance1.ck4o6l6o9kyg.us-east-1.rds.amazonaws.com"
export PGPASSWORD="$(aws rds generate-db-auth-token --hostname $RDSHOST --port 5432 --region us-east-1 --username cloud_user )"

/*
# output below manually broken into multiple lines for reading
echo $PGPASSWORD 
postgres-instance1.ck4o6l6o9kyg.us-east-1.rds.amazonaws.com:5432/?
Action=connect&DBUser=cloud_user&X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=
AKIA4NPR4XWLDEIKZQLQ%2F20211030%2Fus-east-1%2Frds-db%2Faws4_request&X-Amz-Date=20211030T025117Z&
X-Amz-Expires=900&X-Amz-SignedHeaders=host&
X-Amz-Signature=99b4b724ff566e2a30db834b5f49727a4cf2de4da91ac6a721711cd3bc506499

*/

$ psql "host=$RDSHOST port=5432 dbname=mytest user=cloud_user password=$PGPASSWORD" 

psql (13.4)
SSL connection (protocol: TLSv1.2, cipher: ECDHE-RSA-AES256-GCM-SHA384, bits: 256, compression: off)
Type "help" for help.

mytest=> select ssl_is_used(), ssl_cipher();
 ssl_is_used |         ssl_cipher          
-------------+-----------------------------
 t           | ECDHE-RSA-AES256-GCM-SHA384
(1 row)


/*

SSL Mode Descriptions
 - disable: I don't care about security, and I don't want to pay the overhead of encryption.
 - allow: I don't care about security, but I will pay the overhead of encryption if the server insists on it.
 - prefer: I don't care about encryption, but I wish to pay the overhead of encryption if the server supports it.
 - require: I want my data to be encrypted, and I accept the overhead. I trust that the network will make sure I always connect to the server I want.
 - verify-ca: I want my data encrypted, and I accept the overhead. I want to be sure that I connect to a server that I trust.
 - verify-full: I want my data encrypted, and I accept the overhead. I want to be sure that I connect to a server I trust, and that it's the one I specify.

prefer is the default mode

The difference between verify-ca and verify-full depends on the policy of the root CA. If a public CA is used, 
verify-ca allows connections to a server that somebody else may have registered with the CA. 
In this case, verify-full should always be used. If a local CA is used, or even a self-signed certificate, 
using verify-ca often provides enough protection.

*/


$ psql "host=$RDSHOST port=5432 sslmode=verify-full sslrootcert=./global-bundle.pem dbname=mytest user=cloud_user password=$PGPASSWORD"                                                                                                          
psql (13.4)
SSL connection (protocol: TLSv1.2, cipher: ECDHE-RSA-AES256-GCM-SHA384, bits: 256, compression: off)
Type "help" for help.

mytest=> select ssl_is_used(), ssl_cipher();
 ssl_is_used |         ssl_cipher          
-------------+-----------------------------
 t           | ECDHE-RSA-AES256-GCM-SHA384
(1 row)



