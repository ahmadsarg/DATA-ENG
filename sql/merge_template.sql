-- ============================================
-- SCD Type 2 MERGE Template
-- ============================================
-- This template demonstrates how to implement SCD Type 2
-- using MERGE statements for atomic dimension updates.

-- ============================================
-- PostgreSQL (using INSERT ON CONFLICT + UPDATE)
-- PostgreSQL doesn't support full MERGE until v15
-- ============================================

-- Step 1: Expire changed records
UPDATE dim_customer AS target
SET
    valid_to = CURRENT_TIMESTAMP,
    is_current = FALSE,
    updated_at = CURRENT_TIMESTAMP
FROM staging_customer AS source
WHERE target.customer_id = source.customer_id
  AND target.is_current = TRUE
  AND (
      target.customer_name IS DISTINCT FROM source.customer_name
      OR target.email IS DISTINCT FROM source.email
      OR target.phone IS DISTINCT FROM source.phone
      OR target.address_line1 IS DISTINCT FROM source.address_line1
      OR target.city IS DISTINCT FROM source.city
      OR target.state IS DISTINCT FROM source.state
      OR target.postal_code IS DISTINCT FROM source.postal_code
      OR target.country IS DISTINCT FROM source.country
      OR target.customer_segment IS DISTINCT FROM source.customer_segment
  );

-- Step 2: Insert new/changed records
INSERT INTO dim_customer (
    customer_id,
    customer_name,
    email,
    phone,
    address_line1,
    address_line2,
    city,
    state,
    postal_code,
    country,
    customer_segment,
    valid_from,
    valid_to,
    is_current,
    source_system,
    created_at,
    updated_at
)
SELECT
    source.customer_id,
    source.customer_name,
    source.email,
    source.phone,
    source.address_line1,
    source.address_line2,
    source.city,
    source.state,
    source.postal_code,
    source.country,
    source.customer_segment,
    CURRENT_TIMESTAMP AS valid_from,
    '9999-12-31 23:59:59'::TIMESTAMP AS valid_to,
    TRUE AS is_current,
    source.source_system,
    CURRENT_TIMESTAMP AS created_at,
    CURRENT_TIMESTAMP AS updated_at
FROM staging_customer AS source
LEFT JOIN dim_customer AS target
    ON source.customer_id = target.customer_id
    AND target.is_current = TRUE
WHERE target.customer_sk IS NULL  -- New records
   OR (  -- Changed records
      target.customer_name IS DISTINCT FROM source.customer_name
      OR target.email IS DISTINCT FROM source.email
      OR target.phone IS DISTINCT FROM source.phone
      OR target.address_line1 IS DISTINCT FROM source.address_line1
      OR target.city IS DISTINCT FROM source.city
      OR target.state IS DISTINCT FROM source.state
      OR target.postal_code IS DISTINCT FROM source.postal_code
      OR target.country IS DISTINCT FROM source.country
      OR target.customer_segment IS DISTINCT FROM source.customer_segment
   );


-- ============================================
-- Snowflake MERGE Statement
-- ============================================
/*
MERGE INTO dim_customer AS target
USING (
    SELECT
        s.*,
        CURRENT_TIMESTAMP() AS effective_date
    FROM staging_customer s
) AS source
ON target.customer_id = source.customer_id AND target.is_current = TRUE

-- When matched and attributes changed: expire existing record
WHEN MATCHED AND (
    target.customer_name <> source.customer_name
    OR target.email <> source.email
    OR target.phone <> source.phone
    OR target.address_line1 <> source.address_line1
    OR target.city <> source.city
    OR target.customer_segment <> source.customer_segment
    OR (target.customer_name IS NULL AND source.customer_name IS NOT NULL)
    OR (target.email IS NULL AND source.email IS NOT NULL)
) THEN UPDATE SET
    valid_to = source.effective_date,
    is_current = FALSE,
    updated_at = CURRENT_TIMESTAMP()

-- When not matched: insert new record
WHEN NOT MATCHED THEN INSERT (
    customer_id,
    customer_name,
    email,
    phone,
    address_line1,
    address_line2,
    city,
    state,
    postal_code,
    country,
    customer_segment,
    valid_from,
    valid_to,
    is_current,
    source_system,
    created_at,
    updated_at
) VALUES (
    source.customer_id,
    source.customer_name,
    source.email,
    source.phone,
    source.address_line1,
    source.address_line2,
    source.city,
    source.state,
    source.postal_code,
    source.country,
    source.customer_segment,
    source.effective_date,
    '9999-12-31 23:59:59',
    TRUE,
    source.source_system,
    CURRENT_TIMESTAMP(),
    CURRENT_TIMESTAMP()
);

-- Note: Snowflake MERGE cannot insert new versions for changed records
-- in the same statement. Use a separate INSERT after the MERGE:

INSERT INTO dim_customer (
    customer_id, customer_name, email, phone,
    address_line1, address_line2, city, state,
    postal_code, country, customer_segment,
    valid_from, valid_to, is_current,
    source_system, created_at, updated_at
)
SELECT
    s.customer_id, s.customer_name, s.email, s.phone,
    s.address_line1, s.address_line2, s.city, s.state,
    s.postal_code, s.country, s.customer_segment,
    CURRENT_TIMESTAMP(), '9999-12-31 23:59:59', TRUE,
    s.source_system, CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()
FROM staging_customer s
INNER JOIN dim_customer d
    ON s.customer_id = d.customer_id
WHERE d.is_current = FALSE
  AND d.valid_to = (SELECT MAX(valid_to) FROM dim_customer WHERE customer_id = s.customer_id AND is_current = FALSE);
*/


-- ============================================
-- BigQuery MERGE Statement
-- ============================================
/*
-- BigQuery supports full MERGE with multiple actions
MERGE `project.dataset.dim_customer` AS target
USING `project.dataset.staging_customer` AS source
ON target.customer_id = source.customer_id AND target.is_current = TRUE

-- Expire changed records
WHEN MATCHED AND (
    IFNULL(target.customer_name, '') <> IFNULL(source.customer_name, '')
    OR IFNULL(target.email, '') <> IFNULL(source.email, '')
    OR IFNULL(target.phone, '') <> IFNULL(source.phone, '')
    OR IFNULL(target.customer_segment, '') <> IFNULL(source.customer_segment, '')
) THEN UPDATE SET
    valid_to = CURRENT_TIMESTAMP(),
    is_current = FALSE,
    updated_at = CURRENT_TIMESTAMP()

-- Insert new records (not matched)
WHEN NOT MATCHED THEN INSERT (
    customer_sk, customer_id, customer_name, email, phone,
    address_line1, address_line2, city, state, postal_code,
    country, customer_segment, valid_from, valid_to, is_current,
    source_system, created_at, updated_at
) VALUES (
    GENERATE_UUID(),
    source.customer_id, source.customer_name, source.email, source.phone,
    source.address_line1, source.address_line2, source.city, source.state,
    source.postal_code, source.country, source.customer_segment,
    CURRENT_TIMESTAMP(), TIMESTAMP('9999-12-31 23:59:59'), TRUE,
    source.source_system, CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()
);
*/


-- ============================================
-- Helper Query: Point-in-Time Lookup
-- ============================================
-- Get customer data as it existed on a specific date

SELECT *
FROM dim_customer
WHERE customer_id = 'CUST001'
  AND valid_from <= '2024-06-15'::TIMESTAMP
  AND valid_to > '2024-06-15'::TIMESTAMP;


-- ============================================
-- Helper Query: Full History for a Customer
-- ============================================

SELECT
    customer_sk,
    customer_id,
    customer_name,
    email,
    customer_segment,
    valid_from,
    valid_to,
    is_current,
    CASE
        WHEN is_current THEN 'Current'
        ELSE 'Historical'
    END AS record_status
FROM dim_customer
WHERE customer_id = 'CUST001'
ORDER BY valid_from;


-- ============================================
-- Helper Query: Detect Changed Records
-- ============================================

SELECT
    s.customer_id,
    'CHANGED' AS change_type,
    d.customer_name AS old_name,
    s.customer_name AS new_name,
    d.email AS old_email,
    s.email AS new_email
FROM staging_customer s
INNER JOIN dim_customer d
    ON s.customer_id = d.customer_id
    AND d.is_current = TRUE
WHERE s.customer_name IS DISTINCT FROM d.customer_name
   OR s.email IS DISTINCT FROM d.email
   OR s.customer_segment IS DISTINCT FROM d.customer_segment;
