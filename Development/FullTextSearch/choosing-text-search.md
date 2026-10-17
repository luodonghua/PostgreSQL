# Choosing a Text-Search Approach: `LIKE`, Regex, `tsvector`, or `pg_trgm`

PostgreSQL offers four ways to search text, and they solve *different* problems.
Picking the wrong one means either poor performance or wrong results. This guide
compares them and gives a decision procedure. All performance claims were
verified on **PostgreSQL 18.6**.

Deep dives: [full-text-search.md](full-text-search.md) (tsvector) and
[trigram-fuzzy-search.md](trigram-fuzzy-search.md) (pg_trgm).

---

## The four approaches at a glance

| | `LIKE` / `ILIKE` | Regex (`~`, `~*`) | `tsvector` (FTS) | `pg_trgm` (trigram) |
|---|---|---|---|---|
| **Matches on** | literal substring with `%`/`_` wildcards | character pattern | whole words / lexemes (stemmed) | 3-char fragments |
| **Primary use** | simple pattern match | complex pattern match | word-based FTS, ranked relevance | fuzzy match, similarity |
| **Typo tolerant** | no | no | no | **yes** |
| **Language-aware** (stemming, stop words) | no | no | **yes** | no |
| **Ranking** | no | no | relevance (`ts_rank`) | similarity (`<->`) |
| **Phrase / boolean** | no | partial | **yes** (`& \| ! <->`) | no |
| **Index** | B-tree (prefix only) | limited | GIN / GiST | GIN / GiST |
| **Scales to large tables** | prefix only | poorly | **yes** | **yes** |

---

## When to use each

### `LIKE` / `ILIKE` — simple, precise pattern matching
Use for exact substring/wildcard matching, **especially prefix matches** where a
B-tree index applies. Good when you want literal matching and no stemming or
fuzziness.

- *Good:* `email LIKE 'admin%'`, `code LIKE 'SKU-2024-%'`, filtering by a known
  prefix or exact fragment.
- *Watch out:* a **leading wildcard** (`'%foo'`) cannot use a normal B-tree.

Verified — prefix `LIKE` uses the B-tree, leading-wildcard falls back to a seq
scan on 200k rows:

```sql
CREATE INDEX idx_t_email ON t(email text_pattern_ops);

-- prefix: B-tree range scan, 0.29 ms
EXPLAIN (ANALYZE) SELECT count(*) FROM t WHERE email LIKE 'user123%';
--  Bitmap Index Scan on idx_t_email
--    Index Cond: ((email ~>=~ 'user123') AND (email ~<~ 'user124'))

-- leading wildcard: parallel seq scan, 18.6 ms
EXPLAIN (ANALYZE) SELECT count(*) FROM t WHERE email LIKE '%@example.com';
--  Parallel Seq Scan on t   Filter: (email ~~ '%@example.com')
```

> For case-insensitive or middle-of-string `LIKE`/`ILIKE` on large tables, add a
> **`gin_trgm_ops` trigram index** — it accelerates leading-wildcard and `ILIKE`
> searches that a B-tree cannot (see [trigram-fuzzy-search.md](trigram-fuzzy-search.md)).

### Regular expressions (`~`, `~*`) — complex pattern matching
Use when the pattern itself is structured — extracting or validating formats
during data cleansing (URLs, phone numbers, codes). Most flexible, but indexing
support is limited (a trigram GIN can help some patterns; many regexes still scan).

- *Good:* `body ~ 'https?://[^ ]+'`, validating/finding structured tokens.
- *Watch out:* expensive on large tables; treat as a data-processing tool, not a
  hot-path search.

### `tsvector` (full-text search) — word-based, ranked, language-aware
Use to search **document contents** by words, with stemming (`running`→`run`),
stop-word removal, phrase/boolean queries, and **relevance ranking**. The
standard choice for searching blogs, articles, descriptions, comments.

- *Good:* "find articles about `postgresql & performance`, ranked by relevance",
  multi-field weighted search (title > body).
- *Requires correct spelling* — a typo returns nothing (pair with pg_trgm for a
  did-you-mean fallback).
- Index with GIN; query with `@@`. See [full-text-search.md](full-text-search.md).

### `pg_trgm` (trigrams) — fuzzy matching and similarity
Use when input may be **misspelled** or you want "similar to" rather than "equal
to": typo-tolerant search on names/brands/SKUs, deduplicating dirty data,
type-ahead that survives mistakes, and accelerating `ILIKE`/leading-wildcard.

- *Good:* "user typed `Uniclo`, find `Uniqlo`", fuzzy address/name matching,
  `ORDER BY name <-> 'typo'` for closest matches.
- *Not* language-aware and *no* phrase/boolean logic. See
  [trigram-fuzzy-search.md](trigram-fuzzy-search.md).

---

## Decision procedure

```
Is the query a structured pattern (format extraction/validation)?
  └─ yes → Regular expression

Do you need typo tolerance / "similar to" matching?
  └─ yes → pg_trgm (trigram)

Are you searching word-based document content, wanting stemming + ranking?
  └─ yes → tsvector (full-text search)

Is it a simple literal match, especially a prefix?
  └─ yes → LIKE / ILIKE (B-tree for prefixes; add gin_trgm_ops for %middle% / ILIKE)
```

Concretely:

| Goal | Use |
|------|-----|
| Filter emails by domain/name prefix | `LIKE` + B-tree |
| Find URLs / validate formats in text | regex |
| Search article bodies, ranked by relevance, with stemming | `tsvector` |
| Find a product/brand despite a typo; type-ahead | `pg_trgm` |
| Case-insensitive `%substring%` on a big table | `pg_trgm` GIN index |

---

## They combine well

These are not mutually exclusive — strong designs layer them:

- **FTS + trigram fallback:** run `tsvector @@ tsquery`; if it returns nothing,
  retry with a `pg_trgm` similarity search as a "did you mean…?" path. FTS gives
  ranked word search; trigrams rescue the misspellings FTS can't handle.
- **FTS + scalar filter:** combine `@@` with ordinary `WHERE price < 50`; the
  planner can intersect a GIN FTS index with a B-tree via `BitmapAnd`
  (see [full-text-search.md](full-text-search.md), §9).
- **`LIKE` + trigram index:** keep writing `ILIKE '%term%'` but add a
  `gin_trgm_ops` index so it stops being a seq scan.

---

## Summary

- **`LIKE`** — literal patterns; fast only for prefixes (B-tree). Add a trigram
  index for `ILIKE`/middle-of-string.
- **Regex** — complex structured patterns; a data-cleansing tool, limited
  indexing.
- **`tsvector`** — word-based, stemmed, ranked full-text search of document
  content; needs correct spelling.
- **`pg_trgm`** — character-trigram fuzzy matching and similarity; typo-tolerant,
  not language-aware.

Rule of thumb: **search *content* by words → `tsvector`; match *values* fuzzily
→ `pg_trgm`; match a known literal/prefix → `LIKE`; parse a structure → regex.**
