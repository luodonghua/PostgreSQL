# Row-Level Security (RLS): What It Is, How to Use It, Overheads & Pitfalls

Normal GRANTs control access at the **table/column** level — a role can read
`orders` or it can't. **Row-Level Security (RLS)** goes one level finer: it controls
*which rows* a role can see or modify, by attaching **policies** — boolean
expressions PostgreSQL automatically folds into the `WHERE` (and `WITH CHECK`) of
every query on the table. The classic use is **multi-tenancy** ("each tenant sees
only its own rows") and **per-user ownership** ("you see only your records")
enforced in the database, so a bug or SQL-injection in the app tier can't read
across the boundary.

All behavior below verified on **PostgreSQL 18.6**.

---

## 1. The mental model

Two independent switches plus policies:

```sql
ALTER TABLE t ENABLE ROW LEVEL SECURITY;   -- turn RLS on for this table
CREATE POLICY <name> ON t
    [FOR {ALL|SELECT|INSERT|UPDATE|DELETE}]
    [TO <role>]
    USING (<read/visibility predicate>)        -- which existing rows are visible/affected
    [WITH CHECK (<write predicate>)];           -- which new/updated rows are allowed
```

- **`USING`** filters which rows a statement can *see* or *touch* (SELECT/UPDATE/
  DELETE). Rows where it's false simply don't exist for that query.
- **`WITH CHECK`** validates rows a statement tries to *write* (INSERT/UPDATE). A
  row that violates it raises an error instead of silently vanishing.
- Multiple policies on the same command are **OR-combined** (permissive, the
  default); mark them `AS RESTRICTIVE` to **AND** them instead.
- **Enabling RLS with no policy = deny-all** for non-bypassing roles. The default is
  safe: if you forget to add a policy, nobody (except bypassers, §3) sees anything.

---

## 2. A worked example: per-owner visibility

```sql
CREATE TABLE docs (id int PRIMARY KEY, owner text, body text);
INSERT INTO docs VALUES (1,'alice','a1'), (2,'bob','b1'), (3,'alice','a2');

GRANT SELECT, INSERT, UPDATE, DELETE ON docs TO alice, bob;  -- table grant still required
ALTER TABLE docs ENABLE ROW LEVEL SECURITY;

CREATE POLICY p ON docs
    USING      (owner = current_user)       -- see only your own rows
    WITH CHECK (owner = current_user);       -- can only write rows owned by you
```

Verified — connected as `alice`:

```
SET ROLE alice;  SELECT id, owner FROM docs ORDER BY id;
 id | owner
----+-------
  1 | alice
  3 | alice          -- bob's row (2) is invisible, not just unselected
```

And `WITH CHECK` blocks writing outside your boundary (verified):

```
SET ROLE alice;  INSERT INTO docs VALUES (4,'bob','sneaky');
ERROR:  new row violates row-level security policy for table "docs"
```

RLS **complements, not replaces, GRANTs**: a role still needs table-level
privileges *and* must satisfy the policy. No `SELECT` grant → no access, policy or
not.

> **For multi-tenancy, pin the tenant with a session GUC** instead of `current_user`
> (one DB role, many tenants): the app sets `app.tenant_id` per request and the
> policy reads it:
> ```sql
> CREATE POLICY tenant_iso ON events
>     USING (tenant_id = current_setting('app.tenant_id')::int);
> ```
> Set it with `SET LOCAL` inside the request's transaction so it can't leak across
> pooled connections (see pitfall §5).

---

## 3. Who bypasses RLS — the #1 source of "it's not working"

This trips up almost everyone. Three categories ignore RLS, and the rules differ:

| Who | Bypasses RLS? | How to subject them to it |
|-----|---------------|---------------------------|
| **Superusers** | **Always** — even with FORCE | nothing; superusers are never filtered |
| **The table owner** | **Yes, by default** | `ALTER TABLE t FORCE ROW LEVEL SECURITY;` |
| **Roles with `BYPASSRLS`** | **Always** | remove the attribute (`ALTER ROLE r NOBYPASSRLS`) |
| Ordinary roles | No — fully filtered | — |

Verified on PG 18.6:

- Connected as a **superuser**, `SELECT count(*)` returned **all 3** rows despite RLS
  being enabled *and* `FORCE` set — superusers are simply never filtered.
- A **non-superuser table owner** saw **all** rows by default, but after
  `ALTER TABLE … FORCE ROW LEVEL SECURITY` saw only the policy-matching rows (2 → 1
  in the test).

**Takeaways:**
- **Don't test RLS as a superuser or the table owner** — you'll see everything and
  conclude it's broken (or, worse, conclude it's working when it isn't). Test as the
  ordinary application role.
- The application should connect as a **non-superuser, non-owner, non-`BYPASSRLS`**
  role. If your app connects as the table owner, add `FORCE ROW LEVEL SECURITY`.
- RLS is **not** a defense against a superuser or a compromised `BYPASSRLS` role.

---

## 4. Performance: overhead is usually near-zero — *if the predicate is indexable*

A policy's `USING` expression is injected as an extra `WHERE` condition, so the
planner treats it like any predicate. The crucial consequence: **a policy on an
indexed column plans identically to writing that filter by hand.**

Verified — a tenant-isolation policy on an indexed `tenant_id`, `SELECT count(*)
FROM events` (200k rows) produced the *same* plan as the explicit query:

```
 Aggregate
   ->  Bitmap Heap Scan on events
         Recheck Cond: (tenant_id = (current_setting('app.tenant_id'))::integer)
         ->  Bitmap Index Scan on events_tenant_id_idx
               Index Cond: (tenant_id = (current_setting('app.tenant_id'))::integer)
```

So, baseline: **RLS adds no meaningful planner or runtime overhead when the policy
is a simple, sargable predicate on an indexed column.** Index the columns your
policies filter on, exactly as you would for a manual `WHERE`.

### The performance trap: non-inlinable / VOLATILE policy functions

The overhead appears when the policy is **not** a plain predicate — most commonly
when people wrap "access logic" in a PL/pgSQL or `VOLATILE` function. Then the
planner can't use the index and calls the function **once per row**. Measured on the
same 200k-row table:

```
-- policy: USING (can_see(tenant_id))  where can_see is LANGUAGE plpgsql VOLATILE
 Seq Scan on events
   Filter: can_see(tenant_id)
   Rows Removed by Filter: 198000          -- every row scanned + function called
```

Rewriting the predicate as a **`STABLE`, inlinable SQL** function restored the index
immediately:

```
-- policy: USING (can_see(tenant_id))  where can_see is LANGUAGE sql STABLE
 Bitmap Index Scan on events_tenant_id_idx   -- back to the fast plan
```

**Rules for fast policies:**
- Keep the predicate a **plain, sargable expression** on an indexed column where
  possible (`tenant_id = current_setting(...)::int`).
- If you must call a function, make it **`STABLE` (or `IMMUTABLE`) SQL** so it can
  inline; avoid `VOLATILE` and avoid PL/pgSQL for the hot path.
- Session lookups like `current_setting()` are fine — they're stable within a
  statement.
- Remember the policy runs on **every** query against the table, including joins and
  sub-selects — a slow policy taxes the whole workload, not one query.

> **`IMMUTABLE` vs `STABLE` vs `VOLATILE` — the distinction, with one example.**
> These *volatility* labels tell the planner how far it can trust a function's
> result, which is what lets (or forbids) inlining and index use.
>
> | Class | Promise | Example | Can the planner reuse / optimize it? |
> |-------|---------|---------|--------------------------------------|
> | **IMMUTABLE** | same input → same output **forever**, anywhere | `lower('HeLLo')` → always `hello` | fully — can even pre-compute at plan time |
> | **STABLE** | constant **within a single statement**, may differ **between** statements | `now()`, `current_setting('app.tenant_id')` | yes within the query — evaluated once, result usable as an index key |
> | **VOLATILE** | may return a different value **on every call**, even within one statement | `random()`, `nextval()` | no — must be called per row; defeats index use |
>
> The easy way to tell IMMUTABLE from STABLE: ask *"could the answer change over
> time for the same arguments?"* `lower('X')` never changes → **IMMUTABLE**.
> `now()` changes as time passes (just not mid-statement) → **STABLE**. Verified:
> `SELECT now() = now()` is **true** (one statement, one value), but a `now()` run a
> moment later returns a different timestamp — stable *within*, varying *across*.
> `lower('HeLLo')` returns `hello` every time, always.
>
> For an RLS policy, **STABLE is enough** (and is what `current_setting`-based
> tenant predicates are) — the policy is evaluated once per statement and the value
> drives the index. A **VOLATILE** function in a policy is the trap from the Seq
> Scan above: the planner must re-call it for every row. Check any function's class
> with `\df+ funcname` or `SELECT provolatile FROM pg_proc WHERE proname='…'`
> (`i`/`s`/`v`).

---

## 5. Pitfalls to watch for

1. **Testing as superuser/owner** (see §3). The most common "RLS isn't filtering"
   report. Test as the real app role.
2. **Forgetting `FORCE` when the app connects as the table owner.** Owner bypasses by
   default; your policies silently do nothing.
3. **GUC leakage across a connection pool — always use `SET LOCAL`, never plain
   `SET`.** This is the rule, stated plainly: if your policy reads
   `current_setting('app.tenant_id')`, set that value with **`SET LOCAL`** (or
   `set_config('app.tenant_id', …, true)`) inside each request's transaction —
   **not** session-level `SET`.

   Why it matters: a pooled connection is reused across many tenants. Plain `SET`
   persists for the whole *database session* (the physical connection), so it
   survives the request and leaks into whoever grabs that connection next — RLS then
   serves the **previous tenant's rows** to the new one. `SET LOCAL` is scoped to the
   transaction and PostgreSQL **auto-resets it at COMMIT/ROLLBACK**, so the
   connection always returns to the pool clean. Verified on PG 18.6: after
   `BEGIN; SET app.tenant_id='A'; COMMIT`, the *next* transaction in the same session
   still read `A` (the leak); with `SET LOCAL` the value was gone the moment the
   transaction ended.

   Practical pattern — one transaction per request:
   ```sql
   BEGIN;
   SET LOCAL app.tenant_id = '42';   -- or: SELECT set_config('app.tenant_id','42',true);
   -- ... queries; RLS now filters to tenant 42 ...
   COMMIT;                            -- app.tenant_id auto-resets here
   ```
   `SET LOCAL` only works inside a transaction (outside one it's a no-op with a
   warning) — which is fine, since wrapping each request in a transaction is exactly
   the discipline that makes this safe. Session-level `SET` is acceptable **only** on
   a dedicated, non-pooled connection; on any pool, treat plain `SET` for tenant
   context as a correctness-*and*-security bug. The safest rule is to never use
   session `SET` for tenant context at all, so there is no stale session value to
   leak.
4. **`WITH CHECK` omitted on writes.** With only `USING`, an `UPDATE` can move a row
   *out* of your visibility (e.g. change its `tenant_id`), or an `INSERT` can create
   rows you then can't see. Add `WITH CHECK` (often identical to `USING`) to pin
   writes inside the boundary.
5. **Permissive vs restrictive confusion.** Multiple policies OR together by default,
   so adding a second policy *widens* access. If you mean "must satisfy *both*,"
   declare them `AS RESTRICTIVE`.
6. **Policies don't cover everything.** `COPY TO`, some maintenance paths, and
   references via foreign keys can expose row existence; and RLS filters rows, not
   **columns** (use column privileges / views for that). Treat RLS as row-visibility,
   layered with GRANTs and views — not a complete security model by itself.
7. **Non-inlinable predicate functions** tank performance (see §4). Keep policy
   expressions sargable and `STABLE`.
8. **Index the policy columns.** An unindexed policy predicate turns every query into
   a scan — the overhead isn't RLS itself, it's the missing index on the column RLS
   filters.

---

## 6. When to use RLS (and when not)

**Good fit:**
- Multi-tenant SaaS where one schema serves many tenants and you want the isolation
  enforced in the database, below the app.
- Per-user/per-group record ownership, defense-in-depth behind application checks.
- Compliance settings that require the data store itself to enforce separation.

**Reconsider when:**
- A **single tenant per database/schema** already isolates data (simpler; no policy
  overhead or GUC plumbing).
- The filter isn't indexable or the policy must be complex/procedural — the per-row
  cost may outweigh the benefit; consider views or app-tier enforcement.
- You need **column**-level or aggregate-level restrictions — use column privileges,
  views, or masking instead.

RLS is a precise, powerful tool for row isolation with near-zero overhead when the
predicate is indexable — but it's defense *in depth*, correct only for non-bypassing
roles, and only as fast as the index behind its predicate.

---

## Summary

1. RLS filters **rows** via policies folded into every query's `WHERE`/`WITH CHECK`;
   enable it per table, then add `USING` (visibility) and `WITH CHECK` (writes).
2. It **complements GRANTs** — role still needs table privileges *and* must satisfy
   the policy; no policy + RLS on = deny-all.
3. **Bypassers:** superusers always; the table owner by default (use `FORCE`);
   `BYPASSRLS` roles always. Never test or run the app as these.
4. **Overhead is near-zero for a sargable predicate on an indexed column** — plans
   identically to a hand-written filter (verified). It explodes only with
   **VOLATILE/PL-pgSQL policy functions** (per-row, index lost) — keep predicates
   `STABLE`/inlinable and indexed.
5. Watch the pitfalls: superuser/owner testing, missing `FORCE`, **GUC leakage over
   pooled connections** (use `SET LOCAL`), missing `WITH CHECK`, permissive-vs-
   restrictive, and unindexed policy columns.
