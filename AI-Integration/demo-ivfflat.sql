-- demo-ivfflat.sql
-- Runnable IVFFlat demo: build the index (after loading data), show it serves a
-- KNN query, and measure recall@10 vs exact at different probes settings —
-- including the default probes=1 that is often too low.
--
-- Verified on PostgreSQL 18.6 + pgvector 0.8.7. Self-contained and self-cleaning.
-- Run:  psql -d ai_demo -f demo-ivfflat.sql    (any db with the vector extension)
--
-- See AI-Integration/pgvector-ivfflat.md for the explanation.

-- NOTE: data is randomly generated, so exact recall numbers vary per run.
-- The *pattern* is what matters: probes=1 (default) can miss true neighbours;
-- raising probes recovers recall. Re-run a few times to see the trend.
\set ON_ERROR_STOP on
CREATE EXTENSION IF NOT EXISTS vector;

DROP TABLE IF EXISTS ivf_demo, ivf_truth;

-- 20k clustered 8-dim vectors (5 clusters) so nearest neighbours are well-defined
CREATE TABLE ivf_demo (id bigserial PRIMARY KEY, embedding vector(8));
INSERT INTO ivf_demo (embedding)
SELECT ('[' || array_to_string(
         array(SELECT round((((g % 5) + random()*0.1))::numeric, 4)
               FROM generate_series(1, 8)), ',') || ']')::vector
FROM generate_series(1, 20000) g;

\set q '[0.02,0.02,0.02,0.02,0.02,0.02,0.02,0.02]'

-- ground truth: exact top-10 with indexing disabled
SET enable_indexscan = off;
CREATE TABLE ivf_truth AS
SELECT id FROM ivf_demo ORDER BY embedding <=> :'q'::vector LIMIT 10;
RESET enable_indexscan;

-- IVFFlat MUST be built after data exists (k-means needs the rows).
-- 20k rows -> lists ~ rows/1000 ~ 20; use 100 here to show probes effect clearly.
CREATE INDEX idx_ivf_demo ON ivf_demo USING ivfflat (embedding vector_cosine_ops)
  WITH (lists = 100);
ANALYZE ivf_demo;

\echo '=== the KNN query uses the IVFFlat index ==='
EXPLAIN (COSTS OFF)
SELECT id FROM ivf_demo ORDER BY embedding <=> :'q'::vector LIMIT 5;

\echo '=== recall@10 vs exact, at increasing probes (watch the default probes=1) ==='
SET ivfflat.probes = 1;     -- default
SELECT 1 AS probes, count(*) AS recall_at_10
FROM (SELECT id FROM ivf_demo ORDER BY embedding <=> :'q'::vector LIMIT 10) r
JOIN ivf_truth USING (id);
SET ivfflat.probes = 5;
SELECT 5 AS probes, count(*) AS recall_at_10
FROM (SELECT id FROM ivf_demo ORDER BY embedding <=> :'q'::vector LIMIT 10) r
JOIN ivf_truth USING (id);
SET ivfflat.probes = 20;
SELECT 20 AS probes, count(*) AS recall_at_10
FROM (SELECT id FROM ivf_demo ORDER BY embedding <=> :'q'::vector LIMIT 10) r
JOIN ivf_truth USING (id);
RESET ivfflat.probes;

DROP TABLE ivf_demo, ivf_truth;
