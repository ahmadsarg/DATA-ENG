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

CREATE INDEX idx_suppliers_code ON suppliers(code);

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

CREATE INDEX idx_catalog_categories_parent ON catalog_categories(parent_id);

-- --------------------------------------------
-- Conditions Table
-- --------------------------------------------
-- Stores supplier conditions with support for:
-- - Different condition types (percentage, absolute, net)
-- - Cumulability modes (progressive, additive)
-- - Settlement modes (invoice, credit_note)
-- - Position ordering for drag & drop functionality
CREATE TABLE IF NOT EXISTS conditions (
    id                      SERIAL PRIMARY KEY,

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

    -- Validity Period
    valid_from              DATE NOT NULL,
    valid_to                DATE,

    -- Position Order: used for drag & drop ordering in UI
    -- New conditions get max(position_order) + 1
    position_order          INTEGER NOT NULL,

    -- Foreign Key to Supplier
    supplier_id             INTEGER NOT NULL REFERENCES suppliers(id) ON DELETE CASCADE,

    -- Audit Columns
    created_at              TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at              TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Index for listing conditions by supplier ordered by position
CREATE INDEX idx_conditions_supplier_position ON conditions(supplier_id, position_order);

-- Index for validity date filtering
CREATE INDEX idx_conditions_validity ON conditions(valid_from, valid_to);

-- Index for filtering by type
CREATE INDEX idx_conditions_type ON conditions(type);

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

CREATE INDEX idx_pricing_attributes_category ON pricing_attributes(catalog_category_id);
CREATE INDEX idx_pricing_attributes_name ON pricing_attributes(name);

-- --------------------------------------------
-- Condition Pricing Attributes (Junction Table)
-- --------------------------------------------
-- Many-to-many relationship between conditions and pricing attributes
-- A condition can apply to multiple pricing attributes (or none)
-- A pricing attribute can be linked to multiple conditions
CREATE TABLE IF NOT EXISTS condition_pricing_attributes (
    condition_id            INTEGER NOT NULL REFERENCES conditions(id) ON DELETE CASCADE,
    attribute_id            INTEGER NOT NULL REFERENCES pricing_attributes(id) ON DELETE CASCADE,

    -- Composite Primary Key
    PRIMARY KEY (condition_id, attribute_id),

    -- Audit Column
    created_at              TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Index for looking up attributes by condition
CREATE INDEX idx_cpa_condition ON condition_pricing_attributes(condition_id);

-- Index for looking up conditions by attribute
CREATE INDEX idx_cpa_attribute ON condition_pricing_attributes(attribute_id);


-- ============================================
-- Snowflake Version
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
    id                      INTEGER AUTOINCREMENT PRIMARY KEY,
    type                    VARCHAR(20) NOT NULL,
    value                   DECIMAL(15, 4) NOT NULL,
    cumulability            VARCHAR(20) NOT NULL,
    settlement_mode         VARCHAR(20) NOT NULL,
    include_in_net_price    BOOLEAN DEFAULT FALSE,
    valid_from              DATE NOT NULL,
    valid_to                DATE,
    position_order          INTEGER NOT NULL,
    supplier_id             INTEGER NOT NULL REFERENCES suppliers(id),
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
    condition_id            INTEGER NOT NULL REFERENCES conditions(id),
    attribute_id            INTEGER NOT NULL REFERENCES pricing_attributes(id),
    created_at              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (condition_id, attribute_id)
);
*/


-- ============================================
-- BigQuery Version
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
    id                      INT64 NOT NULL,
    type                    STRING NOT NULL,
    value                   NUMERIC NOT NULL,
    cumulability            STRING NOT NULL,
    settlement_mode         STRING NOT NULL,
    include_in_net_price    BOOL DEFAULT FALSE,
    valid_from              DATE NOT NULL,
    valid_to                DATE,
    position_order          INT64 NOT NULL,
    supplier_id             INT64 NOT NULL,
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
    condition_id            INT64 NOT NULL,
    attribute_id            INT64 NOT NULL,
    created_at              TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);
*/


-- ============================================
-- Helper Queries for UI Operations
-- ============================================

-- Get all conditions for a supplier ordered by position
-- SELECT c.*,
--        array_agg(pa.name) FILTER (WHERE pa.name IS NOT NULL) as pricing_attribute_names
-- FROM conditions c
-- LEFT JOIN condition_pricing_attributes cpa ON c.id = cpa.condition_id
-- LEFT JOIN pricing_attributes pa ON cpa.attribute_id = pa.id
-- WHERE c.supplier_id = :supplier_id
-- GROUP BY c.id
-- ORDER BY c.position_order ASC;

-- Get max position_order for a supplier (used when adding new condition)
-- SELECT COALESCE(MAX(position_order), 0) + 1 as next_position
-- FROM conditions
-- WHERE supplier_id = :supplier_id;

-- Update position_order for drag & drop reordering
-- UPDATE conditions
-- SET position_order = :new_position, updated_at = CURRENT_TIMESTAMP
-- WHERE id = :condition_id AND supplier_id = :supplier_id;
