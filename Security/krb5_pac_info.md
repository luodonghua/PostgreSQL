```bash
ec2-user@ip-10-2-2-71 ~]$ gcc -o krb5_pac_info krb5_pac_info.c -lkrb5 -lk5crypto -lcom_err -Wall
```

```bash
[ec2-user@ip-10-2-2-71 ~]$ kinit user1
Password for user1@CORP.EXAMPLE.COM: 
```
```bash
[ec2-user@ip-10-2-2-71 ~]$ ./krb5_pac_info 
Default principal: user1@CORP.EXAMPLE.COM

Credentials status:
- Credentials pointer: 0x3f06f750
- Ticket length: 1212
Ticket decode status:
- Decoded ticket pointer: 0x3f06c940

=== Ticket Details ===

Ticket structure status:
- Ticket pointer: 0x3f06c940
- enc_part2 pointer: 0x3f06ce50
Encryption Type: aes256-cts-hmac-sha1-96 (value: 18)

Session Key Information:
Key Information:
  Encryption Type: aes256-cts-hmac-sha1-96 (value: 18)
  Key Length: 32 bytes

Client Principal: user1@CORP.EXAMPLE.COM
Server Principal: krbtgt/CORP.EXAMPLE.COM@CORP.EXAMPLE.COM

Ticket Flags (Simple Format):
  - Initial ticket
  - Renewable
  - Pre-authenticated

Ticket Flags (Detailed Format):
Ticket Flags Detail:
  INITIAL     : Ticket was issued using AS exchange
  RENEWABLE   : Ticket can be renewed
  PRE_AUTH    : Pre-authentication was used

Time Information (Simple Format):
  Auth time:     2024-12-23 09:32:00
  Start time:    2024-12-23 09:32:00
  End time:      2024-12-23 19:32:00
  Renew until:   2024-12-30 09:31:56

Time Information (Detailed Format):
Time Information:
  Authentication Time: 2024-12-23 09:32:00
  Start Time: 2024-12-23 09:32:00 (valid)
  End Time: 2024-12-23 19:32:00 (valid)
  Renewable Until: 2024-12-30 09:31:56 (valid)

Durations:
  Ticket lifetime: 10.0 hours
  Renewable lifetime: 168.0 hours

Ticket Status:
  - Ticket is valid
  - Renewable for 167.9 more hours

Authorization Data: Not available
```
