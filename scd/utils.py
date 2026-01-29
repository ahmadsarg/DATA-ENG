"""
Utility functions for SCD Type 2 processing.
"""

import hashlib
from typing import Union
import pandas as pd


def generate_surrogate_key(
    start: int = 1,
    existing_max: int = 0
) -> int:
    """
    Generate next surrogate key value.

    Args:
        start: Starting value for new dimensions
        existing_max: Maximum existing surrogate key

    Returns:
        Next surrogate key value
    """
    return max(start, existing_max + 1)


def hash_row(
    row: Union[pd.Series, dict],
    columns: list[str]
) -> str:
    """
    Generate hash of specified columns for change detection.

    Args:
        row: Data row (Series or dict)
        columns: Columns to include in hash

    Returns:
        MD5 hash string of column values
    """
    if isinstance(row, pd.Series):
        row = row.to_dict()

    values = []
    for col in sorted(columns):
        val = row.get(col, "")
        if pd.isna(val):
            val = "__NULL__"
        values.append(str(val))

    combined = "|".join(values)
    return hashlib.md5(combined.encode()).hexdigest()


def compare_dataframes(
    df1: pd.DataFrame,
    df2: pd.DataFrame,
    key_columns: list[str],
    compare_columns: list[str]
) -> dict:
    """
    Compare two DataFrames to identify new, changed, and deleted records.

    Args:
        df1: Source DataFrame (existing data)
        df2: Target DataFrame (incoming data)
        key_columns: Columns forming the natural key
        compare_columns: Columns to compare for changes

    Returns:
        Dictionary with 'new', 'changed', 'deleted', 'unchanged' DataFrames
    """
    # Create key strings for comparison
    df1_keys = set()
    df2_keys = set()

    if not df1.empty:
        df1["_key"] = df1[key_columns].astype(str).agg("|".join, axis=1)
        df1_keys = set(df1["_key"])

    if not df2.empty:
        df2["_key"] = df2[key_columns].astype(str).agg("|".join, axis=1)
        df2_keys = set(df2["_key"])

    # Identify record categories
    new_keys = df2_keys - df1_keys
    deleted_keys = df1_keys - df2_keys
    common_keys = df1_keys & df2_keys

    # Filter DataFrames
    new_records = df2[df2["_key"].isin(new_keys)].drop(columns=["_key"]) if not df2.empty else pd.DataFrame()
    deleted_records = df1[df1["_key"].isin(deleted_keys)].drop(columns=["_key"]) if not df1.empty else pd.DataFrame()

    # Check for changes in common records
    changed = []
    unchanged = []

    for key in common_keys:
        row1 = df1[df1["_key"] == key].iloc[0]
        row2 = df2[df2["_key"] == key].iloc[0]

        hash1 = hash_row(row1, compare_columns)
        hash2 = hash_row(row2, compare_columns)

        if hash1 != hash2:
            changed.append(row2.drop("_key").to_dict())
        else:
            unchanged.append(row2.drop("_key").to_dict())

    # Clean up temporary columns
    if "_key" in df1.columns:
        df1.drop(columns=["_key"], inplace=True)
    if "_key" in df2.columns:
        df2.drop(columns=["_key"], inplace=True)

    return {
        "new": new_records if not new_records.empty else pd.DataFrame(),
        "changed": pd.DataFrame(changed) if changed else pd.DataFrame(),
        "deleted": deleted_records if not deleted_records.empty else pd.DataFrame(),
        "unchanged": pd.DataFrame(unchanged) if unchanged else pd.DataFrame()
    }


def format_date_columns(
    df: pd.DataFrame,
    date_columns: list[str],
    format_str: str = "%Y-%m-%d %H:%M:%S"
) -> pd.DataFrame:
    """
    Format date columns to string representation.

    Args:
        df: DataFrame to format
        date_columns: List of date column names
        format_str: strftime format string

    Returns:
        DataFrame with formatted date columns
    """
    result = df.copy()
    for col in date_columns:
        if col in result.columns:
            result[col] = pd.to_datetime(result[col]).dt.strftime(format_str)
    return result


def create_dimension_schema(
    natural_key_columns: list[dict],
    tracked_columns: list[dict],
    surrogate_key_name: str = "sk"
) -> dict:
    """
    Generate schema definition for an SCD Type 2 dimension table.

    Args:
        natural_key_columns: List of dicts with 'name' and 'type'
        tracked_columns: List of dicts with 'name' and 'type'
        surrogate_key_name: Name for surrogate key column

    Returns:
        Dictionary schema definition
    """
    schema = {
        "columns": [
            {"name": surrogate_key_name, "type": "INTEGER", "primary_key": True},
        ]
    }

    # Add natural key columns
    for col in natural_key_columns:
        schema["columns"].append({
            "name": col["name"],
            "type": col.get("type", "VARCHAR(255)"),
            "nullable": False
        })

    # Add tracked columns
    for col in tracked_columns:
        schema["columns"].append({
            "name": col["name"],
            "type": col.get("type", "VARCHAR(255)"),
            "nullable": col.get("nullable", True)
        })

    # Add SCD Type 2 metadata columns
    schema["columns"].extend([
        {"name": "valid_from", "type": "TIMESTAMP", "nullable": False},
        {"name": "valid_to", "type": "TIMESTAMP", "nullable": True},
        {"name": "is_current", "type": "BOOLEAN", "default": True},
        {"name": "created_at", "type": "TIMESTAMP", "default": "CURRENT_TIMESTAMP"},
        {"name": "updated_at", "type": "TIMESTAMP", "default": "CURRENT_TIMESTAMP"}
    ])

    return schema
