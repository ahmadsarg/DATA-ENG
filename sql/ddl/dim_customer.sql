-- ============================================
-- SCD Type 2 Customer Dimension Table
-- ============================================

-- PostgreSQL Version
CREATE TABLE IF NOT EXISTS dim_customer (
    -- Surrogate Key (auto-generated unique identifier)
    customer_sk         SERIAL PRIMARY KEY,

    -- Natural Key (business key from source system)
    customer_id         VARCHAR(50) NOT NULL,

    -- Tracked Dimension Attributes
    customer_name       VARCHAR(255),
    email               VARCHAR(255),
    phone               VARCHAR(20),
    address_line1       VARCHAR(255),
    address_line2       VARCHAR(255),
    city                VARCHAR(100),
    state               VARCHAR(50),
    postal_code         VARCHAR(20),
    country             VARCHAR(100),
    customer_segment    VARCHAR(50),

    -- SCD Type 2 Metadata
    valid_from          TIMESTAMP NOT NULL,
    valid_to            TIMESTAMP DEFAULT '9999-12-31 23:59:59',
    is_current          BOOLEAN DEFAULT TRUE,

    -- Audit Columns
    source_system       VARCHAR(50),
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for query performance
CREATE INDEX idx_dim_customer_natural_key ON dim_customer(customer_id);
CREATE INDEX idx_dim_customer_current ON dim_customer(is_current) WHERE is_current = TRUE;
CREATE INDEX idx_dim_customer_valid_dates ON dim_customer(valid_from, valid_to);

-- ============================================
-- Snowflake Version
-- ============================================
/*
CREATE TABLE IF NOT EXISTS dim_customer (
    customer_sk         INTEGER AUTOINCREMENT PRIMARY KEY,
    customer_id         VARCHAR(50) NOT NULL,
    customer_name       VARCHAR(255),
    email               VARCHAR(255),
    phone               VARCHAR(20),
    address_line1       VARCHAR(255),
    address_line2       VARCHAR(255),
    city                VARCHAR(100),
    state               VARCHAR(50),
    postal_code         VARCHAR(20),
    country             VARCHAR(100),
    customer_segment    VARCHAR(50),
    valid_from          TIMESTAMP_NTZ NOT NULL,
    valid_to            TIMESTAMP_NTZ DEFAULT '9999-12-31 23:59:59',
    is_current          BOOLEAN DEFAULT TRUE,
    source_system       VARCHAR(50),
    created_at          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    updated_at          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
*/

-- ============================================
-- BigQuery Version
-- ============================================
/*
CREATE TABLE IF NOT EXISTS `project.dataset.dim_customer` (
    customer_sk         INT64 NOT NULL,
    customer_id         STRING NOT NULL,
    customer_name       STRING,
    email               STRING,
    phone               STRING,
    address_line1       STRING,
    address_line2       STRING,
    city                STRING,
    state               STRING,
    postal_code         STRING,
    country             STRING,
    customer_segment    STRING,
    valid_from          TIMESTAMP NOT NULL,
    valid_to            TIMESTAMP,
    is_current          BOOL DEFAULT TRUE,
    source_system       STRING,
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);
*/
