# `LISTEN` / `NOTIFY`: event-driven wakeups in PostgreSQL

`LISTEN` / `NOTIFY` is PostgreSQL's built-in publish/subscribe signal. A session
subscribes to a named channel (`LISTEN channel`), and any session can publish to it
(`NOTIFY channel [, payload]` or the function form `pg_notify('channel', 'payload')`).
It's the standard way to turn a **polling** worker into an **event-driven** one —
for example, to wake an embedding worker the instant a job is enqueued instead of
on the next poll tick (see
[AI-Integration/embedding-pipeline-patterns.md](../../AI-Integration/embedding-pipeline-patterns.md) §6).

The one rule to keep in mind: **`NOTIFY` is a doorbell, not a mailbox.** It's a
best-effort in-memory signal, not durable storage. If no session is listening at
the moment a notification is delivered, it is simply gone. So it pairs with a
durable queue table that remains the source of truth; the notification only reduces
latency.

All behavior below verified on **PostgreSQL 18.6**.

---

## 1. The smallest example

Two `psql` sessions. Session 1 subscribes and waits; session 2 fires.

**Session 1 (listener):**

```sql
LISTEN jobs;
-- psql only prints notifications at a command boundary (between statements), not
-- while a query is running. pg_sleep just keeps the session busy so you have a
-- window to watch; it is NOT a recheck interval and NOT an exit timer.
SELECT pg_sleep(30);
```

Be aware of the timing (verified on PG 18.6): a notification that arrives *during*
`pg_sleep(30)` is **buffered and printed only when the sleep returns** — up to 30 s
later — because psql doesn't interrupt a running query to print. So a single long
`pg_sleep` is a poor way to watch live. To see notifications promptly, run **several
short, separate** statements so each one is a command boundary that flushes anything
pending:

```sql
LISTEN jobs;
SELECT pg_sleep(1);   -- run these one after another (or paste a few at once);
SELECT pg_sleep(1);   -- a notification surfaces right after the statement that was
SELECT pg_sleep(1);   -- running when it arrived — within ~1s, not 30s
```

> Note: `\watch` does **not** work for this — verified on PG 18.6, a `\watch`
> loop never printed an arriving notification, because it doesn't process pending
> notifications between iterations. Use *separate* statements as above.

A real application doesn't poll like this — its driver delivers notifications on the
socket asynchronously (the worker example in §4 uses `select()` on the connection).
The `pg_sleep` trick is only for eyeballing it in `psql`.

**Session 2 (notifier):**

```sql
NOTIFY jobs, 'hello';
-- or, when the channel/payload is dynamic (payload must be a value, not an identifier):
SELECT pg_notify('jobs', 'hello');
```

Session 1 prints:

```
Asynchronous notification "jobs" with payload "hello" received from server process with PID 42957.
```

Use `pg_notify(text, text)` (the function) whenever the channel name or payload is
computed — `NOTIFY` the statement requires a literal channel identifier.

---

## 2. `NOTIFY` is transactional

A notification is queued on `NOTIFY` but **only delivered when the transaction
commits** — and discarded if it rolls back. This is the property that makes it safe
to fire from inside a trigger: the signal and the data change are atomic.

Verified — three transactions, the middle one rolled back:

```sql
BEGIN; SELECT pg_notify('demo', 'committed-1'); COMMIT;
BEGIN; SELECT pg_notify('demo', 'rolled-back'); ROLLBACK;
BEGIN; SELECT pg_notify('demo', 'committed-2'); COMMIT;
```

A session running `LISTEN demo` receives exactly:

```
Asynchronous notification "demo" with payload "committed-1" ...
Asynchronous notification "demo" with payload "committed-2" ...
```

The `rolled-back` payload is **never delivered** — the ROLLBACK suppressed it.

Two more measured properties worth knowing:

- **Duplicate folding.** Identical `(channel, payload)` notifications emitted in the
  *same* transaction are collapsed to one. Firing `pg_notify('d','same')` twice plus
  `pg_notify('d','other')` once in one transaction delivered `same` **once** and
  `other` once. Don't rely on notification *count* — treat it as "something changed,
  go look."
- **Payload limit.** The payload must be **under 8000 bytes** — `repeat('x', 7999)`
  succeeds; `repeat('x', 9000)` raises `ERROR: payload string too long`. Send an
  **id**, not the data; the listener reads the row itself.

---

## 3. The durability gap (why you still need a queue)

If no session is listening when a notification is delivered, it is lost. Verified —
fire first, then connect a listener:

```sql
-- nobody listening yet:
BEGIN; SELECT pg_notify('late', 'you-will-miss-this'); COMMIT;
```

```sql
-- a listener connects AFTER the commit:
LISTEN late;  SELECT pg_sleep(2);   -- receives nothing
```

Result: **missed.** A worker that was restarting, deploying, or briefly disconnected
never learns about that job. That's why the production pattern keeps a **durable
queue table** as the record and uses `NOTIFY` only as a latency shortcut:

1. On enqueue, write the durable queue row **and** `pg_notify` the channel (same
   transaction, so both or neither).
2. A worker `LISTEN`s and, on any notification, drains the queue with
   `FOR UPDATE SKIP LOCKED`.
3. The worker **also** polls on a slow timer (e.g. every few seconds) as a backstop,
   so a missed notification only delays a job by one poll interval instead of
   losing it.

The queue is correctness; the notification is just speed.

---

## 4. Worked pattern: wake an embedding worker

This is the exact wiring referenced by the embedding pipeline doc. The enqueue
trigger writes the durable `embedding_queue` row and rings the doorbell atomically:

```sql
CREATE OR REPLACE FUNCTION enqueue_embedding() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO embedding_queue (document_id) VALUES (NEW.id)
    ON CONFLICT (document_id) DO UPDATE SET enqueued_at = now();

    PERFORM pg_notify('embedding_jobs', NEW.id::text);   -- doorbell; committed with the row
    RETURN NEW;
END $$;
```

A worker (psycopg 3 shown; any driver with async-notification support works) listens
and drains, with a poll fallback:

```python
import select, psycopg

conn = psycopg.connect("dbname=ai_demo", autocommit=True)
conn.execute("LISTEN embedding_jobs")

def drain():
    # claim + embed + upsert via FOR UPDATE SKIP LOCKED (see embedding-pipeline-patterns.md §4)
    while process_embedding_batch(conn):   # returns rows processed; 0 when empty
        pass

drain()  # catch up on anything enqueued before we connected
while True:
    # block up to 5s for a notification; the timeout IS the poll fallback
    if select.select([conn], [], [], 5) != ([], [], []):
        conn.execute("SELECT 1")          # let psycopg collect notifications
        conn.notifies()                   # we don't need the payloads, just the wakeup
    drain()                               # on a signal OR every 5s, drain the durable queue
```

The payload (`document_id`) is available if you want to process just that row, but
draining the queue is more robust — it naturally picks up anything a missed
notification would have dropped.

---

## 5. Managed PostgreSQL: RDS and Aurora

> Not tested here against managed endpoints — the following is from AWS
> documentation and guidance, not a measured result in this repo.

- **Amazon RDS for PostgreSQL** supports `LISTEN` / `NOTIFY` normally — it's a
  single-instance engine, so it behaves like self-managed PostgreSQL.
- **Amazon Aurora PostgreSQL (provisioned)** supports it, with one architectural
  caveat: notifications are an **in-memory, per-instance** mechanism and do **not**
  cross instances. A `NOTIFY` on the **writer** is not delivered to a `LISTEN`er
  connected to a **reader** endpoint. So the listening worker must connect to the
  **same instance** where the `NOTIFY` commits (the writer). This also means
  notifications are not replicated and don't survive a failover — another reason the
  durable queue + poll fallback (§3) matters on Aurora.
- **Aurora Serverless** — AWS advises **against** relying on `LISTEN` / `NOTIFY`: a
  long-lived listening connection conflicts with the auto-pause/scaling model (a
  scale or pause event drops the connection and any pending notifications). Prefer
  **polling** the queue table there, or an external event bus (SQS/SNS/EventBridge)
  driven by the application.

On any managed service the guidance is the same as §3, only more so: **keep the
durable queue as the source of truth and poll as a backstop.** Treat `NOTIFY` as an
optional latency optimization that may be weaker or unavailable depending on the
deployment, never as the delivery guarantee.

---

## 6. When to use it (and when not)

Use `LISTEN` / `NOTIFY` when:

- you already have a durable queue and only want **lower latency** than polling;
- events are frequent enough that per-event wakeups beat a tight poll loop;
- producer and consumer share one database (and, on Aurora, one instance).

Reach for something else when:

- you need **durable, at-least-once** delivery across restarts → a queue table
  (poll or notify+poll), or an external broker (SQS, Kafka, RabbitMQ);
- consumers are in **other databases / regions**, or on Aurora **readers** → an
  external event bus;
- you're on **Aurora Serverless** → poll, or push events from the app layer.

---

## Summary

1. `LISTEN channel` subscribes; `NOTIFY channel, 'payload'` / `pg_notify(...)`
   publishes. It's a built-in signal, not a stored queue.
2. **Transactional:** delivered on commit, dropped on rollback — safe to fire from a
   trigger. Duplicate `(channel, payload)` in one txn folds to one; payload < 8000 B.
3. **Best-effort:** missed entirely if no one is listening — so keep a **durable
   queue** as the truth and use `NOTIFY` only to shorten latency, with a poll
   fallback.
4. **RDS**: works normally. **Aurora (provisioned)**: works but is per-instance
   (writer only, not readers, not across failover). **Aurora Serverless**: not
   recommended — poll instead.
5. Primary use in this repo: waking the async embedding worker —
   [AI-Integration/embedding-pipeline-patterns.md](../../AI-Integration/embedding-pipeline-patterns.md) §6.
