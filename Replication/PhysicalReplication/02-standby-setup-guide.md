# 02 — Step-by-Step Standby Setup Guide

Level: L200. **Tested against PostgreSQL 18.6** (Ubuntu pgdg `18.6-1.pgdg24.04+2`, x86_64),
primary and standby on one machine (ports 5433 / 5435). Every command and output below was
executed. On two real hosts, replace `127.0.0.1` with the primary's address.

Shortcut: `source lab.sh; plab_up` builds the same thing with trust authentication
(see [lab.sh](lab.sh)). The steps below use real authentication.

## 1. Primary prerequisites

`postgresql.conf` on the primary:

```
wal_level = replica            # default; 'logical' also works
max_wal_senders = 10           # default 10: one per standby + backups (pg_basebackup uses one)
max_replication_slots = 10     # default 10
wal_keep_size = 64MB           # safety net if you do not use slots (see topic 03)
hot_standby = on               # default on; matters on the standby
listen_addresses = '…'         # must accept the standby's connection
```

`wal_level`, `max_wal_senders`, `max_replication_slots` need a **restart** to change;
on PG ≥ 10 `wal_level=replica` is the default, so many installations need no change.

## 2. Replication role and `pg_hba.conf`

```sql
CREATE ROLE repl WITH LOGIN REPLICATION PASSWORD 'replpw';
```

`pg_hba.conf` (primary) — physical replication uses the special database name `replication`:

```
host  replication  repl  <standby-ip>/32  scram-sha-256
```

(Contrast with logical replication, which connects to a normal database name — see
[logical topic 03](../LogicalReplication/03-subscriptions.md#security-model).) Use `hostssl` in production.
`SELECT pg_reload_conf();` applies it.

## 3. Take the base backup

Run this **on the standby host**, with an empty target directory:

```bash
PGPASSWORD=replpw PGDATABASE=postgres \
pg_basebackup -h 127.0.0.1 -p 5433 -U repl -D /var/lib/postgresql/18/standby \
              -R -X stream -C -S standby1 -P -v
```

Output (abridged, 18.6):

```
23854/23854 kB (100%), 1/1 tablespace
pg_basebackup: write-ahead log end point: 0/2000AB8
pg_basebackup: waiting for background process to finish streaming ...
pg_basebackup: syncing data to disk ...
pg_basebackup: renaming backup_manifest.tmp to backup_manifest
pg_basebackup: base backup completed
```

What each flag does:

| Flag | Meaning |
|---|---|
| `-R` | Write `standby.signal` and `primary_conninfo` (+ `primary_slot_name`) into the new data dir |
| `-X stream` | Stream WAL **during** the backup in a second connection (so the backup is self-contained); the default `-X stream` since PG10 |
| `-C -S standby1` | **Create** the physical replication slot `standby1` on the primary as part of the backup, so no WAL is lost between backup end and first start |
| `-P -v` | Progress and verbose |
| `PGDATABASE=postgres` | In PG17+ `-R` also writes `dbname=$PGDATABASE` into `primary_conninfo`. Set it to a real database name (matters for failover-slot sync, [logical topic 16](../LogicalReplication/16-failover-and-ha.md)); a wrong value (in my first run it was my login name `donghua`, which does not exist) breaks slot sync |

The backup copies the primary's `postgresql.conf` too. Edit whatever must differ on the standby (at least `port`/
`listen_addresses`/`unix_socket_directories` when on the same host).

Generated on the standby:

```
standby/standby.signal
standby/postgresql.auto.conf
   primary_conninfo = 'user=repl password=replpw channel_binding=prefer host=127.0.0.1 port=5433 sslmode=prefer …'
   primary_slot_name = 'standby1'
```

Passwords in `primary_conninfo` are stored in clear text in that file — prefer a
`passfile`/`.pgpass` (`pg_basebackup` writes one automatically when the password came from
`.pgpass`) and keep the data directory mode `0700`.

## 4. Start the standby and verify

```bash
pg_ctl -D /var/lib/postgresql/18/standby -l standby.log start
```

On the standby:

```sql
SELECT pg_is_in_recovery();                     -- t
SELECT count(*) FROM t;                         -- 1000  (data present)
```

On the primary:

```sql
SELECT slot_name, slot_type, active, restart_lsn FROM pg_replication_slots;
 standby1 | physical | t | 0/3002078

SELECT application_name, state, sync_state FROM pg_stat_replication;
 walreceiver | streaming | async
```

A write on the primary shows up on the standby within milliseconds
(`INSERT` → standby `count(*)` went 1000 → 1001).

Things that prove it is what you think it is:

```sql
-- standby: writes are refused
CREATE TABLE x(i int);
ERROR:  cannot execute CREATE TABLE in a read-only transaction

-- standby: unlogged tables are not available
SELECT count(*) FROM u;
ERROR:  cannot access temporary or unlogged relations during recovery
```

## 5. Name the standby

`application_name` defaults to `walreceiver`. Give each standby a name so that
`pg_stat_replication` and `synchronous_standby_names` ([04](04-synchronous-replication.md)) can tell them apart:

```
primary_conninfo = 'user=repl … host=primary port=5432 application_name=standby_a'
```

## 6. Parameters that must not be lower on a standby

Tested: with the standby's `max_connections` set to 50 (primary 100) the standby
refuses to replay:

```
FATAL:  recovery aborted because of insufficient parameter settings
DETAIL:  max_connections = 50 is a lower setting than on the primary server, where its value was 100.
HINT:  You can restart the server after making the necessary configuration changes.
```

The set: `max_connections`, `max_worker_processes`, `max_wal_senders`,
`max_prepared_transactions`, `max_locks_per_transaction`. Change order when increasing:
**standbys first, then the primary**. When decreasing: primary first.

## 7. Alternatives to a pg_basebackup copy

| Method | When |
|---|---|
| `pg_basebackup` (this guide) | Normal case; online, consistent |
| Restore from a backup + WAL archive (`restore_command`) then `standby.signal` | You have a backup tool (pgBackRest, Barman, WAL-G); often faster and gives the standby an archive fallback ([08](08-cascading-delayed-archive.md)) |
| Filesystem snapshot with `pg_backup_start/stop` | Storage snapshots (LVM/EBS), consistent with WAL |
| `pg_basebackup --incremental` + `pg_combinebackup` (PG17+) | Huge databases with a recent full backup |
| `pg_rewind` an old primary | Reusing a former primary ([07](07-failover-switchover-promotion.md)) |

## 8. Post-setup checklist

- [ ] `pg_stat_replication.state = streaming` and the expected `application_name`.
- [ ] Slot is `active` (if using slots), and `max_slot_wal_keep_size` is set deliberately ([03](03-replication-slots-and-wal-retention.md)).
- [ ] Standby sizing parameters ≥ primary (section 6).
- [ ] `hot_standby_feedback` / `max_standby_streaming_delay` decided for your read workload ([05](05-hot-standby-and-query-conflicts.md)).
- [ ] Monitoring and alerts on lag ([06](06-monitoring-and-lag.md)).
- [ ] Failover procedure written and tested ([07](07-failover-switchover-promotion.md)).
- [ ] Backups still run (a standby is **not** a backup: `DROP TABLE` replicates).
