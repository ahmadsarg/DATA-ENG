-- ============================================
-- Conditions Management System Tables
-- ============================================
-- This schema supports:
-- - Supplier conditions with different types (percentage/absolute/net)
-- - Pricing attributes linked to catalog categories
-- - Many-to-many relationship between conditions and pricing attributes
-- - Drag & drop ordering via position_order column

-- ============================================
-- PostgreSQL Version
-- ============================================

-- --------------------------------------------
-- Suppliers Table (Reference Table)
-- --------------------------------------------
CREATE TABLE IF NOT EXISTS suppliers (
    id                  SERIAL PRIMARY KEY,
    name                VARCHAR(255) NOT NULL,
    code                VARCHAR(50) UNIQUE,

    -- Audit Columns
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- --------------------------------------------
-- Catalog Categories Table (Reference Table)
-- --------------------------------------------
CREATE TABLE IF NOT EXISTS catalog_categories (
    id                  SERIAL PRIMARY KEY,
    name                VARCHAR(255) NOT NULL,
    parent_id           INTEGER REFERENCES catalog_categories(id),

    -- Audit Columns
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- --------------------------------------------
-- Conditions Table (SCD Type 2)
-- --------------------------------------------
-- Stores supplier conditions with FULL HISTORY TRACKING using SCD Type 2
--
-- SCD Type 2 Implementation:
-- - condition_sk: Surrogate key (unique per row/version)
-- - condition_id: Natural key (stable business identifier across versions)
-- - record_valid_from/to: When this VERSION of the record was current
-- - is_current: TRUE only for the latest version
--
-- Supports:
-- - Different condition types (percentage, absolute, net)
-- - Cumulability modes (progressive, additive)
-- - Settlement modes (invoice, credit_note)
-- - Position ordering for drag & drop functionality
-- - FULL HISTORY of all changes to any condition
CREATE TABLE IF NOT EXISTS conditions (
    -- Surrogate Key (unique per row/version - auto-generated)
    condition_sk            SERIAL PRIMARY KEY,

    -- Natural Key (stable business identifier - same across all versions)
    condition_id            VARCHAR(50) NOT NULL,

    -- Condition Type: determines how the value is applied
    -- 'percentage': value is a percentage (e.g., 10 = 10%)
    -- 'absolute': value is a fixed amount
    -- 'net': value is a net price
    type                    VARCHAR(20) NOT NULL CHECK (type IN ('percentage', 'absolute', 'net')),

    -- Numeric value of the condition
    value                   DECIMAL(15, 4) NOT NULL,

    -- Cumulability: how conditions stack with others
    -- 'progressive': applies to the result of previous conditions
    -- 'additive': adds to other conditions
    cumulability            VARCHAR(20) NOT NULL CHECK (cumulability IN ('progressive', 'additive')),

    -- Settlement Mode: how the condition is settled
    -- 'invoice': applied directly on invoice
    -- 'credit_note': settled via credit note
    settlement_mode         VARCHAR(20) NOT NULL CHECK (settlement_mode IN ('invoice', 'credit_note')),

    -- Include in Net Price: only relevant when settlement_mode = 'credit_note'
    -- Indicates if this condition should be included in net price calculation
    include_in_net_price    BOOLEAN DEFAULT FALSE,

    -- Business Validity Period (when the condition applies to pricing)
    business_valid_from     DATE NOT NULL,
    business_valid_to       DATE,

    -- Position Order: used for drag & drop ordering in UI
    -- New conditions get max(position_order) + 1
    position_order          INTEGER NOT NULL,

    -- Foreign Key to Supplier
    supplier_id             INTEGER NOT NULL REFERENCES suppliers(id) ON DELETE CASCADE,

    -- ========================================
    -- SCD Type 2 Metadata
    -- ========================================
    -- Record validity: when this VERSION of the record was the "truth"
    record_valid_from       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    record_valid_to         TIMESTAMP DEFAULT '9999-12-31 23:59:59',

    -- Is this the current/latest version of this condition?
    is_current              BOOLEAN DEFAULT TRUE,

    -- Audit Columns
    source_system           VARCHAR(50),
    created_at              TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at              TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- --------------------------------------------
-- Pricing Attributes Table
-- --------------------------------------------
-- Stores pricing attributes that can be linked to conditions
-- Each attribute belongs to a catalog category
CREATE TABLE IF NOT EXISTS pricing_attributes (
    id                      SERIAL PRIMARY KEY,
    name                    VARCHAR(255) NOT NULL,

    -- Foreign Key to Catalog Category
    catalog_category_id     INTEGER REFERENCES catalog_categories(id) ON DELETE SET NULL,

    -- Audit Columns
    created_at              TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at              TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- --------------------------------------------
-- Condition Pricing Attributes (Junction Table)
-- --------------------------------------------
-- Many-to-many relationship between conditions and pricing attributes
-- A condition can apply to multiple pricing attributes (or none)
-- A pricing attribute can be linked to multiple conditions
--
-- NOTE: Uses condition_id (natural key) NOT condition_sk (surrogate key)
-- This ensures attribute links persist across condition versions
CREATE TABLE IF NOT EXISTS condition_pricing_attributes (
    -- Links to condition's natural key (persists across versions)
    condition_id            VARCHAR(50) NOT NULL,
    attribute_id            INTEGER NOT NULL REFERENCES pricing_attributes(id) ON DELETE CASCADE,

    -- Composite Primary Key
    PRIMARY KEY (condition_id, attribute_id),

    -- Audit Column
    created_at              TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);


-- ============================================
-- Snowflake Version (SCD Type 2)
-- ============================================
/*
CREATE TABLE IF NOT EXISTS suppliers (
    id                  INTEGER AUTOINCREMENT PRIMARY KEY,
    name                VARCHAR(255) NOT NULL,
    code                VARCHAR(50) UNIQUE,
    created_at          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    updated_at          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE TABLE IF NOT EXISTS catalog_categories (
    id                  INTEGER AUTOINCREMENT PRIMARY KEY,
    name                VARCHAR(255) NOT NULL,
    parent_id           INTEGER REFERENCES catalog_categories(id),
    created_at          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    updated_at          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE TABLE IF NOT EXISTS conditions (
    condition_sk            INTEGER AUTOINCREMENT PRIMARY KEY,
    condition_id            VARCHAR(50) NOT NULL,
    type                    VARCHAR(20) NOT NULL,
    value                   DECIMAL(15, 4) NOT NULL,
    cumulability            VARCHAR(20) NOT NULL,
    settlement_mode         VARCHAR(20) NOT NULL,
    include_in_net_price    BOOLEAN DEFAULT FALSE,
    business_valid_from     DATE NOT NULL,
    business_valid_to       DATE,
    position_order          INTEGER NOT NULL,
    supplier_id             INTEGER NOT NULL REFERENCES suppliers(id),
    record_valid_from       TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    record_valid_to         TIMESTAMP_NTZ DEFAULT '9999-12-31 23:59:59',
    is_current              BOOLEAN DEFAULT TRUE,
    source_system           VARCHAR(50),
    created_at              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    updated_at              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE TABLE IF NOT EXISTS pricing_attributes (
    id                      INTEGER AUTOINCREMENT PRIMARY KEY,
    name                    VARCHAR(255) NOT NULL,
    catalog_category_id     INTEGER REFERENCES catalog_categories(id),
    created_at              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    updated_at              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE TABLE IF NOT EXISTS condition_pricing_attributes (
    condition_id            VARCHAR(50) NOT NULL,
    attribute_id            INTEGER NOT NULL REFERENCES pricing_attributes(id),
    created_at              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (condition_id, attribute_id)
);
*/


-- ============================================
-- BigQuery Version (SCD Type 2)
-- ============================================
/*
CREATE TABLE IF NOT EXISTS `project.dataset.suppliers` (
    id                  INT64 NOT NULL,
    name                STRING NOT NULL,
    code                STRING,
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

CREATE TABLE IF NOT EXISTS `project.dataset.catalog_categories` (
    id                  INT64 NOT NULL,
    name                STRING NOT NULL,
    parent_id           INT64,
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

CREATE TABLE IF NOT EXISTS `project.dataset.conditions` (
    condition_sk            INT64 NOT NULL,
    condition_id            STRING NOT NULL,
    type                    STRING NOT NULL,
    value                   NUMERIC NOT NULL,
    cumulability            STRING NOT NULL,
    settlement_mode         STRING NOT NULL,
    include_in_net_price    BOOL DEFAULT FALSE,
    business_valid_from     DATE NOT NULL,
    business_valid_to       DATE,
    position_order          INT64 NOT NULL,
    supplier_id             INT64 NOT NULL,
    record_valid_from       TIMESTAMP NOT NULL,
    record_valid_to         TIMESTAMP DEFAULT TIMESTAMP('9999-12-31 23:59:59'),
    is_current              BOOL DEFAULT TRUE,
    source_system           STRING,
    created_at              TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    updated_at              TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

CREATE TABLE IF NOT EXISTS `project.dataset.pricing_attributes` (
    id                      INT64 NOT NULL,
    name                    STRING NOT NULL,
    catalog_category_id     INT64,
    created_at              TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    updated_at              TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

CREATE TABLE IF NOT EXISTS `project.dataset.condition_pricing_attributes` (
    condition_id            STRING NOT NULL,
    attribute_id            INT64 NOT NULL,
    created_at              TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);
*/


-- ============================================
-- Helper Queries for UI Operations
-- ============================================

-- ----------------------------------------
-- CURRENT DATA QUERIES (for normal UI use)
-- ----------------------------------------

-- Get all CURRENT conditions for a supplier ordered by position
-- SELECT c.*,
--        array_agg(pa.name) FILTER (WHERE pa.name IS NOT NULL) as pricing_attribute_names
-- FROM conditions c
-- LEFT JOIN condition_pricing_attributes cpa ON c.condition_id = cpa.condition_id
-- LEFT JOIN pricing_attributes pa ON cpa.attribute_id = pa.id
-- WHERE c.supplier_id = :supplier_id
--   AND c.is_current = TRUE
-- GROUP BY c.condition_sk
-- ORDER BY c.position_order ASC;

-- Get max position_order for a supplier (used when adding new condition)
-- SELECT COALESCE(MAX(position_order), 0) + 1 as next_position
-- FROM conditions
-- WHERE supplier_id = :supplier_id
--   AND is_current = TRUE;


-- ============================================
-- SCD TYPE 2 OPERATIONS
-- ============================================

-- ----------------------------------------
-- 1. GET ALL HISTORICAL VERSIONS OF A CONDITION
-- ----------------------------------------
-- Shows complete change history for a specific condition
-- SELECT
--     condition_sk,
--     condition_id,
--     type,
--     value,
--     cumulability,
--     settlement_mode,
--     include_in_net_price,
--     business_valid_from,
--     business_valid_to,
--     position_order,
--     record_valid_from,
--     record_valid_to,
--     is_current,
--     CASE WHEN is_current THEN 'Current Version'
--          ELSE 'Historical Version' END as version_status
-- FROM conditions
-- WHERE condition_id = :condition_id
-- ORDER BY record_valid_from DESC;

-- ----------------------------------------
-- 2. POINT-IN-TIME LOOKUP
-- ----------------------------------------
-- Get condition state as it was at a specific moment in time
-- SELECT *
-- FROM conditions
-- WHERE condition_id = :condition_id
--   AND record_valid_from <= :point_in_time
--   AND record_valid_to > :point_in_time;

-- Get ALL conditions for a supplier as they were at a specific date
-- SELECT c.*,
--        array_agg(pa.name) FILTER (WHERE pa.name IS NOT NULL) as pricing_attribute_names
-- FROM conditions c
-- LEFT JOIN condition_pricing_attributes cpa ON c.condition_id = cpa.condition_id
-- LEFT JOIN pricing_attributes pa ON cpa.attribute_id = pa.id
-- WHERE c.supplier_id = :supplier_id
--   AND c.record_valid_from <= :point_in_time
--   AND c.record_valid_to > :point_in_time
-- GROUP BY c.condition_sk
-- ORDER BY c.position_order ASC;

-- ----------------------------------------
-- 3. INSERT NEW CONDITION (SCD Type 2)
-- ----------------------------------------
-- When creating a new condition, generate a new condition_id
-- INSERT INTO conditions (
--     condition_id, type, value, cumulability, settlement_mode,
--     include_in_net_price, business_valid_from, business_valid_to,
--     position_order, supplier_id, record_valid_from, record_valid_to,
--     is_current, source_system
-- ) VALUES (
--     'COND-' || gen_random_uuid(),  -- Generate unique natural key
--     :type, :value, :cumulability, :settlement_mode,
--     :include_in_net_price, :business_valid_from, :business_valid_to,
--     (SELECT COALESCE(MAX(position_order), 0) + 1 FROM conditions WHERE supplier_id = :supplier_id AND is_current = TRUE),
--     :supplier_id, CURRENT_TIMESTAMP, '9999-12-31 23:59:59',
--     TRUE, 'UI'
-- );

-- ----------------------------------------
-- 4. UPDATE CONDITION (SCD Type 2 - creates new version)
-- ----------------------------------------
-- Step 1: Close the current version
-- UPDATE conditions
-- SET record_valid_to = CURRENT_TIMESTAMP,
--     is_current = FALSE,
--     updated_at = CURRENT_TIMESTAMP
-- WHERE condition_id = :condition_id
--   AND is_current = TRUE;

-- Step 2: Insert new version with updated values
-- INSERT INTO conditions (
--     condition_id, type, value, cumulability, settlement_mode,
--     include_in_net_price, business_valid_from, business_valid_to,
--     position_order, supplier_id, record_valid_from, record_valid_to,
--     is_current, source_system
-- )
-- SELECT
--     condition_id,
--     :new_type,           -- New value
--     :new_value,          -- New value
--     :new_cumulability,   -- New value (or keep old)
--     :new_settlement_mode,
--     :new_include_in_net_price,
--     :new_business_valid_from,
--     :new_business_valid_to,
--     position_order,      -- Keep same position
--     supplier_id,
--     CURRENT_TIMESTAMP,   -- New version starts now
--     '9999-12-31 23:59:59',
--     TRUE,
--     'UI'
-- FROM conditions
-- WHERE condition_id = :condition_id
--   AND record_valid_to = CURRENT_TIMESTAMP;  -- Just closed version

-- ----------------------------------------
-- 5. DELETE CONDITION (Soft Delete with SCD Type 2)
-- ----------------------------------------
-- Just close the current version - history is preserved
-- UPDATE conditions
-- SET record_valid_to = CURRENT_TIMESTAMP,
--     is_current = FALSE,
--     updated_at = CURRENT_TIMESTAMP
-- WHERE condition_id = :condition_id
--   AND is_current = TRUE;

-- ----------------------------------------
-- 6. COMPARE CONDITION CHANGES OVER TIME
-- ----------------------------------------
-- Show what changed between versions
-- WITH versioned AS (
--     SELECT *,
--            LAG(value) OVER (PARTITION BY condition_id ORDER BY record_valid_from) as prev_value,
--            LAG(type) OVER (PARTITION BY condition_id ORDER BY record_valid_from) as prev_type
--     FROM conditions
--     WHERE condition_id = :condition_id
-- )
-- SELECT
--     condition_sk,
--     record_valid_from as changed_at,
--     prev_value,
--     value as new_value,
--     prev_type,
--     type as new_type,
--     is_current
-- FROM versioned
-- WHERE prev_value IS NOT NULL
-- ORDER BY record_valid_from DESC;

-- ----------------------------------------
-- 7. DRAG & DROP REORDERING (affects current version only)
-- ----------------------------------------
-- For position changes, update current versions only
-- UPDATE conditions
-- SET position_order = :new_position,
--     updated_at = CURRENT_TIMESTAMP
-- WHERE condition_id = :condition_id
--   AND is_current = TRUE;


-- ============================================
-- PRACTICAL EXAMPLE WITH DATA
-- ============================================

-- ----------------------------------------
-- STEP 1: Insert reference data
-- ----------------------------------------
INSERT INTO suppliers (id, name, code) VALUES
(1, 'Acme Corporation', 'ACME'),
(2, 'Global Foods Inc', 'GFOOD');

INSERT INTO catalog_categories (id, name, parent_id) VALUES
(1, 'Electronics', NULL),
(2, 'Food & Beverages', NULL),
(3, 'Smartphones', 1),
(4, 'Dairy Products', 2);

INSERT INTO pricing_attributes (id, name, catalog_category_id) VALUES
(1, 'Premium Brand', 1),
(2, 'Bulk Purchase', NULL),
(3, 'Seasonal Item', 2),
(4, 'New Product Launch', NULL);

-- ----------------------------------------
-- STEP 2: Create initial conditions (January 2024)
-- ----------------------------------------
-- Supplier 1 gets a 10% discount on Premium Brand items
INSERT INTO conditions (
    condition_id, type, value, cumulability, settlement_mode,
    include_in_net_price, business_valid_from, business_valid_to,
    position_order, supplier_id, record_valid_from, record_valid_to,
    is_current, source_system
) VALUES (
    'COND-001', 'percentage', 10.00, 'progressive', 'invoice',
    FALSE, '2024-01-01', '2024-12-31',
    1, 1, '2024-01-01 09:00:00', '9999-12-31 23:59:59',
    TRUE, 'UI'
);

-- Link condition to pricing attribute
INSERT INTO condition_pricing_attributes (condition_id, attribute_id)
VALUES ('COND-001', 1);

-- ----------------------------------------
-- STEP 3: Update condition in June 2024 (discount increased to 15%)
-- ----------------------------------------
-- Step 3a: Close the current version
UPDATE conditions
SET record_valid_to = '2024-06-15 10:30:00',
    is_current = FALSE,
    updated_at = '2024-06-15 10:30:00'
WHERE condition_id = 'COND-001'
  AND is_current = TRUE;

-- Step 3b: Insert new version with updated discount
INSERT INTO conditions (
    condition_id, type, value, cumulability, settlement_mode,
    include_in_net_price, business_valid_from, business_valid_to,
    position_order, supplier_id, record_valid_from, record_valid_to,
    is_current, source_system
) VALUES (
    'COND-001', 'percentage', 15.00, 'progressive', 'invoice',
    FALSE, '2024-01-01', '2024-12-31',
    1, 1, '2024-06-15 10:30:00', '9999-12-31 23:59:59',
    TRUE, 'UI'
);

-- ----------------------------------------
-- STEP 4: Another update in October 2024 (discount changed to 12%, type changed)
-- ----------------------------------------
-- Close current version
UPDATE conditions
SET record_valid_to = '2024-10-01 14:00:00',
    is_current = FALSE,
    updated_at = '2024-10-01 14:00:00'
WHERE condition_id = 'COND-001'
  AND is_current = TRUE;

-- Insert new version
INSERT INTO conditions (
    condition_id, type, value, cumulability, settlement_mode,
    include_in_net_price, business_valid_from, business_valid_to,
    position_order, supplier_id, record_valid_from, record_valid_to,
    is_current, source_system
) VALUES (
    'COND-001', 'percentage', 12.00, 'additive', 'credit_note',
    TRUE, '2024-01-01', '2025-06-30',
    1, 1, '2024-10-01 14:00:00', '9999-12-31 23:59:59',
    TRUE, 'UI'
);


-- ============================================
-- QUERY RESULTS
-- ============================================

-- ----------------------------------------
-- RESULT 1: View all historical versions of COND-001
-- ----------------------------------------
-- SELECT condition_sk, condition_id, value, type, cumulability,
--        settlement_mode, record_valid_from, record_valid_to, is_current
-- FROM conditions
-- WHERE condition_id = 'COND-001'
-- ORDER BY record_valid_from;

-- RESULT:
-- +-------------+--------------+-------+------------+--------------+-----------------+---------------------+---------------------+------------+
-- | condition_sk| condition_id | value | type       | cumulability | settlement_mode | record_valid_from   | record_valid_to     | is_current |
-- +-------------+--------------+-------+------------+--------------+-----------------+---------------------+---------------------+------------+
-- | 1           | COND-001     | 10.00 | percentage | progressive  | invoice         | 2024-01-01 09:00:00 | 2024-06-15 10:30:00 | FALSE      |
-- | 2           | COND-001     | 15.00 | percentage | progressive  | invoice         | 2024-06-15 10:30:00 | 2024-10-01 14:00:00 | FALSE      |
-- | 3           | COND-001     | 12.00 | percentage | additive     | credit_note     | 2024-10-01 14:00:00 | 9999-12-31 23:59:59 | TRUE       |
-- +-------------+--------------+-------+------------+--------------+-----------------+---------------------+---------------------+------------+

-- ----------------------------------------
-- RESULT 2: Point-in-time query - What was the discount on March 15, 2024?
-- ----------------------------------------
-- SELECT value, type, cumulability, settlement_mode
-- FROM conditions
-- WHERE condition_id = 'COND-001'
--   AND record_valid_from <= '2024-03-15'
--   AND record_valid_to > '2024-03-15';

-- RESULT:
-- +-------+------------+--------------+-----------------+
-- | value | type       | cumulability | settlement_mode |
-- +-------+------------+--------------+-----------------+
-- | 10.00 | percentage | progressive  | invoice         |
-- +-------+------------+--------------+-----------------+
-- Answer: 10% discount, applied progressively on invoice

-- ----------------------------------------
-- RESULT 3: Point-in-time query - What was the discount on August 1, 2024?
-- ----------------------------------------
-- SELECT value, type, cumulability, settlement_mode
-- FROM conditions
-- WHERE condition_id = 'COND-001'
--   AND record_valid_from <= '2024-08-01'
--   AND record_valid_to > '2024-08-01';

-- RESULT:
-- +-------+------------+--------------+-----------------+
-- | value | type       | cumulability | settlement_mode |
-- +-------+------------+--------------+-----------------+
-- | 15.00 | percentage | progressive  | invoice         |
-- +-------+------------+--------------+-----------------+
-- Answer: 15% discount (was increased in June)

-- ----------------------------------------
-- RESULT 4: Get current condition (today)
-- ----------------------------------------
-- SELECT value, type, cumulability, settlement_mode, include_in_net_price
-- FROM conditions
-- WHERE condition_id = 'COND-001'
--   AND is_current = TRUE;

-- RESULT:
-- +-------+------------+--------------+-----------------+----------------------+
-- | value | type       | cumulability | settlement_mode | include_in_net_price |
-- +-------+------------+--------------+-----------------+----------------------+
-- | 12.00 | percentage | additive     | credit_note     | TRUE                 |
-- +-------+------------+--------------+-----------------+----------------------+
-- Answer: 12% discount, additive cumulability, settled via credit note

-- ----------------------------------------
-- RESULT 5: Timeline visualization of COND-001
-- ----------------------------------------
--
--  Jan 2024          Jun 2024           Oct 2024          Today
--     |                 |                  |                |
--     |   VALUE: 10%    |   VALUE: 15%     |   VALUE: 12%   |
--     |   Type: %       |   Type: %        |   Type: %      |
--     |   Cumul: prog   |   Cumul: prog    |   Cumul: add   |
--     |   Settle: inv   |   Settle: inv    |   Settle: CN   |
--     |---------------->|----------------->|--------------->|
--     |   Version 1     |   Version 2      |   Version 3    |
--     |   (CLOSED)      |   (CLOSED)       |   (CURRENT)    |
--
