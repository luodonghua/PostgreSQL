# Choosing & Operating PostgreSQL Tools (Migration, Tuning, Operation) — a Checklist

The ecosystem around PostgreSQL is full of helpers: migration tools, tuning
advisors, schema-diff utilities, and increasingly **AI/LLM agents and MCP servers**
that connect a model directly to your database. They're useful, but each one is
also a new way to break production. This doc is a **selection and operations
checklist** — questions to ask *before* you adopt a tool, and guardrails to put in
place *before* you let it touch a real database.

It's deliberately vendor-neutral: the same questions apply to a migration framework,
a `pg_stat_statements` dashboard, or an LLM that writes SQL for you. The emphasis is
on **operation and security**, because that's where these tools cause the most
expensive, hardest-to-undo damage.

> Why a checklist? Because the failure modes here are not exotic — they're the same
> few mistakes (too much privilege, no timeout, no row cap, an unbounded or
> network-coupled call) made over and over. A checklist is how you avoid learning
> each one the hard way.

---

## 1. First question: where does the tool run, and what can it reach?

Before anything else, classify the tool on two axes — this determines its entire
risk profile:

| Axis | Options | Why it matters |
|------|---------|----------------|
| **Privilege** | read-only / DML / DDL / superuser | caps the worst-case blast radius |
| **Locus** | runs *in* the DB (extension, SQL function) vs *beside* it (app/worker/agent) | in-DB tools couple DB health to the tool's behavior; external tools are isolated |

A read-only reporting tool and a superuser migration runner are not the same kind of
risk, and shouldn't get the same trust. **Give each tool the least privilege and the
most isolation its job allows.** Most "advisor"/"assistant" tools only need to
*read*; very few genuinely need DDL or superuser.

---

## 2. Migration & schema-change tools

| ✅ Check | Why |
|---------|-----|
| Does it run changes in a **transaction** and roll back cleanly on failure? | a half-applied migration is the worst state to be in |
| Does it support **`lock_timeout`** / short lock windows for DDL? | an `ALTER TABLE` that grabs an `ACCESS EXCLUSIVE` lock and waits behind a long query can stall all traffic |
| Does it avoid **full table rewrites** where possible (or warn you)? | adding a `NOT NULL DEFAULT`, changing a type, etc. can rewrite the whole table and hold locks for minutes |
| Is the change log **ordered, versioned, and idempotent** (re-runnable)? | so a retried or partially-applied migration converges, not corrupts |
| Does it have a **tested down/rollback** path, or a forward-fix plan? | "we'll just revert" is not a plan unless you've tried it |
| Does it run against a **staging copy** first? | migrations are the classic "worked in dev, locked prod" trap |

**Pitfall to avoid:** tools that apply DDL with no lock timeout. On a busy table,
a blocked `ALTER` queues behind it every subsequent query on that table — a brief
schema change becomes a site-wide outage. Always bound DDL with `lock_timeout` and,
for big tables, prefer online patterns (e.g. `pg_repack`, add-column-then-backfill;
see [Maintenance/postgresql-maintenance.md](../Maintenance/postgresql-maintenance.md)).

---

## 3. Tuning & advisory tools

| ✅ Check | Why |
|---------|-----|
| Does it **read** stats (`pg_stat_statements`, `pg_stat_user_tables`) rather than guess? | advice not grounded in your workload is noise |
| Does it **recommend**, or does it **auto-apply**? Auto-apply needs far more scrutiny. | an index created automatically on a hot table is a write-amplification and lock surprise |
| Does it account for the **write cost** of its suggestions? | every index it proposes slows `INSERT`/`UPDATE` and adds vacuum load — an advisor that only counts read speedups is half-blind |
| Does it suggest changes you can **test and measure**, not just trust? | verify with `EXPLAIN (ANALYZE, BUFFERS)` on your data before/after |
| Does it understand **your** PostgreSQL version's planner/features? | advice for PG 12 can be wrong on PG 18 |

**Pitfall to avoid:** blindly applying an index advisor's full list. Indexes aren't
free — each one adds write latency, bloat, and vacuum work. Add them one at a time,
measure, and keep only the ones that earn their keep. (Index internals and the
read/write trade-off: [Development/Indexes/index-comparison.md](../Development/Indexes/index-comparison.md).)

---

## 4. Operational / runtime tools (incl. AI agents & MCP servers)

This is where AI tooling lands: an LLM or MCP server that runs queries on your
behalf, a chatbot answering from SQL, an agent doing "AIOps." These are powerful and
the **highest-risk** category, because they issue *dynamic, model-generated* commands
at runtime. Treat every one as untrusted input to your database.

### Correctness
- **Answer only from real query results.** If the tool synthesizes an answer the SQL
  didn't return, it will confidently hallucinate. Empty result → "nothing found,"
  never improvisation.
- **Stable output shape.** Downstream code integrates against the response contract
  (text + rows + the SQL used); keep column names and ordering predictable. Expose
  **views** with fixed shapes rather than raw tables, so you can evolve the schema
  behind them.

### Performance (every tool path, no exceptions)
- **Row caps on every query.** An assistant is not a bulk-export job; a missing
  `LIMIT` turns one bad prompt into a million-row scan. Enforce a cap in the tool
  layer, not just by hoping the model adds `LIMIT`.
- **`statement_timeout` on the tool's role.** A bad or ambiguous request must become
  a *fast failure*, not a slow resource drain. Set it on the role the tool connects
  as, so it can't be prompted away.
- **Index what the tools actually touch.** Vector columns need their ANN index
  (HNSW/IVFFlat — [pgvector-indexes.md](pgvector-indexes.md)); queue/status tables
  need their claim indexes ([Performance/postgresql-as-queue-table.md](../Performance/postgresql-as-queue-table.md));
  views inherit the underlying tables' indexes.

### Security (the part people skip and regret)
- **Dedicated least-privilege role.** The tool connects as a role with **read-only**
  access to **only** the schemas/views it needs — no writes, no DDL, no `pg_catalog`
  spelunking into unrelated data. This single control caps the blast radius of a
  prompt-injected or buggy tool.
- **Validate any dynamic SQL** before executing it: `SELECT`-only, reject multiple
  statements / stacked queries (no stray `;`), block dangerous keywords
  (`INSERT/UPDATE/DELETE/DROP/ALTER/COPY/GRANT`), and allow only approved
  schemas/views. **Parameterize** rather than string-concatenate user/model input.
- **Query views (`api.*`), not raw tables.** A view is a controlled exposure surface:
  you decide which columns leak, and you can change the physical schema without
  changing what the tool sees.
- **Assume prompt injection.** Content the model reads (rows, documents, user
  messages) may contain instructions. The role's privileges — not the model's
  "judgment" — must be what actually stops a destructive action. Defense is the
  grant, not the prompt.

### Observability (your flight recorder)
- **Return which tool/route handled the request** so routing is debuggable.
- **Return the exact SQL executed** for dynamic-SQL paths — every answer gets an
  audit trail.
- **Log each tool call:** timestamp, tool, the question, `row_count`, latency, and
  any error text. When results "feel off," this log is how you find out why.

---

## 5. Security hygiene for tools that call external APIs

If a tool (or the database itself) calls out to an external model/API, add these:

- **No hardcoded keys.** Never bake an API key into a SQL function or a committed
  file. Load secrets from a secrets manager into the app/worker tier; rotate them
  regularly. Session-scoped settings (`current_setting`) are fine for a local demo,
  not for production.
- **Control egress.** A database making outbound internet calls is an unusual and
  risky posture — add network egress controls / allow-lists so a compromised
  function can't exfiltrate data or reach arbitrary endpoints.
- **Prefer calling models from the app/worker tier, not the database.** This is the
  strong recommendation from our pipeline work
  ([embedding-pipeline-patterns.md](embedding-pipeline-patterns.md) §0): the database
  is precious and hard to scale; an in-backend network call couples DB health to an
  external service's latency and failures, and holds a backend process (and possibly
  locks) for the whole round-trip. Let the app compute vectors/answers and the
  database **store and serve** them.
- **On managed PostgreSQL, in-DB external calls are usually not even possible.** RDS
  and Aurora don't allow untrusted languages (`plpython3u`) or arbitrary
  HTTP-from-SQL, so a raw call to a third-party API (e.g. OpenAI) from inside the DB
  won't work there at all. The only in-database route is the provider's own
  integration — e.g. **Aurora Machine Learning**, which exposes **Amazon Bedrock /
  SageMaker / Comprehend** (same Region) as SQL functions — which locks you to
  AWS-hosted models. For anything else, the call must live in the app/worker tier.
  *(Managed-service specifics per AWS documentation; confirm against your version.)*

---

## 6. A connection to lessons already in this repo

These checks aren't abstract — they encode failures we've reproduced and documented:

- **"Set a `statement_timeout`"** — see long-running-query behavior in
  [RDS-PostgreSQL/simulate-long-running-query.md](../RDS-PostgreSQL/simulate-long-running-query.md).
- **"A slow call inside a DB transaction stalls OLTP"** — measured, with the fix, in
  [embedding-pipeline-patterns.md](embedding-pipeline-patterns.md) §4 and
  [Performance/postgresql-as-queue-table.md](../Performance/postgresql-as-queue-table.md) §2.
- **"Least privilege via roles and schema `USAGE`"** —
  [Security/schema-usage-privilege.md](../Security/schema-usage-privilege.md).
- **"Indexes cost writes"** —
  [Development/Indexes/index-comparison.md](../Development/Indexes/index-comparison.md).
- **"Pool exhaustion when one tool holds connections/locks"** —
  [Connection-Pooling/lock-contention-pool-exhaustion.md](../Connection-Pooling/lock-contention-pool-exhaustion.md).

---

## Summary — the one-screen checklist

**Before adopting any PostgreSQL tool:**

- [ ] What privilege does it *actually* need? Grant the least; default to read-only.
- [ ] Does it run **in** the DB or **beside** it? Prefer beside (isolation).
- [ ] Migration: transactional, `lock_timeout`, no surprise table rewrite, tested on staging, rollback plan.
- [ ] Tuning: grounded in real stats, recommends (not auto-applies), accounts for write cost, measurable.
- [ ] Operational/AI: row caps + `statement_timeout` on a dedicated **read-only role**; dynamic SQL validated (SELECT-only, single statement, approved views); query views not raw tables; assume prompt injection.
- [ ] Observability: log tool, SQL, row_count, latency, errors — every call.
- [ ] External calls: no hardcoded keys (use a secrets manager + rotation); control egress; **prefer the app/worker tier**; on RDS/Aurora, in-DB calls are limited to the provider's own ML integration.

The through-line: **the database's own guardrails — roles, timeouts, row caps,
views, egress controls — are what keep a tool safe, not the tool's good intentions
or the model's judgment.**
