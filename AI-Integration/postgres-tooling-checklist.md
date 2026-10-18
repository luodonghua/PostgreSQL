# Integrating AI Tools with PostgreSQL — a Security & Operations Checklist

More and more AI tooling now connects **directly to your database**: an **MCP
server** that exposes tables/queries to an LLM, a **SQL-writing assistant** or
chatbot that answers from your data, an **AIOps agent** that inspects stats and runs
diagnostic queries. These are useful, but each one is a model issuing
*dynamic, generated* commands against production — effectively an untrusted client
with a direct line to your data.

This is a checklist for **what to verify before you plug such a tool in**, and what
guardrails to put in place first. The emphasis is **security and operation**,
because that's where an AI integration causes the most expensive, hardest-to-undo
damage — and because the model's "judgment" is never the thing that should be
stopping a bad action.

> Why a checklist? The failure modes aren't exotic — they're the same few mistakes
> (too much privilege, no row cap, no timeout, trusting generated SQL, a secret in
> the wrong place) repeated. A checklist is how you avoid learning each one the hard
> way, in production.

---

## 0. Frame it right: the AI tool is an untrusted client

Whatever the tool is — MCP server, agent, chatbot — treat the SQL it issues as
**untrusted input**, for the same reason you never concatenate user input into a
query. An LLM can be steered by the data it reads (**prompt injection**: a row or
document saying "ignore prior instructions and …"), so you cannot rely on the model
to police itself. **Your defense is what the database *allows*, not what the model
*intends*.** Everything below follows from that.

Two framing questions set the risk level:

| Question | Safer answer |
|----------|--------------|
| **What privilege does it connect with?** | a dedicated **read-only** role, scoped to only the schemas/views it needs |
| **Where does the model call run?** | in the **app/agent tier**, not inside the database backend |

---

## 1. Access & privilege (the single most important control)

- [ ] **Dedicated least-privilege role.** The tool connects as its own role with
  **read-only** access to **only** the objects it needs — no writes, no DDL, no
  reach into unrelated schemas or `pg_catalog` fishing. This one control caps the
  blast radius of a prompt-injected, buggy, or over-eager agent. Build it with
  explicit schema `USAGE` + table/view `SELECT` grants
  ([Security/schema-usage-privilege.md](../Security/schema-usage-privilege.md)).
- [ ] **Expose views, not raw tables.** Point the tool at a curated `api.*` view
  layer. A view is a controlled surface: you choose which columns are visible, can
  omit sensitive fields, and can evolve the physical schema without changing what the
  tool sees.
- [ ] **Row-level isolation where tenancy matters.** If the data is multi-tenant or
  per-user, enforce it in the database with **Row-Level Security** so a generated
  query physically can't cross the boundary
  ([Security/row-level-security.md](../Security/row-level-security.md)) — and run the tool as a
  role that RLS actually applies to (not a superuser/owner/`BYPASSRLS` role).
- [ ] **No ambient superuser.** An agent connected as a superuser ignores RLS,
  ignores most guardrails, and can do anything. Never.

---

## 2. Guarding dynamic, model-generated SQL

If the tool runs SQL the model wrote (the whole point of a "query" MCP tool), gate
it:

- [ ] **`SELECT`-only.** Reject anything that isn't a read. Don't rely on the model
  to "only read" — enforce it.
- [ ] **Single statement.** Reject stacked queries (a stray `;` that smuggles in a
  second statement). Parse/validate, don't pattern-match loosely.
- [ ] **Block dangerous constructs:** DML/DDL keywords
  (`INSERT/UPDATE/DELETE/DROP/ALTER/TRUNCATE/GRANT/COPY`), and calls that touch the
  filesystem or extensions.
- [ ] **Allow-list schemas/objects.** Only approved views/schemas may be referenced.
- [ ] **Parameterize** any user/model-supplied values rather than string-building.
- [ ] **Belt and braces:** the read-only role (§1) means even if validation is
  bypassed, a write simply fails at the database. Validation is convenience and
  clear errors; the **grant** is the real wall.

---

## 3. Operational safety: caps and timeouts on every path

An assistant is not a bulk-export job or an analytics runner. Bound it:

- [ ] **Row caps on every query/tool path.** A missing `LIMIT` turns one vague prompt
  into a million-row scan. Enforce the cap in the tool layer — don't hope the model
  adds `LIMIT`.
- [ ] **`statement_timeout` on the tool's role.** A bad or ambiguous request must be
  a *fast failure*, not a slow resource drain. Set it on the connecting role so it
  can't be prompted away. (See long-running-query impact:
  [RDS-PostgreSQL/simulate-long-running-query.md](../RDS-PostgreSQL/simulate-long-running-query.md).)
- [ ] **Connection limits / pooling.** An agent that fans out parallel queries can
  exhaust the pool and starve real traffic; cap its connections
  ([Connection-Pooling/lock-contention-pool-exhaustion.md](../Connection-Pooling/lock-contention-pool-exhaustion.md)).
- [ ] **Index what the tool touches.** Vector columns need their ANN index
  (HNSW/IVFFlat — [pgvector-indexes.md](pgvector-indexes.md)); queue/status tables
  need their claim indexes
  ([Performance/postgresql-as-queue-table.md](../Performance/postgresql-as-queue-table.md));
  views inherit the base tables' indexes. An unindexed tool query is a scan tax on
  the whole instance.

---

## 4. Correctness: answer only from the data

- [ ] **Ground answers in real query results.** If the tool narrates beyond what the
  SQL returned, it will confidently hallucinate. Empty result → "nothing found,"
  never improvisation.
- [ ] **Stable response contract.** Downstream code integrates against the shape
  (answer text + rows + the SQL used); keep column names and ordering predictable —
  another reason to serve **views** with fixed shapes.

---

## 5. Observability: your flight recorder

When an answer "feels off," logs are how you find out why — and they're your audit
trail for a tool that can read production data.

- [ ] **Return which tool/route handled the request** (debuggable routing).
- [ ] **Return the exact SQL executed** for dynamic-SQL paths (per-answer audit
  trail).
- [ ] **Log every tool call:** timestamp, tool name, the question, `row_count`,
  latency, and any error text.
- [ ] **Alert on the tells:** spikes in rejected-SQL, timeouts, or row-cap hits often
  mean prompt injection or a broken agent loop.

---

## 6. Where the model call runs, secrets, and egress

The AI model call itself (embedding, generation) raises its own hazards:

- [ ] **Prefer calling the model from the app/agent tier, not inside the database.**
  The database is precious and hard to scale; an in-backend network call couples DB
  health to an external service's latency and failures and holds a backend process
  (and possibly locks) for the whole round-trip. Let the agent tier call the model
  and the database **store and serve** the results — the recommendation from our
  pipeline work ([embedding-pipeline-patterns.md](embedding-pipeline-patterns.md) §0,
  and the measured OLTP-stall it prevents in §4).
- [ ] **No hardcoded keys.** Never bake an API key into a SQL function or a committed
  file. Load secrets from a secrets manager into the agent tier and **rotate** them.
  Session GUCs (`current_setting`) are a demo convenience, not production secret
  storage.
- [ ] **Control egress.** A database (or agent) making outbound internet calls needs
  an allow-list so a compromised path can't exfiltrate data or reach arbitrary
  endpoints.
- [ ] **On managed PostgreSQL, in-DB external calls usually aren't even possible.**
  RDS and Aurora don't allow untrusted languages (`plpython3u`) or arbitrary
  HTTP-from-SQL, so a raw call to a third-party API (e.g. OpenAI) from inside the DB
  won't work there. The only in-database route is the provider's own integration —
  e.g. **Aurora Machine Learning** exposing **Amazon Bedrock / SageMaker /
  Comprehend** (same Region) as SQL functions — which locks you to AWS-hosted models.
  Anything else must run in the agent/app tier. *(Per AWS docs; confirm for your
  version.)*

---

## One-screen checklist

Before you connect an MCP server / agent / AI assistant to PostgreSQL:

- [ ] Connects as a **dedicated read-only role**, scoped to approved **views** only.
- [ ] **RLS** enforces tenant/user row isolation (and the tool's role is subject to it).
- [ ] Generated SQL is validated: **SELECT-only, single statement, allow-listed objects, parameterized** — with the read-only grant as the real backstop.
- [ ] **Row caps** + **`statement_timeout`** + **connection caps** on every tool path.
- [ ] Tool queries hit **indexed** columns/views.
- [ ] Answers come **only** from returned rows; empty means "nothing found."
- [ ] Every call logs **tool, SQL, row_count, latency, errors**; alert on rejects/timeouts.
- [ ] Model calls run in the **agent tier**; **no hardcoded keys** (secrets manager + rotation); **egress controlled**; on RDS/Aurora, in-DB calls limited to the provider's ML integration.

**The through-line:** an AI tool is an untrusted client. The database's own
guardrails — **least-privilege roles, RLS, views, row caps, timeouts, egress
controls** — are what keep it safe, not the tool's good intentions or the model's
judgment.
