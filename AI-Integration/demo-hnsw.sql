-- demo-hnsw.sql
-- Runnable HNSW demo: build the index, show it serves a KNN query, and measure
-- recall@10 vs exact at different ef_search settings.
--
-- Verified on PostgreSQL 18.6 + pgvector 0.8.7. Self-contained and self-cleaning.
-- Run:  psql -d ai_demo -f demo-hnsw.sql     (any db with the vector extension)
--
-- See AI-Integration/pgvector-hnsw.md for the explanation.

-- NOTE: data is randomly generated, so exact recall numbers vary per run.
-- The *pattern* is what matters: HNSW reaches full recall at low ef_search.
\set ON_ERROR_STOP on
CREATE EXTENSION IF NOT EXISTS vector;

DROP TABLE IF EXISTS hnsw_demo, hnsw_truth;

-- 20k clustered 8-dim vectors (5 clusters) so nearest neighbours are well-defined
CREATE TABLE hnsw_demo (id bigserial PRIMARY KEY, embedding vector(8));
INSERT INTO hnsw_demo (embedding)
SELECT ('[' || array_to_string(
         array(SELECT round((((g % 5) + random()*0.1))::numeric, 4)
               FROM generate_series(1, 8)), ',') || ']')::vector
FROM generate_series(1, 20000) g;

-- a fixed query vector near cluster 0
\set q '[0.02,0.02,0.02,0.02,0.02,0.02,0.02,0.02]'

-- ground truth: exact top-10 with indexing disabled
SET enable_indexscan = off;
CREATE TABLE hnsw_truth AS
SELECT id FROM hnsw_demo ORDER BY embedding <=> :'q'::vector LIMIT 10;
RESET enable_indexscan;

-- build the HNSW index (cosine)
CREATE INDEX idx_hnsw_demo ON hnsw_demo USING hnsw (embedding vector_cosine_ops)
  WITH (m = 16, ef_construction = 64);
ANALYZE hnsw_demo;

\echo '=== the KNN query uses the HNSW index ==='
EXPLAIN (COSTS OFF)
SELECT id FROM hnsw_demo ORDER BY embedding <=> :'q'::vector LIMIT 5;

\echo '=== recall@10 vs exact, at increasing ef_search ==='
SET hnsw.ef_search = 10;
SELECT 10 AS ef_search, count(*) AS recall_at_10
FROM (SELECT id FROM hnsw_demo ORDER BY embedding <=> :'q'::vector LIMIT 10) r
JOIN hnsw_truth USING (id);
SET hnsw.ef_search = 40;
SELECT 40 AS ef_search, count(*) AS recall_at_10
FROM (SELECT id FROM hnsw_demo ORDER BY embedding <=> :'q'::vector LIMIT 10) r
JOIN hnsw_truth USING (id);
SET hnsw.ef_search = 100;
SELECT 100 AS ef_search, count(*) AS recall_at_10
FROM (SELECT id FROM hnsw_demo ORDER BY embedding <=> :'q'::vector LIMIT 10) r
JOIN hnsw_truth USING (id);
RESET hnsw.ef_search;

DROP TABLE hnsw_demo, hnsw_truth;
