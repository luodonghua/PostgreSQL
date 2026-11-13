# 04 — Step-by-Step Setup Guide (hands-on lab)

Level: L200. **Tested against PostgreSQL 18.6** (Ubuntu pgdg `18.6-1.pgdg24.04+2`,
`x86_64`), two instances on one machine. Every command below was executed; the
outputs shown are real. On other versions the flow is the same, but check the
[version policy](README.md#version-policy-read-this-first) for options that
differ (e.g. `streaming` defaults to `parallel` only on 18+).

## 0. Start the lab

```bash
cd Replication/LogicalReplication
source lab.sh
lab_up
# publisher :5433  subscriber :5434  (postgres (PostgreSQL) 18.6 …)
```

`lab_up` initialises two clusters under `/tmp/lr-lab` and sets
`wal_level = logical` on the publisher only. Helpers: `pub` and `sub` are
`psql` shortcuts for the two instances; `lab_down` deletes everything.

For a real environment, replace the lab with your own hosts and apply the
settings in step 1 yourself.

## 1. Publisher prerequisites

| Setting | Needed value | Restart? | Lab value |
|---|---|---|---|
| `wal_level` | `logical` | **yes** | `logical` |
| `max_replication_slots` | ≥ (subscriptions + tablesync slots in flight + other slots) | yes | 10 |
| `max_wal_senders` | ≥ number of slots in use + physical standbys | yes | 10 |
| `max_slot_wal_keep_size` | a cap you can afford (default `-1` = unlimited!) | no | -1 |

```sql
-- publisher
SHOW wal_level;                  -- logical
SHOW max_replication_slots;      -- 10
SHOW max_wal_senders;            -- 10
```

Subscriber prerequisites:

```sql
-- subscriber
SHOW max_logical_replication_workers;   -- 4 default: 1 apply worker per subscription
                                         --   + tablesync workers + parallel apply workers
SHOW max_worker_processes;              -- 8 default: must be larger than the line above
```

Rule: `max_logical_replication_workers` ≥ subscriptions + sync workers you want in
parallel (`max_sync_workers_per_subscription`, default 2) + parallel apply workers
(`max_parallel_apply_workers_per_subscription`, default 2).
`wal_level` on the subscriber can stay `replica`.

## 2. Create a replication role and allow it in `pg_hba.conf`

```sql
-- publisher
CREATE ROLE repl WITH LOGIN REPLICATION PASSWORD 'S3cret!';
```

`pg_hba.conf` on the publisher (logical replication connects to a *normal
database*, so use the database name, **not** the `replication` keyword):

```
host  postgres  repl  127.0.0.1/32  scram-sha-256
```

```sql
SELECT pg_reload_conf();      -- t
```

In production use `hostssl` and `sslmode=verify-full` in the subscription
conninfo, and store the password in `~/.pgpass`/a secret manager rather than
in `CREATE SUBSCRIPTION` (it is saved in `pg_subscription.subconninfo`,
which only superusers can read).

## 3. Create sample data on the publisher

```sql
-- publisher
CREATE TABLE customers(id bigint PRIMARY KEY, name text NOT NULL);
CREATE TABLE orders(id bigint PRIMARY KEY,
                    customer_id bigint REFERENCES customers,
                    amount numeric(10,2),
                    created_at timestamptz DEFAULT now());
CREATE TABLE audit_log(ts timestamptz, msg text);            -- note: no primary key

INSERT INTO customers SELECT g,'cust'||g FROM generate_series(1,100) g;
INSERT INTO orders    SELECT g,(g%100)+1,g*1.5 FROM generate_series(1,10000) g;
INSERT INTO audit_log VALUES (now(),'boot');

GRANT SELECT ON ALL TABLES IN SCHEMA public TO repl;         -- needed for the initial copy
ALTER TABLE audit_log REPLICA IDENTITY FULL;                 -- no PK → needed for UPDATE/DELETE
```

> If you skip the `REPLICA IDENTITY FULL` line and later `UPDATE audit_log`, the
> **publisher** rejects the statement once the table is in a publication that
> publishes updates ([topic 02](02-publications.md)).

## 4. Create the publication

```sql
-- publisher
CREATE PUBLICATION app_pub FOR TABLE customers, orders, audit_log;
```

## 5. Create the same schema on the subscriber

Logical replication does not copy DDL, so the target tables must exist first. This
lab uses `--no-owner --no-privileges` because the subscriber has none of the
publisher's roles. For real systems create the roles first and keep owners and grants
([15 §4](15-best-practices.md#day-0)):

```bash
pg_dump -h 127.0.0.1 -p 5433 -d postgres \
        --schema-only --no-owner --no-privileges \
        --no-publications --no-subscriptions \
  | psql -X -h 127.0.0.1 -p 5434 -d postgres -v ON_ERROR_STOP=1
```

The three `--no-…` flags matter. My first attempt without them failed twice
on the subscriber: the dump re-created the *publication* (`WARNING: "wal_level"
is insufficient to publish logical changes`) and replayed `GRANT … TO repl`
(`ERROR: role "repl" does not exist`).

## 6. Create the subscription

```sql
-- subscriber
CREATE SUBSCRIPTION app_sub
  CONNECTION 'host=127.0.0.1 port=5433 dbname=postgres user=repl password=S3cret!'
  PUBLICATION app_pub;
-- NOTICE:  created replication slot "app_sub" on publisher
```

This creates the slot on the publisher, copies the three tables with
tablesync workers, then switches to streaming.

## 7. Verify

```sql
-- subscriber: every table should reach 'r' (ready)
SELECT srrelid::regclass, srsubstate FROM pg_subscription_rel ORDER BY 1;
  srrelid  | srsubstate
-----------+------------
 audit_log | r
 customers | r
 orders    | r
```

Row counts (publisher / subscriber): `customers 100/100`, `orders 10000/10000`,
`audit_log 1/1`.

```sql
-- publisher: the slot and the streaming connection
SELECT slot_name, active, confirmed_flush_lsn, wal_status FROM pg_replication_slots;
 slot_name | active | confirmed_flush_lsn | wal_status
-----------+--------+---------------------+------------
 app_sub   | t      | 0/1936310           | reserved

SELECT application_name, state, sent_lsn, replay_lsn, sync_state FROM pg_stat_replication;
 application_name |   state   | sent_lsn  | replay_lsn | sync_state
 app_sub          | streaming | 0/1936310 | 0/1936310  | async
```

`write_lag`/`flush_lag`/`replay_lag` are NULL when idle; they fill in while changes flow.

## 8. Watch live changes flow

```sql
-- publisher
INSERT INTO orders VALUES (10001,1,1);
UPDATE customers SET name='renamed' WHERE id=1;
DELETE FROM orders WHERE id=1;
INSERT INTO audit_log VALUES (now(),'live');
```

```sql
-- subscriber (one second later)
SELECT (SELECT name FROM customers WHERE id=1) n,
       (SELECT count(*) FROM orders) o,
       (SELECT count(*) FROM audit_log) a;
    n    |   o   | a
---------+-------+---
 renamed | 10000 | 2
```

(10000 + 1 inserted − 1 deleted = 10000.)

Lag in bytes, measured on the publisher:

```sql
SELECT slot_name,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn)) AS behind
FROM pg_replication_slots;
 app_sub | 0 bytes
```

## 9. Day-2 procedures (each one tested)

### 9.1 Add a column — change the subscriber first

```sql
-- 1) subscriber
ALTER TABLE orders ADD COLUMN note text;
-- 2) publisher
ALTER TABLE orders ADD COLUMN note text;
INSERT INTO orders VALUES (5000,1,1,'hi');   -- subscriber shows note = 'hi'
```

What happens in the wrong order (publisher first, then a write that uses the
column): the apply worker raises

```
ERROR:  logical replication target relation "public.orders" is missing replicated column: "extra"
```

and retries every `wal_retrieve_retry_interval` (5 s). It **self-heals** once
you add the column on the subscriber (I confirmed the row arrived after the
next retry). While it is erroring, replication for that subscription is
stalled and the slot retains WAL.

Rule: **additive changes: subscriber first. Destructive changes (drop column):
publisher first**, after nothing reads the column. Type changes need a plan —
see [topic 13](13-limitations.md).

### 9.2 Add a table to an existing setup

```sql
-- publisher
CREATE TABLE notes(id int PRIMARY KEY, t text);
INSERT INTO notes VALUES (1,'n');
GRANT SELECT ON notes TO repl;
ALTER PUBLICATION app_pub ADD TABLE notes;
-- subscriber
CREATE TABLE notes(id int PRIMARY KEY, t text);
ALTER SUBSCRIPTION app_sub REFRESH PUBLICATION;
SELECT srsubstate FROM pg_subscription_rel WHERE srrelid='notes'::regclass;   -- r
SELECT count(*) FROM notes;                                                     -- 1
```

### 9.3 Remove a table

```sql
-- publisher
ALTER PUBLICATION app_pub DROP TABLE notes;
-- subscriber
ALTER SUBSCRIPTION app_sub REFRESH PUBLICATION;   -- pg_subscription_rel drops back to 2 rows
```

### 9.4 Tear everything down cleanly

```sql
-- subscriber
DROP SUBSCRIPTION app_sub;
-- NOTICE:  dropped replication slot "app_sub" on publisher
```

```sql
-- publisher: confirm nothing is left pinning WAL
SELECT count(*) FROM pg_replication_slots;     -- 0
```

Then `lab_down`.

## 10. Checklist before you trust it

- [ ] `pg_subscription_rel`: all tables `r`.
- [ ] `pg_replication_slots.active = t`, `wal_status = reserved`.
- [ ] Row counts and a checksum query match for each table.
- [ ] Every published table has a PK or an explicit `REPLICA IDENTITY`.
- [ ] A cap on slot retention is set (`max_slot_wal_keep_size`), and an alert on
      `pg_replication_slots` retained bytes exists ([topic 14](14-monitoring-and-troubleshooting.md)).
- [ ] Sequences: decide how they will be handled on cut-over ([topic 13](13-limitations.md)).
- [ ] Runbook for DDL order (9.1) and for dropping the subscription (9.4).

## Not covered here (and where it is)

Conflict handling → [12](12-conflicts-and-error-handling.md). Failover →
[16](16-failover-and-ha.md). Major-version upgrade recipe →
[17](17-upgrades-and-migrations.md). Managed services (RDS/Aurora) →
[20](20-amazon-rds-and-aurora.md).
