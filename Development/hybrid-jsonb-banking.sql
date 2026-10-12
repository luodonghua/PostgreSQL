-- =============================================================================
-- Hybrid JSONB + relational design (banking example)   PostgreSQL 18
-- =============================================================================
-- PRINCIPLE
--   PostgreSQL cannot update a JSONB document in place. Changing one key
--   produces a brand-new JSONB value, and MVCC writes a brand-new copy of the
--   WHOLE row. That new tuple is WAL-logged in full. So the WAL (and bloat)
--   cost of an UPDATE is driven by the size of the ENTIRE row being rewritten,
--   not by how many bytes you "changed".
--
--   Therefore the hot, high-frequency field (account balance) must not share a
--   row with a large, rarely-changed JSONB blob (customer profile / KYC).
--
-- GOOD DESIGN
--   accounts            -> stable identity + big JSONB profile (rarely updated)
--   account_balances    -> narrow row: balance, status, updated_at (hot path)
--   One account : one balance row, linked by account_id.
--
-- BAD DESIGN (for contrast)
--   accounts_jsonb_only -> balance + status live INSIDE the big JSONB doc,
--                          so every debit/credit rewrites the whole ~1 KB blob.
-- =============================================================================

DROP TABLE IF EXISTS account_balances;
DROP TABLE IF EXISTS accounts;
DROP TABLE IF EXISTS accounts_jsonb_only;

-- -----------------------------------------------------------------------------
-- GOOD DESIGN
-- -----------------------------------------------------------------------------
CREATE TABLE accounts (
    account_id  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    account_no  text  NOT NULL UNIQUE,
    profile     jsonb NOT NULL           -- large, stable: customer / KYC / prefs
);
CREATE INDEX idx_accounts_profile ON accounts USING gin (profile);

-- Narrow, hot table. Rows here are tiny, so each UPDATE rewrites few bytes
-- and WAL-logs little. The big profile blob is never touched.
CREATE TABLE account_balances (
    account_id  bigint PRIMARY KEY REFERENCES accounts(account_id),
    balance     numeric(18,2) NOT NULL DEFAULT 0,
    status      text          NOT NULL DEFAULT 'ACTIVE',
    updated_at  timestamptz   NOT NULL DEFAULT now()
);

-- -----------------------------------------------------------------------------
-- BAD DESIGN: balance buried inside a large JSONB document
-- -----------------------------------------------------------------------------
CREATE TABLE accounts_jsonb_only (
    account_id  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    account_no  text  NOT NULL UNIQUE,
    doc         jsonb NOT NULL           -- balance + status + profile ALL here
);

-- -----------------------------------------------------------------------------
-- Seed identical logical data. Profile blob is deliberately ~1 KB.
-- -----------------------------------------------------------------------------
INSERT INTO accounts (account_no, profile)
SELECT
    'ACC' || lpad(g::text, 8, '0'),
    jsonb_build_object(
        'customer', jsonb_build_object(
            'name',  'Customer ' || g,
            'dob',   '1980-01-01',
            'email', 'customer' || g || '@example.com',
            'phone', '+65-9000-' || lpad(g::text, 4, '0')
        ),
        'kyc', jsonb_build_object(
            'id_type','PASSPORT',
            'id_number','P' || lpad(g::text, 9, '0'),
            'verified', true,
            'documents', jsonb_build_array(
                jsonb_build_object('type','passport_scan','hash', md5(g::text)),
                jsonb_build_object('type','proof_of_address','hash', md5((g+1)::text))
            )
        ),
        'preferences', jsonb_build_object(
            'language','en','statements','email','marketing_opt_in', (g % 2 = 0)
        ),
        'notes', repeat('x', 500)
    )
FROM generate_series(1, 5000) AS g;

INSERT INTO account_balances (account_id, balance, status)
SELECT account_id, 1000.00, 'ACTIVE' FROM accounts;

INSERT INTO accounts_jsonb_only (account_no, doc)
SELECT a.account_no,
       a.profile || jsonb_build_object('balance', 1000.00, 'status', 'ACTIVE')
FROM accounts a;

ANALYZE accounts;
ANALYZE account_balances;
ANALYZE accounts_jsonb_only;
