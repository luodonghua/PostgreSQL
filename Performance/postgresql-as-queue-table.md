# PostgreSQL as a Queue Table (`FOR UPDATE SKIP LOCKED`)

You don't always need Kafka/SQS/RabbitMQ to get a work queue. A plain table plus
`SELECT … FOR UPDATE SKIP LOCKED` turns PostgreSQL into a correct, transactional,
multi-consumer queue — workers claim disjoint batches without blocking each
other, and the claim rides in the same transaction as the rest of your work.

This doc covers the two ways a worker **claims** rows — **DELETE-on-claim** and
**UPDATE-to-processing** — with runnable snippets, their trade-offs, and when to
pick each. A concrete use of this pattern (an embedding/vector-refresh queue) is
in [pgvector-indexes.md](../AI-Integration/pgvector-indexes.md) §4.

All behavior below verified on **PostgreSQL 18.6**.

---

## 1. Why `FOR UPDATE SKIP LOCKED`

The whole queue hinges on one locking clause. Several workers run the *same*
claim query concurrently:

```sql
SELECT document_id FROM embedding_queue
ORDER BY enqueued_at
FOR UPDATE SKIP LOCKED      -- the magic
LIMIT 100;
```

- `FOR UPDATE` takes a **row lock** on each returned row, so no other transaction
  can claim it until this one ends.
- `SKIP LOCKED` tells the scan to **skip rows another transaction already holds**
  instead of waiting on them.

Without `SKIP LOCKED`, every worker's `ORDER BY enqueued_at … LIMIT 100` targets
the *same* oldest rows; they serialize on the first row's lock, and all but one
worker stalls — a convoy. With it, worker 2 steps over worker 1's locked rows and
claims the next 100. The queue scales with workers instead of serializing.

Crucially, the plan places the **`LockRows` node *below* `Limit`**:

```text
 Limit
   ->  LockRows
         ->  Index Scan using embedding_queue_enqueued_at_idx on embedding_queue
```

So a row skipped because it's locked is skipped **before** it counts against your
`LIMIT 100`. Each worker gets 100 *genuinely claimable* rows, not
"100 minus whatever is contended."

`SKIP LOCKED` also skips rows that a concurrent transaction has deleted/updated
but **not yet committed** — their in-progress `xmax` is treated as locked — so a
worker never waits on, or re-claims, in-flight work.

> **Index the ordering column.** Every snippet below orders by `enqueued_at`.
> Without an index on it, each claim sorts the whole queue — milliseconds at a few
> thousand rows, seconds at millions, multiplied by every worker. Use a **partial
> index** scoped to claimable rows where the design has a status column (see §3).

---

## 2. Approach A — DELETE-on-claim

The worker **deletes** the rows as it claims them; the row's existence *is* its
"not done yet" state. `RETURNING` hands the claimed IDs back.

```sql
-- claim a batch of up to 100, skipping rows other workers hold
DELETE FROM embedding_queue
WHERE document_id IN (
    SELECT document_id FROM embedding_queue
    ORDER BY enqueued_at
    FOR UPDATE SKIP LOCKED
    LIMIT 100
)
RETURNING document_id;
```

Equivalent, slightly more robust forms join on the physical row (`ctid`) or the
PK so the outer `DELETE` touches exactly the rows the subquery locked:

```sql
WITH claimed AS (
    SELECT ctid FROM embedding_queue
    ORDER BY enqueued_at
    FOR UPDATE SKIP LOCKED
    LIMIT 100
)
DELETE FROM embedding_queue q USING claimed c
WHERE q.ctid = c.ctid
RETURNING q.document_id;
```

### `RETURNING` is a result set, not an array

`RETURNING document_id` yields **one row per deleted row** (100 rows), each a
scalar. If you want a single array value, aggregate in a CTE:

```sql
WITH claimed AS (
    DELETE FROM embedding_queue
    WHERE document_id IN (
        SELECT document_id FROM embedding_queue
        ORDER BY enqueued_at FOR UPDATE SKIP LOCKED LIMIT 100
    )
    RETURNING document_id
)
SELECT coalesce(array_agg(document_id), '{}') AS document_ids FROM claimed;
```

The `coalesce` matters: bare `array_agg` over zero claimed rows returns **`NULL`**,
not `{}`, which tends to break client code that expects to iterate.

### The one correctness requirement: a unique claim key

The `WHERE document_id IN (subquery)` form is safe **only when `document_id` is
unique** (PK/unique constraint). If it isn't, the outer `DELETE` re-resolves the
predicate and matches *every* row sharing those IDs — including rows another
worker locked and skipped — so it blocks on them and silently undoes
`SKIP LOCKED`. With a unique key the matched set is exactly the locked set, so the
`ctid`/PK-join rewrite buys nothing; the simple `IN` form is fine. Keep the key
unique, or use the `ctid`/PK-join form.

### Verified: workers claim disjoint batches, nobody blocks

8 concurrent workers, each claiming 100 from an 800-row queue, each holding its
transaction open 3 s so **every lock window overlapped**:

```text
worker 1: 100 rows  (min=1   max=100)
worker 3: 100 rows  (min=101 max=200)
worker 4: 100 rows  (min=201 max=300)
worker 6: 100 rows  (min=301 max=400)
worker 7: 100 rows  (min=401 max=500)
worker 5: 100 rows  (min=501 max=600)
worker 2: 100 rows  (min=601 max=700)
worker 8: 100 rows  (min=701 max=800)

total claimed rows : 800
distinct ids       : 800
DUPLICATE ids      : 0
errors / deadlocks : none
rows left in queue : 0
```

A perfect partition — eight disjoint batches, zero duplicates, no worker blocked
or deadlocked. In a two-session timing test, the second worker's claim returned in
**11 ms** while the first still held its locks, confirming no waiting.

### Pros / cons

**Pros**
- **Simplest possible** — one statement, no status column, no reaper process.
- The table stays small (claimed rows leave immediately); the claimable set is the
  whole table, so no partial index gymnastics.
- No "stuck in `processing` forever" failure mode to manage.

**Cons** — DELETE-on-claim has **two variants** with different crash semantics;
most of these cons apply fully only to the *second* (commit-claim-first) variant:

- **Variant 1 — one transaction** (`BEGIN; DELETE … RETURNING; <process>; <write
  result>; COMMIT`): **crash-safe.** A crash before `COMMIT` rolls the `DELETE`
  back and the queue row **reappears** for another worker — no work lost. The only
  cost is that the slow step may have already run, so the item is **processed
  again** on retry (wasted compute, not lost data) — harmless if the result write
  is an idempotent upsert keyed by the item id. This is the right default for a
  queue table (see the note below on why holding this transaction open is fine).
- **Variant 2 — commit the claim first** (`BEGIN; DELETE … RETURNING; COMMIT`,
  *then* process): the row is gone the instant the claim commits, so a crash
  mid-processing **loses that batch** with no trace and no retry. Only choose this
  if the processing step must not hold *any* transaction open (see note) **and**
  losing a batch is acceptable.
- **No retry / attempt count / dead-letter** — once the delete commits (variant 2,
  or after a successful commit in variant 1) the row no longer exists to carry that
  state. A failed-but-not-crashed process in variant 1 that `ROLLBACK`s simply
  re-exposes the row, which gives you an implicit retry but no attempt *counter* or
  dead-letter after N tries.
- **No observability** — a claimed row isn't visibly distinct from an un-enqueued
  one; you can't query "what's in flight."
- Delete/rollback churn produces dead tuples → vacuum pressure on the queue table
  (see §4).

> **Why is holding the transaction open across the slow step OK here, when the
> usual advice is "never hold a transaction open across a slow call"?**
> Because that advice is about the **OLTP table** — the hot table serving
> user-facing traffic. This transaction is on the **queue table**, which nothing
> does OLTP on. Holding it open across the slow step:
>
> - **locks only the claimed queue rows**, which `SKIP LOCKED` already hides from
>   other workers — so **no OLTP writer is blocked**; OLTP never touches these rows
>   beyond the tiny enqueue;
> - **decouples OLTP latency from processing latency**, which is the entire reason
>   the queue exists — the OLTP transaction committed long ago.
>
> So **variant 1 (one transaction on the queue table)** gives you *both* crash
> safety *and* zero OLTP impact. Its only real cost is a longer-lived worker
> transaction holding a snapshot open, which adds some dead-tuple/vacuum pressure
> **on the queue table** (handled by §4's autovacuum recipe) and matters only if
> the processing step is extremely long. Prefer variant 1; reach for variant 2
> only when the slow step genuinely cannot run inside any transaction (e.g. it must
> not pin a snapshot at all) and a lost batch is acceptable.

**Choose DELETE-on-claim when** you don't need attempt counts, dead-lettering, or
in-flight visibility. Use **variant 1** (single transaction) by default — it's
crash-safe. Fall back to **variant 2** only when the slow step can't be inside a
transaction and losing a batch is acceptable or cheaply recoverable (the work is
re-derivable from a source of truth, or a "best-effort refresh" queue where a
dropped item is simply re-enqueued on the next source update).

---

## 3. Approach B — UPDATE-to-processing (claim, process, then finish)

The worker **marks** rows `processing` instead of removing them, does the slow
work, then transitions them to `done`/deletes them. A **reaper** resets rows
stuck in `processing` (crashed workers) back to `pending`.

```sql
CREATE TABLE embedding_queue (
    document_id bigint PRIMARY KEY,
    status      text        NOT NULL DEFAULT 'pending',   -- pending | processing | failed
    attempts    int         NOT NULL DEFAULT 0,
    enqueued_at timestamptz NOT NULL DEFAULT now(),
    claimed_at  timestamptz
);

-- partial indexes: only the rows each scan actually cares about
CREATE INDEX eq_pending_idx    ON embedding_queue (enqueued_at) WHERE status = 'pending';
CREATE INDEX eq_processing_idx ON embedding_queue (claimed_at)  WHERE status = 'processing';
```

**Claim** — select `pending` with `SKIP LOCKED`, flip to `processing`, bump
`attempts`, stamp `claimed_at`:

```sql
WITH claimed AS (
    SELECT document_id FROM embedding_queue
    WHERE status = 'pending'
    ORDER BY enqueued_at
    FOR UPDATE SKIP LOCKED
    LIMIT 100
)
UPDATE embedding_queue q
SET status = 'processing', attempts = attempts + 1, claimed_at = now()
FROM claimed c
WHERE q.document_id = c.document_id
RETURNING q.document_id;
```

The plan uses the partial index for the claim and locks before limiting:

```text
 Update on embedding_queue q
   CTE claimed
     ->  Limit
           ->  LockRows
                 ->  Index Scan using eq_pending_idx on embedding_queue
                       Filter: (status = 'pending')
   ->  Hash Join ...
```

**Finish** — after the slow work succeeds, remove (or mark `done`) the rows:

```sql
DELETE FROM embedding_queue WHERE document_id = ANY($1);   -- $1 = claimed id[]
-- or: UPDATE … SET status='done' if you keep an audit trail / dedup window
```

**Reaper** — a periodic job that reclaims rows a dead worker left behind:

```sql
UPDATE embedding_queue
SET status = 'pending', claimed_at = NULL
WHERE status = 'processing'
  AND claimed_at < now() - interval '5 min';   -- > your max processing time
-- optionally: route to 'failed' once attempts exceeds a cap (dead-letter)
```

### Verified: disjoint claims, and the reaper reclaims crashed work

5 concurrent workers each claiming 100 pending from a 500-row queue (locks held
2 s, fully overlapping):

```text
worker 1..5: 100 rows each
total claimed : 500   distinct: 500   dupes: 0
→ status breakdown: processing | 500
```

Then simulating a crashed worker (back-date 40 `processing` rows to 10 min ago)
and running the reaper:

```text
reaped | 40
→ status breakdown:  pending | 40   processing | 460
```

The 40 stale rows returned to `pending` — available for re-claim — while the
healthy `processing` rows were untouched. No work lost.

### Pros / cons

**Pros**
- **Crash-safe / at-least-once.** A worker that dies mid-processing leaves its
  rows in `processing`; the reaper re-queues them. Nothing is silently dropped.
- **Retries, back-off, dead-lettering** via `attempts` and a `failed` status.
- **Observability** — `SELECT status, count(*) … GROUP BY status` shows pending /
  in-flight / failed at a glance.

**Cons**
- **More moving parts** — a status column, two partial indexes, and a **reaper**
  process/cron you must run and tune.
- **At-least-once means consumers must be idempotent** — a reaped row may be
  processed twice (first worker didn't actually die, or finished after the reaper
  fired). Make the finish step an upsert / idempotent write.
- **Two writes per item** (claim + finish) and the `status` updates create dead
  tuples → vacuum pressure, same as DELETE (see §4).
- Reaper timeout tuning: too short re-queues slow-but-alive work (duplicate
  processing); too long delays recovery from real crashes. Set it above your P99
  processing time.

**Choose UPDATE-to-processing when** losing an item is **not** acceptable, work
isn't cheaply re-derivable, or you need retries / dead-lettering / visibility —
i.e. most "real" job queues.

---

## 4. Shared operational notes

**Mind the transaction boundary around the slow step.** You have two shapes (see
§2): wrap claim + process + finish in **one** transaction (crash-safe; the claimed
rows reappear on rollback), or commit the claim first and process after (no
open transaction during the slow step, but a crash loses the batch). Either way
the transaction is on the **queue table**, not an OLTP table — so holding it open
blocks no OLTP writer (`SKIP LOCKED` hides the claimed rows) and doesn't pin the
OLTP hot table's horizon. The cost of the one-transaction shape is a longer-lived
snapshot adding dead-tuple pressure **on the queue table** (handled by the
autovacuum recipe below) and matters only if the slow step is extremely long.
UPDATE-to-processing (§3) always uses short claim/finish transactions with the
slow step strictly between them, and leans on the reaper for crash recovery.

**A claim can return fewer than `LIMIT` rows — even zero.** `SKIP LOCKED` returns
what's *available*: if contention is high or the queue is nearly drained, a worker
may get a short batch or none. Treat an empty claim as "sleep briefly and retry,"
**not** as an error or an empty downstream call.

**Vacuum the churn.** Both patterns generate dead tuples fast (DELETE, or the
`pending→processing→done` updates). A busy queue table benefits from **aggressive
autovacuum** so the table and its indexes don't bloat:

```sql
ALTER TABLE embedding_queue SET (
  autovacuum_vacuum_scale_factor = 0.0,
  autovacuum_vacuum_threshold    = 1000,     -- vacuum every ~1000 dead tuples
  autovacuum_vacuum_cost_delay   = 0
);
```

**Wake workers with `LISTEN`/`NOTIFY` instead of tight polling.** Keep the table
as the durable source of truth (NOTIFY is best-effort, not delivered to
disconnected workers); use a notify only to prompt an idle worker to run its claim
query immediately rather than on its next poll tick.

**Batch size.** Bigger batches = better throughput and fewer transactions, but
more memory, slower time-to-first-result, and a larger retry blast radius; smaller
= fresher/smoother but more overhead. ~100 rows/batch with a few parallel workers
is a sane starting point.

---

## 5. Decision guide

| Question | DELETE-on-claim | UPDATE-to-processing |
|----------|-----------------|----------------------|
| Crash-safe (no lost work)? | **yes, variant 1** (one txn); no, variant 2 | **yes** (reaper re-queues) |
| Need retries / attempt counts / dead-letter? | no | **yes** |
| Need to *see* in-flight / failed work? | no | **yes** |
| Want the fewest moving parts (no reaper)? | **yes** | no |
| Can the slow step run inside a transaction? | required for variant 1 | not required |
| Consumers idempotent (safe to process twice)? | **required** | **required** |
| Writes per item | 1 (delete) | 2 (claim + finish) |

Both shapes are **at-least-once** and need **idempotent** consumers: variant 1 can
re-run the slow step after a rollback, and the reaper in UPDATE-to-processing can
re-dispatch a row whose worker only *looked* dead.

**Rule of thumb:** use **DELETE-on-claim variant 1** (single transaction) when you
don't need attempt counts, dead-lettering, or in-flight visibility — it's the
simplest *and* crash-safe. Move to **UPDATE-to-processing** when you need those
features, or when the slow step must not run inside a transaction (then
UPDATE-to-processing gives you crash recovery via the reaper that variant 2 of
DELETE-on-claim can't). The embedding-refresh queue in
[pgvector-indexes.md](../AI-Integration/pgvector-indexes.md) §4 uses
DELETE-on-claim variant 1: the whole claim→embed→upsert is one transaction, so a
crashed worker's rows simply reappear, and the idempotent upsert keyed by
`document_id` makes a re-embed harmless.

> **When *not* to hand-roll this.** For heavier needs (visibility timeouts,
> archival, metrics out of the box) consider the **`pgmq`** extension, which
> implements this pattern — `SKIP LOCKED` queue, visibility timeout, archive
> table — so you don't maintain the reaper and status machine yourself.

---

## 6. Dead-letter queues (DLQ)

A **poison item** — one that fails every time (malformed content, a document the
model keeps rejecting) — will be retried forever by either pattern. A **dead-letter
queue** breaks that loop: after N attempts, move the item out of the live queue
into a side table for inspection, so healthy work keeps flowing.

One shared DLQ table serves both patterns:

```sql
CREATE TABLE embedding_dead_letter (
    document_id bigint PRIMARY KEY,
    attempts    int         NOT NULL,
    last_error  text,
    enqueued_at timestamptz,
    died_at     timestamptz NOT NULL DEFAULT now()
);
```

### Pattern B (UPDATE-to-processing) — natural fit

B already carries `attempts` and `last_error`, so dead-lettering is just a routing
decision. On a failed batch, bump the counter and record the error; a row at the
cap is routed to the DLQ instead of back to `pending`. Fold this into the **reaper**
so stale *and* over-cap rows are handled in one pass:

```sql
-- reaper: reclaim stale 'processing' rows; dead-letter those past the attempt cap
WITH stale AS (
    SELECT document_id FROM embedding_queue
    WHERE status = 'processing' AND claimed_at < now() - interval '5 min'
    FOR UPDATE SKIP LOCKED
),
reaped AS (
    UPDATE embedding_queue q
    SET status = CASE WHEN q.attempts >= 3 THEN 'dead' ELSE 'pending' END,  -- cap = 3
        claimed_at = NULL
    FROM stale s WHERE q.document_id = s.document_id
    RETURNING q.document_id, q.status, q.attempts, q.last_error, q.enqueued_at
),
moved AS (
    INSERT INTO embedding_dead_letter (document_id, attempts, last_error, enqueued_at)
    SELECT document_id, attempts, last_error, enqueued_at FROM reaped WHERE status = 'dead'
    RETURNING document_id
)
DELETE FROM embedding_queue WHERE document_id IN (SELECT document_id FROM moved);
```

On a failure the worker *catches* (not a crash), record it so the next reaper pass
can act — or dead-letter immediately if already at the cap:

```sql
-- worker's failure handler for a batch it processed but that errored
UPDATE embedding_queue
SET status = 'pending', claimed_at = NULL, last_error = $2   -- $2 = error text
WHERE document_id = ANY($1) AND attempts < 3;                -- $1 = failed id[]
-- rows that just hit attempts >= 3 are left 'processing' for the reaper to dead-letter,
-- or move them here directly with the same DELETE…RETURNING→INSERT as above.
```

### Pattern A (DELETE-on-claim) — needs an out-of-band attempt counter

A deletes the row on claim, so there's nowhere to keep `attempts` *inside* the live
queue. Two lightweight options:

**Option 1 — keep a small `attempts` column and bump it in a separate committed
statement before processing** (so the count survives a crash/rollback of the
processing transaction):

```sql
-- queue carries attempts; worker claims, then in its OWN committed txn bumps the counter
UPDATE embedding_queue SET attempts = attempts + 1
WHERE document_id = ANY($1);                      -- commit this before the model call
```

Then, when a claimed row is already at the cap, route it to the DLQ instead of
processing it:

```sql
WITH dead AS (
    DELETE FROM embedding_queue
    WHERE document_id = ANY($1) AND attempts >= 3  -- $1 = just-claimed id[]
    RETURNING document_id, attempts, enqueued_at
)
INSERT INTO embedding_dead_letter (document_id, attempts, enqueued_at)
SELECT document_id, attempts, enqueued_at FROM dead;
```

**Option 2 — on a caught failure, re-enqueue with an incremented count, or
dead-letter past the cap** (single statement, keeps the live queue clean):

```sql
-- the batch was claimed (deleted) already; decide per row where it goes
INSERT INTO embedding_queue (document_id, attempts, enqueued_at)
SELECT id, prev_attempts + 1, now()
FROM failed_batch                                 -- app-side set: (id, prev_attempts)
WHERE prev_attempts + 1 < 3                        -- still under cap → back to queue
ON CONFLICT (document_id) DO UPDATE SET attempts = EXCLUDED.attempts, enqueued_at = now();

INSERT INTO embedding_dead_letter (document_id, attempts)
SELECT id, prev_attempts + 1 FROM failed_batch WHERE prev_attempts + 1 >= 3;
```

### Draining the DLQ

Inspect, fix the root cause, then requeue selected rows (both patterns):

```sql
-- requeue specific dead-lettered documents after a fix
WITH revived AS (
    DELETE FROM embedding_dead_letter WHERE document_id = ANY($1)
    RETURNING document_id
)
INSERT INTO embedding_queue (document_id)      -- add status/attempts columns for pattern B
SELECT document_id FROM revived
ON CONFLICT (document_id) DO NOTHING;
```

**Pick the cap deliberately:** too low dead-letters transient failures (a model
timeout, a rate-limit blip) that would have succeeded on retry; too high wastes
work on genuine poison items. 3–5 attempts with back-off is a common starting
point. For embedding specifically, distinguish *retryable* errors (HTTP 429/5xx,
timeout → retry) from *permanent* ones (empty/oversized text, unsupported content
→ dead-letter on the **first** occurrence, don't waste the cap).

---

## Summary

1. `FOR UPDATE SKIP LOCKED` is what makes a table a concurrent queue: workers
   claim **disjoint** batches without blocking. `LockRows` sits **below** `Limit`,
   so each worker gets a full batch of genuinely-claimable rows.
2. **DELETE-on-claim** — simplest, no reaper. **Variant 1** (claim + process +
   finish in one transaction) is **crash-safe**: a crash rolls the delete back and
   the row reappears (at-least-once, so the consumer must be idempotent). **Variant
   2** (commit the claim first, then process) avoids an open transaction during the
   slow step but loses the batch on crash. No retries/attempt-count/visibility
   either way. Requires a **unique claim key** for the `IN (subquery)` form;
   `RETURNING` is a result set, use `array_agg` + `coalesce(…, '{}')` for an array.
3. **UPDATE-to-processing** — status + `attempts` + `claimed_at` + a **reaper** that
   re-queues stale `processing` rows. Crash-safe, at-least-once (make consumers
   idempotent), observable; more moving parts.
4. Shared: the claim/finish transactions live on the **queue table**, so holding
   one open across the slow step blocks no OLTP writer (`SKIP LOCKED` hides claimed
   rows) — the only cost is queue-table vacuum pressure. Index the ordering column
   (partial index on the claimable status), tune autovacuum for the churn, and
   treat empty claims as "retry later."
5. **Dead-letter queue (§6):** after an attempt cap, move poison items to a side
   table so healthy work keeps flowing. B does it in the reaper (it already has
   `attempts`); A needs an out-of-band `attempts` counter or re-enqueue-with-count.
6. Real-world use: the async embedding/vector-refresh queue in
   [pgvector-indexes.md](../AI-Integration/pgvector-indexes.md) §4.
