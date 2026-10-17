-- multi-language-fts.sql
-- Multi-language full-text search: ONE table, one row per (product, language),
-- with a regconfig column that drives a per-row generated tsvector.
--
-- Verified on PostgreSQL 18.6. Run with:  psql -X -f multi-language-fts.sql
--
-- Key point: to_tsvector(regconfig, text) is IMMUTABLE even when the regconfig
-- comes from a *column*, so each row can be stemmed with its own language's
-- configuration inside a STORED generated column.

\set ON_ERROR_STOP on

DROP TABLE IF EXISTS product_translation, product CASCADE;

CREATE TABLE product (
    id    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sku   text NOT NULL
);

------------------------------------------------------------------------------
-- One row per (product, language). The language is data (lang + ts_config),
-- not schema: adding a new language is an INSERT, never DDL.
------------------------------------------------------------------------------
CREATE TABLE product_translation (
    product_id bigint    NOT NULL REFERENCES product(id),
    lang       text      NOT NULL,          -- human label: 'en','fr','de'
    ts_config  regconfig NOT NULL,          -- search config: 'english','french','german'
    label      text,
    body       text,
    search_tsv tsvector GENERATED ALWAYS AS (
        setweight(to_tsvector(ts_config, coalesce(label,'')),'A') ||
        setweight(to_tsvector(ts_config, coalesce(body ,'')),'B')
    ) STORED,
    PRIMARY KEY (product_id, lang)
);

-- A single GIN index covers every language; each row carries its own config.
CREATE INDEX idx_pt_fts ON product_translation USING gin (search_tsv);

------------------------------------------------------------------------------
-- Seed data: the same product described in three languages.
------------------------------------------------------------------------------
INSERT INTO product (sku) VALUES ('RUN-001');

INSERT INTO product_translation (product_id, lang, ts_config, label, body) VALUES
(1,'en','english','Running shoes',       'Lightweight running shoes for athletes'),
(1,'fr','french', 'Chaussures de course','Chaussures de course légères pour athlètes'),
(1,'de','german', 'Laufschuhe',          'Leichte Laufschuhe für Sportler');

------------------------------------------------------------------------------
-- Each row is stemmed with ITS OWN language: 'running'->'run' (en),
-- 'légères'->'léger' (fr), 'Laufschuhe'->'laufschuh' (de).
------------------------------------------------------------------------------
\echo '=== stored vectors (per-language stemming) ==='
SELECT lang, search_tsv FROM product_translation WHERE product_id = 1 ORDER BY lang;

------------------------------------------------------------------------------
-- Query the user's language only: filter by lang, build the tsquery with the
-- matching config. Here: a French search for the stem of "courses".
------------------------------------------------------------------------------
\echo '=== search in French ==='
SELECT pt.product_id, p.sku,
       ts_rank(pt.search_tsv, q) AS rank
FROM product_translation pt
JOIN product p ON p.id = pt.product_id,
     websearch_to_tsquery('french','courses') AS q
WHERE pt.lang = 'fr'
  AND pt.search_tsv @@ q
ORDER BY rank DESC;

\echo '=== same stem would NOT match the English row (different stemming) ==='
SELECT lang,
       search_tsv @@ websearch_to_tsquery('french','courses') AS matches_fr_query
FROM product_translation
WHERE product_id = 1
ORDER BY lang;

------------------------------------------------------------------------------
-- Adding a 4th language is just data - no ALTER TABLE, no new table.
------------------------------------------------------------------------------
\echo '=== add Spanish with a plain INSERT (no DDL) ==='
INSERT INTO product_translation (product_id, lang, ts_config, label, body) VALUES
(1,'es','spanish','Zapatillas de correr','Zapatillas de correr ligeras para atletas');
SELECT lang, search_tsv FROM product_translation WHERE lang = 'es';

-- cleanup
DROP TABLE IF EXISTS product_translation, product CASCADE;
