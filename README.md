# Slowly Changing Dimension Type 2 (SCD Type 2)

A Python implementation for managing Slowly Changing Dimensions Type 2 in data warehousing.

## What is SCD Type 2?

SCD Type 2 is a dimension modeling technique that preserves the complete history of changes by:

- **Creating new records** when dimension attributes change
- **Tracking validity periods** with `valid_from` and `valid_to` dates
- **Flagging current records** with an `is_current` indicator
- **Using surrogate keys** to maintain referential integrity

## Features

- Pure Python implementation with pandas support
- SQL templates for major databases (PostgreSQL, Snowflake, BigQuery)
- Change detection with configurable tracked columns
- Support for soft deletes
- Comprehensive audit trail

## Installation

```bash
pip install -r requirements.txt
```

## Quick Start

```python
from scd.type2 import SCDType2Processor

# Initialize processor
processor = SCDType2Processor(
    natural_key=['customer_id'],
    tracked_columns=['name', 'email', 'address', 'phone'],
    surrogate_key='customer_sk'
)

# Process incoming dimension changes
result = processor.process_changes(
    existing_dimension=current_dim_df,
    incoming_data=new_data_df
)

# Access results
new_records = result['inserts']
expired_records = result['updates']
unchanged_records = result['unchanged']
```

## Project Structure

```
DATA-ENG/
├── README.md
├── requirements.txt
├── scd/
│   ├── __init__.py
│   ├── type2.py          # Core SCD Type 2 logic
│   └── utils.py          # Helper utilities
├── sql/
│   ├── merge_template.sql
│   └── ddl/
│       └── dim_customer.sql
├── examples/
│   └── customer_dimension.py
└── tests/
    └── test_scd_type2.py
```

## SCD Type 2 Table Schema

A typical SCD Type 2 dimension table includes:

| Column | Description |
|--------|-------------|
| `surrogate_key` | Auto-generated unique identifier |
| `natural_key` | Business key from source system |
| `attribute_1..n` | Tracked dimension attributes |
| `valid_from` | Record effective start date |
| `valid_to` | Record effective end date |
| `is_current` | Flag indicating active record |
| `created_at` | Record creation timestamp |
| `updated_at` | Record modification timestamp |

## Example: Customer Dimension

```sql
CREATE TABLE dim_customer (
    customer_sk      SERIAL PRIMARY KEY,
    customer_id      VARCHAR(50) NOT NULL,  -- Natural key
    customer_name    VARCHAR(255),
    email            VARCHAR(255),
    address          VARCHAR(500),
    phone            VARCHAR(20),
    valid_from       TIMESTAMP NOT NULL,
    valid_to         TIMESTAMP,
    is_current       BOOLEAN DEFAULT TRUE,
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

## Processing Logic

1. **Match** incoming records with existing dimension using natural key
2. **Detect changes** in tracked columns
3. **For changed records:**
   - Expire existing record (set `valid_to`, `is_current = FALSE`)
   - Insert new record (set `valid_from`, `is_current = TRUE`)
4. **For new records:** Insert with current validity
5. **For unchanged records:** No action required

## License

MIT License
