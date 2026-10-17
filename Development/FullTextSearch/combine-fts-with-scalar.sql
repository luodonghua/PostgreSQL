-- combine-fts-with-scalar.sql
-- Reproduces how PostgreSQL's planner combines a full-text (GIN) index with a
-- scalar B-tree index, and contrasts single-table (BitmapAnd) vs multi-table
-- (join) behavior.
--
-- Verified on PostgreSQL 18.6. Run with:  psql -X -f combine-fts-with-scalar.sql
-- Each EXPLAIN uses ANALYZE so you see the *actual* chosen plan.

\set ON_ERROR_STOP on

DROP TABLE IF EXISTS product_variant_price, product_variant, product CASCADE;

------------------------------------------------------------------------------
-- Schema: a product with a weighted, stored tsvector generated column,
-- plus a plain price column and a B-tree on it.
------------------------------------------------------------------------------
CREATE TABLE product (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    label        text NOT NULL,
    description  text,
    price        numeric(10,2),
    infotext_tsv tsvector GENERATED ALWAYS AS (
        setweight(to_tsvector('english', coalesce(label,'')),      'A') ||
        setweight(to_tsvector('english', coalesce(description,'')),'B')
    ) STORED
);

-- 200k rows so the planner's cost model actually prefers indexes.
INSERT INTO product (label, description, price)
SELECT
  CASE WHEN g % 50 = 0 THEN 'Edgy Cool T-Shirt '||g
       WHEN g % 30 = 0 THEN 'Classic Oxford Shirt '||g
       ELSE 'Generic Mug '||g END,
  CASE WHEN g % 50 = 0 THEN 'An edgy and cool shirt for modern wardrobes'
       WHEN g % 30 = 0 THEN 'A cool button-down oxford shirt'
       ELSE 'plain ceramic item' END,
  (g % 200)::numeric
FROM generate_series(1,200000) g;

CREATE INDEX idx_prod_fts   ON product USING gin  (infotext_tsv);
CREATE INDEX idx_prod_price ON product USING btree(price);
ANALYZE product;

------------------------------------------------------------------------------
-- CASE 1: FTS predicate is far more selective than price.
-- Planner uses ONLY the GIN index; price becomes a post-scan Filter.
------------------------------------------------------------------------------
\echo '=== CASE 1: FTS selective -> single GIN index + price Filter ==='
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF)
SELECT id, label
FROM product
WHERE infotext_tsv @@ websearch_to_tsquery('english','edgy and cool shirt or t-shirt')
  AND price < 50;

------------------------------------------------------------------------------
-- CASE 2: both predicates individually selective on the SAME table.
-- Planner intersects two bitmaps with BitmapAnd (GIN + B-tree).
------------------------------------------------------------------------------
\echo '=== CASE 2: both selective -> BitmapAnd(GIN, B-tree) ==='
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF)
SELECT id, label
FROM product
WHERE infotext_tsv @@ websearch_to_tsquery('english','shirt')
  AND price < 3;

------------------------------------------------------------------------------
-- CASE 3: the book's shape - predicates live on DIFFERENT tables.
-- BitmapAnd cannot span tables; each table is scanned separately and joined.
------------------------------------------------------------------------------
CREATE TABLE product_variant (
    id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id bigint NOT NULL REFERENCES product(id)
);
CREATE TABLE product_variant_price (
    id                 bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_variant_id bigint NOT NULL REFERENCES product_variant(id),
    price              numeric(10,2)
);
INSERT INTO product_variant (product_id) SELECT id FROM product;
INSERT INTO product_variant_price (product_variant_id, price)
SELECT pv.id, (pv.id % 200)::numeric FROM product_variant pv;
CREATE INDEX idx_pv_product  ON product_variant(product_id);
CREATE INDEX idx_pvp_variant ON product_variant_price(product_variant_id);
CREATE INDEX idx_pvp_price    ON product_variant_price(price);
ANALYZE product_variant, product_variant_price;

\echo '=== CASE 3: FTS on product, price on another table -> join, no BitmapAnd ==='
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF)
SELECT p.id, p.label,
       FORMAT('%s-%s', MIN(pvp.price), MAX(pvp.price)) AS price_range
FROM product p
JOIN product_variant pv        ON p.id  = pv.product_id
JOIN product_variant_price pvp ON pv.id = pvp.product_variant_id
WHERE p.infotext_tsv @@ websearch_to_tsquery('english','edgy and cool shirt or t-shirt')
  AND pvp.price < 50
GROUP BY p.id, p.label
ORDER BY MAX(pvp.price) DESC;

-- cleanup
DROP TABLE IF EXISTS product_variant_price, product_variant, product CASCADE;
