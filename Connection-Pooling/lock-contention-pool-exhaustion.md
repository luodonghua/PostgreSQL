# Lock Contention → Connection-Pool Exhaustion

A playbook for a common production incident: a **long-running batch job holds
row locks**, small OLTP transactions **block waiting** on those locks, and
because each blocked transaction **keeps holding its pool connection while it
waits**, the application connection pool drains and new requests fail with
connection-timeout errors.

> **Key insight:** pool exhaustion here is a *symptom*. The disease is **lock
> contention + a long-held transaction**. Enlarging the pool only lets more
> threads pile onto the same locks — it delays the wall, it doesn't remove it.
> Fix the lock-holding time first; treat pool settings as a safety net.

## What happens, step by step

1. A **batch job** opens a session and takes row locks (`UPDATE`, `DELETE`, `SELECT ... FOR UPDATE`) inside a long transaction, and holds them (large batch, or autocommit off with no intermediate commits).
2. **Small OLTP transactions** that want the same rows **block**, waiting on the batch's locks.
3. Each blocked transaction is **holding a pool connection while it waits** — the connection is parked on a lock wait, doing no work.
4. Blocked requests pile up → `maximumPoolSize` is reached → new requests can't get a connection → `SQLTransientConnectionException ... request timed out` (or equivalent).

```
Batch txn (holds locks, long)                 ████████████████████████ (minutes)
  OLTP #1 wants same row  → blocked, holds conn   ░░░░░░░░░░░░░░░░ (waiting)
  OLTP #2 wants same row  → blocked, holds conn    ░░░░░░░░░░░░░░░ (waiting)
  OLTP #3 ... → pool exhausted → new requests fail to even get a connection ✗
```

## Fixes — from root cause outward

Apply these roughly in order. The earliest items remove the cause; the later
items contain the blast radius and fail fast.

### 1. Shorten how long the batch holds locks (most important)

- **Chunk the batch into small transactions.** Instead of one transaction locking a million rows, commit every N rows (e.g. 1k–10k). Each chunk acquires and *releases* locks quickly, so OLTP waits milliseconds, not minutes.
- **Keyset-paginate** the batch so each chunk is bounded:

  ```sql
  -- process in bounded chunks, committing between each
  UPDATE orders SET status = 'archived'
  WHERE id > :last_id
  ORDER BY id
  LIMIT 5000
  RETURNING id;   -- remember max(id) as :last_id for the next chunk, then COMMIT
  ```

- **Keep the critical section tight** — acquire lock, write, commit. Never hold a transaction open across app logic, network calls, or user think-time.

### 2. Make the batch yield instead of blocking OLTP

- **Let the batch skip rows that OLTP is currently using**, coming back to them later rather than queuing ahead of users:

  ```sql
  SELECT id FROM work_queue
  WHERE status = 'pending'
  ORDER BY id
  FOR UPDATE SKIP LOCKED
  LIMIT 5000;
  ```

- **Give the batch a short `lock_timeout`** so it backs off and retries instead of camping on a contended lock:

  ```sql
  SET lock_timeout = '2s';   -- batch session: fail fast, retry the chunk later
  ```

- Use a **consistent lock acquisition order** across batch and OLTP to avoid deadlocks.

### 3. Stop blocked waiters from hogging pool connections

Cap how long any transaction waits so a blocked connection returns to the pool
quickly instead of parking. Set these on the OLTP side (session, or in the
pooler/proxy init query):

```sql
SET lock_timeout = '3s';                          -- fail the statement if it can't lock in time
SET idle_in_transaction_session_timeout = '10s';  -- kill forgotten open transactions
SET statement_timeout = '30s';                    -- backstop for runaway statements
```

A fail-fast request frees its connection, so the pool doesn't drain. The user
gets a **retriable error** instead of a 30-second hang that exhausts the pool.

### 4. Isolate the batch from OLTP (most effective structural fix)

A batch and interactive traffic should almost never share one pool.

- Run the batch through a **separate connection pool / separate DB user / separate RDS Proxy endpoint (or a direct connection)**, with its own small cap (e.g. 2–4 connections). Then even if the batch misbehaves, it **cannot consume the OLTP pool's connections** — the blast radius is contained.
- On RDS/Aurora, point a **read-mostly** batch at a **reader endpoint** to keep it off the OLTP writer path entirely.

### 5. Reduce the contention itself (schema / design)

- Prefer a **work-queue with `SKIP LOCKED`** so workers never fight over the same rows.
- Consider **optimistic concurrency** (version column + retry) instead of pessimistic `FOR UPDATE` for OLTP paths.
- **Partition** data so the batch and OLTP touch different partitions / key ranges.

### 6. Pool settings — safety net, not the cure

- Set a **sane `connectionTimeout`** (e.g. 2–5 s, not 30 s) so threads fail fast when the pool is drained, surfacing the problem instead of hanging the whole app.
- Enable **leak detection / `maxLifetime`** so a stuck connection is eventually reclaimed (HikariCP `leakDetectionThreshold`).
- **Do NOT reflexively raise `maximumPoolSize`.** A bigger pool behind the same lock just means more backend connections all stuck on the same wait, pushing the exhaustion down to the database's `max_connections`.

## Interaction with a server-side pooler (RDS Proxy / PgBouncer)

If this traffic runs behind **RDS Proxy**, note that a long row-locking
transaction — and especially `SELECT ... FOR UPDATE` or session state held
across statements — can **pin** the proxy connection for the whole batch, so the
pinned backend is unavailable to other clients for the duration. That makes the
**batch-isolation fix (#4) doubly important**: give the batch its own path so
its pinning can't starve the shared OLTP multiplexing. For how pinning works,
see [pgbouncer-vs-rds-proxy.md §2.6](pgbouncer-vs-rds-proxy.md).

With **PgBouncer transaction mode**, a long transaction holds its server
connection for the whole transaction, so chunking (#1) directly improves pool
reuse there too.

## Diagnosis cheat-sheet

Find the blocking chain and the culprit while it's happening:

```sql
-- Who is blocking whom?
SELECT blocked.pid        AS blocked_pid,
       blocked.query      AS blocked_query,
       blocking.pid       AS blocking_pid,
       blocking.query     AS blocking_query,
       blocking.state     AS blocking_state
FROM pg_stat_activity blocked
JOIN pg_stat_activity blocking
  ON blocking.pid = ANY(pg_blocking_pids(blocked.pid))
WHERE cardinality(pg_blocking_pids(blocked.pid)) > 0;

-- Long-running / idle-in-transaction sessions (the usual batch culprit)
SELECT pid, state, now() - xact_start AS xact_age, now() - query_start AS query_age, query
FROM pg_stat_activity
WHERE state <> 'idle'
ORDER BY xact_start NULLS LAST;
```

Pool-side signals:

- **HikariCP:** `hikaricp_connections_pending > 0` under normal load, and `SQLTransientConnectionException ... request timed out`.
- **RDS Proxy:** `DatabaseConnectionsCurrentlySessionPinned` rising (pinning), plus `DatabaseConnectionsBorrowLatency` / connection borrow timeouts.
- **PgBouncer:** `SHOW POOLS;` — `cl_waiting` > 0 means clients are queued for a server connection.

## TL;DR priority order

1. **Chunk the batch** so it holds locks briefly (commit every N rows).
2. **Give the batch a `lock_timeout` and/or `SKIP LOCKED`** so it yields to OLTP.
3. **Give OLTP a `lock_timeout`** so blocked requests fail fast and return their connection.
4. **Run the batch on its own isolated pool/endpoint** so it can't starve OLTP.
5. Only then, tune pool `connectionTimeout` / leak detection — never just enlarge the pool.
