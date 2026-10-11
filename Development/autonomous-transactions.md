# Autonomous Transactions in PostgreSQL

PostgreSQL has **no built-in autonomous transactions** like Oracle's
`PRAGMA AUTONOMOUS_TRANSACTION`. This note explains the problem, the common ways
people work around it, whether `pg_background` is standard practice (it isn't),
and the portable pattern that works on managed services such as Amazon RDS /
Aurora PostgreSQL (`dblink` loopback).

All SQL below was tested on **PostgreSQL 18.6**. The example is a small
bank-transfer domain built just for this note.

## The problem: an audit row that must survive a rollback

An *autonomous transaction* is work that commits **independently of the
transaction that triggered it**. The classic need is an **audit / attempt log**:
you want to record that something was *attempted* even if the main operation
later fails and rolls back.

In PostgreSQL, a function (and any `BEGIN ... EXCEPTION` block) runs inside the
caller's transaction. If that transaction rolls back, **every** change it made
rolls back too — including any audit row you inserted along the way.

### Setup

```sql
CREATE TABLE account (
    id      int PRIMARY KEY,
    owner   text NOT NULL,
    balance numeric(12,2) NOT NULL CHECK (balance >= 0)   -- overdraft forbidden
);

CREATE TABLE transfer_attempt (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    attempted_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    from_id int, to_id int, amount numeric(12,2), outcome text
);

INSERT INTO account (id, owner, balance) VALUES (1,'Alice',100.00), (2,'Bob',50.00);
```

### The naive version (audit row is lost)

```sql
CREATE OR REPLACE FUNCTION transfer_naive(p_from int, p_to int, p_amount numeric)
RETURNS text LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO transfer_attempt (from_id, to_id, amount, outcome)
    VALUES (p_from, p_to, p_amount, 'ATTEMPTED');

    UPDATE account SET balance = balance - p_amount WHERE id = p_from;  -- CHECK may fire
    UPDATE account SET balance = balance + p_amount WHERE id = p_to;
    RETURN 'ok';
END;
$$;
```

Running a transfer that overdraws the account:

```sql
SELECT transfer_naive(1, 2, 999);   -- Alice only has ~70 at this point
```

```
ERROR:  new row for relation "account" violates check constraint "account_balance_check"
```

The `CHECK (balance >= 0)` raised, so the function rolled back — **and the
`ATTEMPTED` row is gone**. Querying `transfer_attempt` afterward shows no trace
of the 999 attempt. That is the gap autonomous transactions fill.

## Why the obvious workarounds don't give autonomy

Two approaches *look* like they should solve this but don't. Understanding why
explains what autonomy actually requires.

### Misconception 1: "Log it in the `EXCEPTION` handler — that's outside the rollback"

A very common assumption is that an `INSERT` placed in a PL/pgSQL `EXCEPTION`
clause escapes the rollback. It does **not**. The handler write survives the
*caught error*, but it is still part of the **same transaction**, so if the
overall transaction rolls back, the audit row rolls back with it.

```sql
CREATE OR REPLACE FUNCTION transfer_log_in_handler(p_from int, p_to int, p_amount numeric)
RETURNS text LANGUAGE plpgsql AS $$
BEGIN
    UPDATE account SET balance = balance - p_amount WHERE id = p_from;  -- CHECK may fire
    UPDATE account SET balance = balance + p_amount WHERE id = p_to;
    RETURN 'ok';
EXCEPTION
    WHEN check_violation THEN
        INSERT INTO transfer_attempt(from_id,to_id,amount,outcome)
        VALUES (p_from,p_to,p_amount,'FAILED: caught in handler');   -- survives?
        RETURN 'failed';
END;
$$;
```

**Case 1 — error caught, surrounding transaction commits (autocommit):**

```sql
SELECT transfer_log_in_handler(1,2,999);   -- returns 'failed', no error propagates
SELECT outcome FROM transfer_attempt;
-- FAILED: caught in handler        <-- row is present
```

**Case 2 — same call, but the caller rolls back the transaction:**

```sql
TRUNCATE transfer_attempt RESTART IDENTITY;   -- clean slate (committed on its own)
BEGIN;
SELECT transfer_log_in_handler(1,2,999);
ROLLBACK;
SELECT count(*) FROM transfer_attempt;
-- 0                                 <-- row is GONE
```

So the handler INSERT only "works" when (1) you catch the error *and* (2) the
surrounding transaction ultimately **commits**. It gives *"log the failure,
swallow it, and continue"* semantics — legitimate and common — but it is **not**
autonomous durability. It does not survive a caller `ROLLBACK`, a later statement
failure, a re-raised error, or a crashed session.

### Why: `EXCEPTION` blocks are subtransactions, not nested transactions

PostgreSQL has **no true nested transactions**. A `BEGIN` inside a `BEGIN` is
rejected (`WARNING: there is already a transaction in progress`). What it has is
**subtransactions via savepoints**, and a PL/pgSQL `BEGIN ... EXCEPTION ... END`
block is implemented as an **implicit `SAVEPOINT`**.

That explains both behaviors above:

- On error, PostgreSQL **rolls back to the block's savepoint** (undoing the failed statements in the block) and then runs the handler — which is why the handler INSERT survives the *caught error*.
- But a subtransaction has **no independent commit**. "Finishing" it only folds its effects **provisionally into the parent**. Its final durability is decided entirely by whether the **top-level** transaction commits.

Proof that even an explicitly *released* savepoint is discarded by a parent
rollback:

```sql
TRUNCATE transfer_attempt RESTART IDENTITY;
BEGIN;
  INSERT INTO transfer_attempt(from_id,to_id,amount,outcome) VALUES (1,2,1,'parent');
  SAVEPOINT sp1;
    INSERT INTO transfer_attempt(from_id,to_id,amount,outcome) VALUES (3,4,2,'subtxn');
  RELEASE SAVEPOINT sp1;   -- "commit" the subtransaction (provisionally)
ROLLBACK;                  -- parent discards EVERYTHING, incl. the released subtxn
SELECT count(*) FROM transfer_attempt;
-- 0
```

| Concept | Independent durability? | Visible to other sessions before parent commit? |
|---|---|---|
| **Subtransaction / savepoint** (what `EXCEPTION` uses) | ❌ No — tied to the parent's commit/rollback | ❌ No |
| **Autonomous transaction** (separate session, e.g. `dblink`) | ✅ Yes — its own top-level transaction | ✅ Yes |

**The takeaway:** autonomy requires a **separate top-level transaction in a
separate session** — not a subtransaction of the caller. That is exactly why the
`dblink` loopback below works: there is no parent-child relationship, so the
caller's rollback cannot reach it.

## The common, portable solution: `dblink` loopback

The standard PostgreSQL idiom is to perform the independent write over a
**separate database connection**, using the `dblink` extension to open a
*loopback* connection back to the same database. Work done through that
connection runs in **its own session and its own transaction**, and commits
immediately — independent of the caller.

```sql
CREATE EXTENSION IF NOT EXISTS dblink;

-- Write one audit row through a short-lived loopback connection.
CREATE OR REPLACE FUNCTION log_attempt_autonomous(
    p_from int, p_to int, p_amount numeric, p_outcome text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v_conn text := 'autonomous_log_conn';
BEGIN
    PERFORM dblink_connect(v_conn, 'dbname=autonomous_demo');   -- loopback to same DB
    PERFORM dblink_exec(v_conn, format(
        $q$INSERT INTO transfer_attempt (from_id, to_id, amount, outcome)
           VALUES (%L, %L, %L, %L)$q$,
        p_from, p_to, p_amount, p_outcome));
    PERFORM dblink_disconnect(v_conn);
EXCEPTION
    WHEN OTHERS THEN
        PERFORM dblink_disconnect(v_conn);   -- never leak the named connection
        RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION transfer_with_audit(p_from int, p_to int, p_amount numeric)
RETURNS text LANGUAGE plpgsql AS $$
BEGIN
    PERFORM log_attempt_autonomous(p_from, p_to, p_amount, 'ATTEMPTED');   -- autonomous
    UPDATE account SET balance = balance - p_amount WHERE id = p_from;
    UPDATE account SET balance = balance + p_amount WHERE id = p_to;
    PERFORM log_attempt_autonomous(p_from, p_to, p_amount, 'SUCCESS');     -- autonomous
    RETURN 'ok';
END;
$$;
```

### Tested behavior

**Test A — the main operation fails (overdraft):**

```sql
SELECT transfer_with_audit(1, 2, 999);
-- ERROR: ... violates check constraint "account_balance_check"

SELECT id, from_id, to_id, amount, outcome FROM transfer_attempt ORDER BY id;
```
```
 id | from_id | to_id | amount |  outcome
----+---------+-------+--------+-----------
  1 |       1 |     2 | 999.00 | ATTEMPTED      <-- SURVIVED the rollback
```

**Test B — the caller explicitly rolls back:**

```sql
BEGIN;
SELECT transfer_with_audit(1, 2, 10);   -- succeeds inside the txn
ROLLBACK;                                 -- caller throws the money move away
```

Balances are unchanged (no money moved), **but both audit rows persisted**:

```
 id | owner | balance            id | from_id | to_id | amount | outcome
----+-------+---------          ----+---------+-------+--------+-----------
  1 | Alice |  100.00             2 |    1    |   2   |  10.00 | ATTEMPTED
  2 | Bob   |   50.00             3 |    1    |   2   |  10.00 | SUCCESS
```

The audit writes committed on the loopback session and were **not** undone by
the caller's `ROLLBACK`. That is autonomous-transaction behavior.

### Why `dblink` is the common choice

- It is a **contrib extension** shipped with PostgreSQL and **available on RDS and Aurora PostgreSQL** (`CREATE EXTENSION dblink;`).
- It needs no external process, compilation, or background worker.
- The separate session genuinely isolates the write from the caller's transaction.

### Practical caveats

- **Connection cost:** each `dblink_connect`/`disconnect` is a real backend connection. For high call rates, reuse a named connection, or batch the autonomous writes, or use a queue (below).
- **Authentication:** the connection string must authenticate. On the local demo, unix-socket **peer** auth needs no password (`'dbname=autonomous_demo'`). On RDS/Aurora you supply host/user/password (ideally via a stored credential / Secrets Manager, not inline), e.g. `'host=... dbname=app user=audit password=...'`.
- **No distributed-transaction guarantee:** the autonomous write is independent, so it is *not* rolled back with the caller — which is the whole point, but it also means you own the consistency semantics.
- **Error isolation:** wrap `dblink_exec` so a logging failure doesn't necessarily abort the business operation (or does, if that is your policy).

## Is `pg_background` the common practice? No.

`pg_background` is a **third-party extension** (not part of core or contrib). It
launches a background worker that runs a command in a separate process and
transaction, which does give autonomous-style behavior. But:

- It must be **compiled and installed** on the server from source.
- It is **not available on managed services**. On this test system (and on RDS /
  Aurora) installing it fails:

  ```sql
  CREATE EXTENSION pg_background;
  ```
  ```
  ERROR:  extension "pg_background" is not available
  HINT:  The extension must first be installed on the system where
         PostgreSQL is running.
  ```

Because it is unavailable precisely where many production databases run (managed
cloud), `pg_background` is **not** the common or portable approach. Treat it as a
niche option for self-managed servers where you control the binaries.

## What about a procedure with `COMMIT`? Not a substitute

Since PostgreSQL 11, a **procedure** (`CALL`) can issue `COMMIT` / `ROLLBACK`.
That is useful for *batching* long work into chunks, but it is **not**
autonomous: the `COMMIT` commits the caller's own transaction, and it only works
when the procedure is **not** already inside an outer transaction block. Tested:

```sql
CREATE PROCEDURE proc_with_commit() LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO transfer_attempt(from_id,to_id,amount,outcome) VALUES (9,9,1,'X');
    COMMIT;
END;$$;

BEGIN;
CALL proc_with_commit();   -- inside an explicit transaction
ROLLBACK;
```
```
ERROR:  invalid transaction termination
CONTEXT:  PL/pgSQL function proc_with_commit() line 4 at COMMIT
```

So a procedure cannot be nested inside another transaction/function to act as an
autonomous unit. Use `dblink` for true autonomy.

## Other approaches (brief)

- **Queue + `NOTIFY` / external worker:** instead of writing the audit row inline, `pg_notify` (or insert into an unlogged "outbox" that a separate worker drains). The worker commits independently. Scales better than per-call `dblink` for high volume, at the cost of asynchrony and an extra moving part. (`NOTIFY` itself is only delivered on commit, so pair it with a durable outbox if the trigger transaction may roll back.)
- **`postgres_fdw` loopback:** similar isolation to `dblink` via a foreign server pointing back at the same instance. Available on RDS/Aurora too; heavier to set up than `dblink` for a simple log write.
- **Application-side:** open a second DB connection in the app and write the audit record there, outside the business transaction. Simple and explicit, but moves the logic out of the database.

## Choosing an approach

| Approach | True autonomy? | On RDS / Aurora? | Notes |
|---|---|---|---|
| **`dblink` loopback** | ✅ Yes | ✅ Yes | Common, portable idiom; watch connection cost |
| **`postgres_fdw` loopback** | ✅ Yes | ✅ Yes | More setup than `dblink`; same idea |
| **Queue / `NOTIFY` + worker** | ✅ Yes (async) | ✅ Yes | Best at high volume; asynchronous; use a durable outbox |
| **Application second connection** | ✅ Yes | ✅ Yes | Logic lives in the app, not the DB |
| **`pg_background`** | ✅ Yes | ❌ No | Third-party, must compile; **not** on managed services |
| **Procedure + `COMMIT`** | ❌ No | ✅ Yes | For chunked commits, not isolation; can't nest in a txn |

**Bottom line:** for an autonomous write that must survive a rollback and must
also run on RDS / Aurora, the common, portable choice is the **`dblink` loopback
connection**. Reserve `pg_background` for self-managed servers where you can
install it, and don't mistake a procedure's `COMMIT` for autonomy.

## References

- [dblink (PostgreSQL docs)](https://www.postgresql.org/docs/current/dblink.html)
- [postgres_fdw (PostgreSQL docs)](https://www.postgresql.org/docs/current/postgres-fdw.html)
- [Transaction management in procedures (PostgreSQL docs)](https://www.postgresql.org/docs/current/plpgsql-transactions.html)
- [RDS for PostgreSQL — supported extensions](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Appendix.PostgreSQL.CommonDBATasks.Extensions.html)
