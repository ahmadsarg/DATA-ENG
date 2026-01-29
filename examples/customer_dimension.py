"""
Example: Customer Dimension with SCD Type 2

This example demonstrates how to use the SCD Type 2 processor
to manage a customer dimension table with historical tracking.
"""

from datetime import datetime, timedelta

import pandas as pd

from scd import SCDType2Processor


def create_initial_dimension() -> pd.DataFrame:
    """Create initial customer dimension with sample data."""
    data = {
        "customer_sk": [1, 2, 3],
        "customer_id": ["CUST001", "CUST002", "CUST003"],
        "customer_name": ["John Smith", "Jane Doe", "Bob Wilson"],
        "email": ["john@email.com", "jane@email.com", "bob@email.com"],
        "phone": ["555-0101", "555-0102", "555-0103"],
        "address": ["123 Main St", "456 Oak Ave", "789 Pine Rd"],
        "segment": ["Gold", "Silver", "Bronze"],
        "valid_from": [
            datetime(2024, 1, 1),
            datetime(2024, 1, 15),
            datetime(2024, 2, 1)
        ],
        "valid_to": [
            datetime(9999, 12, 31, 23, 59, 59),
            datetime(9999, 12, 31, 23, 59, 59),
            datetime(9999, 12, 31, 23, 59, 59)
        ],
        "is_current": [True, True, True]
    }
    return pd.DataFrame(data)


def create_incoming_updates() -> pd.DataFrame:
    """Create sample incoming data with changes."""
    data = {
        "customer_id": ["CUST001", "CUST002", "CUST004"],
        "customer_name": ["John Smith", "Jane Wilson", "Alice Brown"],  # CUST002 name changed
        "email": ["john.smith@newemail.com", "jane@email.com", "alice@email.com"],  # CUST001 email changed
        "phone": ["555-0101", "555-0102", "555-0104"],
        "address": ["123 Main St", "456 Oak Ave", "321 Elm St"],
        "segment": ["Platinum", "Silver", "Gold"]  # CUST001 segment changed
    }
    return pd.DataFrame(data)


def main():
    """Demonstrate SCD Type 2 processing."""
    print("=" * 60)
    print("SCD Type 2 Customer Dimension Example")
    print("=" * 60)

    # Initialize the SCD Type 2 processor
    processor = SCDType2Processor(
        natural_key=["customer_id"],
        tracked_columns=["customer_name", "email", "phone", "address", "segment"],
        surrogate_key="customer_sk",
        valid_from_col="valid_from",
        valid_to_col="valid_to",
        is_current_col="is_current"
    )

    # Create initial dimension
    dimension = create_initial_dimension()
    print("\n1. INITIAL DIMENSION TABLE")
    print("-" * 40)
    print(dimension[["customer_sk", "customer_id", "customer_name", "email", "segment", "is_current"]].to_string(index=False))

    # Create incoming updates
    incoming = create_incoming_updates()
    print("\n2. INCOMING DATA (Source System)")
    print("-" * 40)
    print(incoming.to_string(index=False))

    # Process changes
    print("\n3. PROCESSING CHANGES...")
    print("-" * 40)
    effective_date = datetime(2024, 6, 1)
    result = processor.process_changes(
        existing_dimension=dimension,
        incoming_data=incoming,
        effective_date=effective_date
    )

    # Display results
    print(f"\nProcessing Statistics:")
    print(f"  - Total incoming records: {result['stats']['total_incoming']}")
    print(f"  - New records: {result['stats']['new_records']}")
    print(f"  - Changed records: {result['stats']['changed_records']}")
    print(f"  - Unchanged records: {result['stats']['unchanged_records']}")
    print(f"  - Effective date: {result['stats']['effective_date']}")

    if not result["updates"].empty:
        print("\nRecords to EXPIRE (set is_current=False):")
        print(result["updates"][["customer_sk", "customer_id", "customer_name", "valid_to", "is_current"]].to_string(index=False))

    if not result["inserts"].empty:
        insert_cols = ["customer_sk", "customer_id", "customer_name", "email", "segment", "valid_from", "is_current"]
        available_cols = [c for c in insert_cols if c in result["inserts"].columns]
        print("\nRecords to INSERT (new versions):")
        print(result["inserts"][available_cols].to_string(index=False))

    # Apply changes to dimension
    print("\n4. UPDATED DIMENSION TABLE (After SCD Type 2 Processing)")
    print("-" * 40)
    updated_dimension = processor.apply_changes(dimension, result)
    display_cols = ["customer_sk", "customer_id", "customer_name", "email", "segment", "valid_from", "valid_to", "is_current"]
    print(updated_dimension[display_cols].to_string(index=False))

    # Demonstrate point-in-time lookup
    print("\n5. POINT-IN-TIME LOOKUP")
    print("-" * 40)

    # Look up CUST001 as of January 15, 2024 (before changes)
    lookup_date = datetime(2024, 3, 15)
    historical_record = processor.point_in_time_lookup(
        updated_dimension,
        natural_key_value=("CUST001",),
        as_of_date=lookup_date
    )
    print(f"\nCUST001 as of {lookup_date.date()}:")
    if historical_record is not None:
        print(f"  Name: {historical_record['customer_name']}")
        print(f"  Email: {historical_record['email']}")
        print(f"  Segment: {historical_record['segment']}")

    # Look up CUST001 as of July 1, 2024 (after changes)
    lookup_date = datetime(2024, 7, 1)
    current_record = processor.point_in_time_lookup(
        updated_dimension,
        natural_key_value=("CUST001",),
        as_of_date=lookup_date
    )
    print(f"\nCUST001 as of {lookup_date.date()}:")
    if current_record is not None:
        print(f"  Name: {current_record['customer_name']}")
        print(f"  Email: {current_record['email']}")
        print(f"  Segment: {current_record['segment']}")

    # Show complete history
    print("\n6. COMPLETE HISTORY FOR CUST001")
    print("-" * 40)
    history = processor.get_history(updated_dimension, ("CUST001",))
    print(history[["customer_sk", "customer_name", "email", "segment", "valid_from", "valid_to", "is_current"]].to_string(index=False))

    print("\n" + "=" * 60)
    print("SCD Type 2 Processing Complete!")
    print("=" * 60)


if __name__ == "__main__":
    main()
