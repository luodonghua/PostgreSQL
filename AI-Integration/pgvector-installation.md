# Installing pgvector

`pgvector` is the open-source PostgreSQL extension that adds a `vector` data type
and vector similarity search (L2, cosine, inner product) with ANN indexing
(HNSW, IVFFlat). It is the foundation for embeddings storage and
retrieval-augmented generation (RAG) on PostgreSQL.

**Upstream project (authoritative source for all install methods and docs):**
<https://github.com/pgvector/pgvector>

> **Why read the upstream page too?** pgvector is *not* bundled with core
> PostgreSQL, so how you install it depends entirely on **your OS platform and
> how PostgreSQL was installed** (distro packages, source build, Docker, or a
> managed cloud service). The steps below are what was used and verified in this
> repo's environment; they will differ on other platforms. For anything that
> doesn't match your setup, follow the upstream README.

---

## Environment used here (verified)

These exact steps were run and verified on:

| | |
|---|---|
| OS | Linux Mint 22.3 (Ubuntu 24.04 "noble" base) |
| PostgreSQL | 18.6 (from the PGDG apt repository) |
| pgvector | 0.8.7 (`postgresql-18-pgvector` package) |
| Architecture | x86_64 |

If your OS, PostgreSQL major version, or install source differs, see
[Other platforms](#other-platforms) and
[Managed PostgreSQL services](#managed-postgresql-services) below.

---

## Install on Debian/Ubuntu (PGDG apt repo)

Because this server's PostgreSQL 18 came from the PostgreSQL Global Development
Group (PGDG) apt repository, pgvector is available there as a prebuilt package.
**The package name is version-specific: `postgresql-<PGMAJOR>-pgvector`.**

```bash
# 1. Confirm your PostgreSQL major version
psql -tAc "SHOW server_version"        # e.g. 18.6  -> major 18

# 2. Install the matching pgvector package (adjust 18 to your major version)
sudo apt-get update
sudo apt-get install -y postgresql-18-pgvector
```

This installs the `vector.control` file and SQL scripts under
`/usr/share/postgresql/18/extension/` and the compiled `vector.so` into the
server's library directory. No server restart is required — the extension is
loaded on demand when you run `CREATE EXTENSION`.

> If the package can't be found, your PostgreSQL likely didn't come from PGDG.
> Add the PGDG repo (see upstream / PostgreSQL apt docs) or build from source.

---

## Enable the extension in a database

The OS package only makes pgvector *available*; you must enable it **per
database**. Here we create a dedicated database and enable it:

```sql
CREATE DATABASE ai_demo;
\c ai_demo
CREATE EXTENSION IF NOT EXISTS vector;
```

Note the extension is named **`vector`** (the project is "pgvector", the
extension is `vector`).

Verify:

```sql
SELECT extname, extversion FROM pg_extension WHERE extname = 'vector';
--  extname | extversion
--  vector  | 0.8.7
```

---

## Smoke test

Confirm the type, an insert, and a distance query work end to end:

```sql
CREATE TABLE items (id bigserial PRIMARY KEY, embedding vector(3));

INSERT INTO items (embedding) VALUES ('[1,2,3]'), ('[4,5,6]'), ('[1,1,1]');

-- order rows by L2 distance to a query vector
SELECT id, embedding, embedding <-> '[1,2,3]' AS l2_distance
FROM items
ORDER BY embedding <-> '[1,2,3]';
```
```
 id | embedding |    l2_distance
----+-----------+-------------------
  1 | [1,2,3]   |                 0
  3 | [1,1,1]   |  2.23606797749979
  2 | [4,5,6]   | 5.196152422706632
```

The three distance operators:

| Operator | Distance | Typical use |
|----------|----------|-------------|
| `<->` | L2 (Euclidean) | general similarity |
| `<=>` | cosine distance | normalized embeddings (most LLM embeddings) |
| `<#>` | negative inner product | maximum inner-product search |

(Clean up the smoke-test table with `DROP TABLE items;` when done.)

---

## Upgrading pgvector

The package ships the upgrade-path scripts (`vector--0.8.6--0.8.7.sql`, etc.),
so after installing a newer OS package you bump the in-database version with:

```sql
ALTER EXTENSION vector UPDATE;                 -- to the newest installed version
-- or target a specific version:
ALTER EXTENSION vector UPDATE TO '0.8.7';
```

---

## Other platforms

pgvector supports many install paths; pick the one matching your setup (full
matrix on the [upstream README](https://github.com/pgvector/pgvector)):

- **RHEL / Rocky / Alma (PGDG yum):** `sudo dnf install pgvector_18`
  (package name uses the PG major version).
- **macOS (Homebrew PostgreSQL):** `brew install pgvector`.
- **Build from source** (any platform with the PG dev headers):
  ```bash
  git clone --branch v0.8.7 https://github.com/pgvector/pgvector.git
  cd pgvector
  make                 # needs pg_config on PATH (e.g. postgresql-server-dev-18)
  sudo make install
  ```
- **Docker:** use the official `pgvector/pgvector:pg18` image, or add pgvector to
  your own image via the source build above.
- **Windows:** build with MSVC per the upstream instructions.

In every case the package/build must match your **PostgreSQL major version** and
architecture.

---

## Managed PostgreSQL services

On managed services you usually **cannot install OS packages** — pgvector must be
offered by the provider, and you just run `CREATE EXTENSION vector;` (sometimes
after allow-listing it). Availability and minimum versions vary, so check the
provider's current docs:

- **Amazon RDS / Aurora PostgreSQL** — pgvector is supported on recent engine
  versions; enable with `CREATE EXTENSION vector;` (it is on the allowed
  extensions list). Confirm your engine version meets the minimum in the AWS
  docs.
- **Google Cloud SQL / AlloyDB** — pgvector is available; AlloyDB adds its own
  ScaNN index. Enable per the GCP docs.
- **Azure Database for PostgreSQL (Flexible Server)** — allow-list `vector` in
  server parameters (`azure.extensions`), then `CREATE EXTENSION vector;`.
- **Other providers (Supabase, Neon, Timescale, etc.)** — pgvector is widely
  pre-installed; enable with `CREATE EXTENSION vector;`.

Because support changes over time and differs per provider/version, treat the
provider's documentation and the
[upstream pgvector page](https://github.com/pgvector/pgvector) as the source of
truth; the apt steps above apply only to self-managed Debian/Ubuntu servers.

---

## Summary

1. pgvector is a separate extension — install the **server package matching your
   PostgreSQL major version** (`postgresql-18-pgvector` here), or use your
   platform's method / your managed provider's support.
2. Enable it **per database**: `CREATE EXTENSION vector;` (extension name is
   `vector`).
3. Verify with `pg_extension`, smoke-test with a `vector` column and a `<->`
   query.
4. For any environment that differs from this one (other OS, PG version, Docker,
   or managed service), follow <https://github.com/pgvector/pgvector>.
