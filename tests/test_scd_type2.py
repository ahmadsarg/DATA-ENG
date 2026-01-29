"""
Unit tests for SCD Type 2 Processor.
"""

from datetime import datetime

import pandas as pd
import pytest

from scd import SCDType2Processor
from scd.utils import hash_row, compare_dataframes


class TestSCDType2Processor:
    """Tests for SCDType2Processor class."""

    @pytest.fixture
    def processor(self):
        """Create a standard processor for tests."""
        return SCDType2Processor(
            natural_key=["customer_id"],
            tracked_columns=["name", "email", "segment"],
            surrogate_key="sk",
            valid_from_col="valid_from",
            valid_to_col="valid_to",
            is_current_col="is_current"
        )

    @pytest.fixture
    def existing_dimension(self):
        """Create sample existing dimension."""
        return pd.DataFrame({
            "sk": [1, 2, 3],
            "customer_id": ["C001", "C002", "C003"],
            "name": ["John", "Jane", "Bob"],
            "email": ["john@test.com", "jane@test.com", "bob@test.com"],
            "segment": ["Gold", "Silver", "Bronze"],
            "valid_from": [
                datetime(2024, 1, 1),
                datetime(2024, 1, 1),
                datetime(2024, 1, 1)
            ],
            "valid_to": [
                datetime(9999, 12, 31, 23, 59, 59),
                datetime(9999, 12, 31, 23, 59, 59),
                datetime(9999, 12, 31, 23, 59, 59)
            ],
            "is_current": [True, True, True]
        })

    def test_process_new_record(self, processor, existing_dimension):
        """Test inserting a completely new record."""
        incoming = pd.DataFrame({
            "customer_id": ["C004"],
            "name": ["Alice"],
            "email": ["alice@test.com"],
            "segment": ["Platinum"]
        })

        result = processor.process_changes(
            existing_dimension=existing_dimension,
            incoming_data=incoming,
            effective_date=datetime(2024, 6, 1)
        )

        assert len(result["inserts"]) == 1
        assert len(result["updates"]) == 0
        assert result["stats"]["new_records"] == 1

    def test_process_changed_record(self, processor, existing_dimension):
        """Test updating a record with changed attributes."""
        incoming = pd.DataFrame({
            "customer_id": ["C001"],
            "name": ["John Smith"],  # Name changed
            "email": ["john@test.com"],
            "segment": ["Platinum"]  # Segment changed
        })

        result = processor.process_changes(
            existing_dimension=existing_dimension,
            incoming_data=incoming,
            effective_date=datetime(2024, 6, 1)
        )

        assert len(result["inserts"]) == 1  # New version
        assert len(result["updates"]) == 1  # Old version expired
        assert result["stats"]["changed_records"] == 1

        # Check expired record
        expired = result["updates"].iloc[0]
        assert expired["is_current"] == False
        assert expired["valid_to"] == datetime(2024, 6, 1)

    def test_process_unchanged_record(self, processor, existing_dimension):
        """Test no changes when attributes are identical."""
        incoming = pd.DataFrame({
            "customer_id": ["C001"],
            "name": ["John"],
            "email": ["john@test.com"],
            "segment": ["Gold"]
        })

        result = processor.process_changes(
            existing_dimension=existing_dimension,
            incoming_data=incoming,
            effective_date=datetime(2024, 6, 1)
        )

        assert len(result["inserts"]) == 0
        assert len(result["updates"]) == 0
        assert result["stats"]["unchanged_records"] == 1

    def test_process_multiple_changes(self, processor, existing_dimension):
        """Test processing multiple records with mixed changes."""
        incoming = pd.DataFrame({
            "customer_id": ["C001", "C002", "C003", "C004"],
            "name": ["John", "Jane Updated", "Bob", "New Customer"],
            "email": ["john.new@test.com", "jane@test.com", "bob@test.com", "new@test.com"],
            "segment": ["Gold", "Gold", "Bronze", "Silver"]
        })

        result = processor.process_changes(
            existing_dimension=existing_dimension,
            incoming_data=incoming,
            effective_date=datetime(2024, 6, 1)
        )

        # C001: email changed -> 1 update, 1 insert
        # C002: name and segment changed -> 1 update, 1 insert
        # C003: unchanged -> 0 updates, 0 inserts
        # C004: new -> 0 updates, 1 insert

        assert len(result["updates"]) == 2  # C001 and C002 expired
        assert len(result["inserts"]) == 3  # C001 new, C002 new, C004 new
        assert result["stats"]["unchanged_records"] == 1  # C003

    def test_process_empty_existing_dimension(self, processor):
        """Test processing against empty dimension (initial load)."""
        empty_dim = pd.DataFrame()

        incoming = pd.DataFrame({
            "customer_id": ["C001", "C002"],
            "name": ["John", "Jane"],
            "email": ["john@test.com", "jane@test.com"],
            "segment": ["Gold", "Silver"]
        })

        result = processor.process_changes(
            existing_dimension=empty_dim,
            incoming_data=incoming,
            effective_date=datetime(2024, 6, 1)
        )

        assert len(result["inserts"]) == 2
        assert len(result["updates"]) == 0

    def test_apply_changes(self, processor, existing_dimension):
        """Test applying processed changes to dimension."""
        incoming = pd.DataFrame({
            "customer_id": ["C001"],
            "name": ["John Updated"],
            "email": ["john@test.com"],
            "segment": ["Gold"]
        })

        result = processor.process_changes(
            existing_dimension=existing_dimension,
            incoming_data=incoming,
            effective_date=datetime(2024, 6, 1)
        )

        updated_dim = processor.apply_changes(existing_dimension, result)

        # Should have 4 records: 3 original + 1 new version for C001
        assert len(updated_dim) == 4

        # Check C001 has 2 records now
        c001_records = updated_dim[updated_dim["customer_id"] == "C001"]
        assert len(c001_records) == 2
        assert sum(c001_records["is_current"]) == 1  # Only one current

    def test_get_current_dimension(self, processor, existing_dimension):
        """Test filtering for current records only."""
        # Add a historical record
        historical = pd.DataFrame({
            "sk": [4],
            "customer_id": ["C001"],
            "name": ["John Old"],
            "email": ["john.old@test.com"],
            "segment": ["Silver"],
            "valid_from": [datetime(2023, 1, 1)],
            "valid_to": [datetime(2024, 1, 1)],
            "is_current": [False]
        })

        full_dim = pd.concat([existing_dimension, historical], ignore_index=True)
        current = processor.get_current_dimension(full_dim)

        assert len(current) == 3
        assert all(current["is_current"])

    def test_get_history(self, processor, existing_dimension):
        """Test retrieving full history for an entity."""
        # Add historical records for C001
        historical = pd.DataFrame({
            "sk": [4, 5],
            "customer_id": ["C001", "C001"],
            "name": ["John V1", "John V2"],
            "email": ["john.v1@test.com", "john.v2@test.com"],
            "segment": ["Bronze", "Silver"],
            "valid_from": [datetime(2023, 1, 1), datetime(2023, 6, 1)],
            "valid_to": [datetime(2023, 6, 1), datetime(2024, 1, 1)],
            "is_current": [False, False]
        })

        full_dim = pd.concat([existing_dimension, historical], ignore_index=True)
        history = processor.get_history(full_dim, ("C001",))

        assert len(history) == 3  # 2 historical + 1 current
        # Should be sorted by valid_from
        dates = history["valid_from"].tolist()
        assert dates == sorted(dates)

    def test_point_in_time_lookup(self, processor, existing_dimension):
        """Test looking up record at a specific point in time."""
        # Add historical record for C001
        historical = pd.DataFrame({
            "sk": [4],
            "customer_id": ["C001"],
            "name": ["John Old"],
            "email": ["john.old@test.com"],
            "segment": ["Silver"],
            "valid_from": [datetime(2023, 1, 1)],
            "valid_to": [datetime(2024, 1, 1)],
            "is_current": [False]
        })

        full_dim = pd.concat([existing_dimension, historical], ignore_index=True)

        # Look up historical version
        old_record = processor.point_in_time_lookup(
            full_dim,
            ("C001",),
            datetime(2023, 6, 15)
        )
        assert old_record is not None
        assert old_record["name"] == "John Old"

        # Look up current version
        current_record = processor.point_in_time_lookup(
            full_dim,
            ("C001",),
            datetime(2024, 6, 15)
        )
        assert current_record is not None
        assert current_record["name"] == "John"

    def test_composite_natural_key(self):
        """Test processor with composite natural key."""
        processor = SCDType2Processor(
            natural_key=["region", "customer_id"],
            tracked_columns=["name"],
            surrogate_key="sk"
        )

        existing = pd.DataFrame({
            "sk": [1, 2],
            "region": ["US", "EU"],
            "customer_id": ["C001", "C001"],
            "name": ["US John", "EU John"],
            "valid_from": [datetime(2024, 1, 1), datetime(2024, 1, 1)],
            "valid_to": [datetime(9999, 12, 31), datetime(9999, 12, 31)],
            "is_current": [True, True]
        })

        incoming = pd.DataFrame({
            "region": ["US"],
            "customer_id": ["C001"],
            "name": ["US John Updated"]
        })

        result = processor.process_changes(existing, incoming)

        # Only US-C001 should be updated, EU-C001 unchanged
        assert len(result["updates"]) == 1
        assert len(result["inserts"]) == 1

    def test_null_value_handling(self, processor, existing_dimension):
        """Test handling of NULL values in comparisons."""
        # Update dimension to have a NULL email
        existing_dimension.loc[0, "email"] = None

        incoming = pd.DataFrame({
            "customer_id": ["C001"],
            "name": ["John"],
            "email": [None],  # Still NULL
            "segment": ["Gold"]
        })

        result = processor.process_changes(existing_dimension, incoming)

        # Should be unchanged since NULL == NULL
        assert len(result["unchanged"]) == 1


class TestUtils:
    """Tests for utility functions."""

    def test_hash_row(self):
        """Test row hashing for change detection."""
        row1 = {"a": "value1", "b": "value2", "c": "value3"}
        row2 = {"a": "value1", "b": "value2", "c": "value3"}
        row3 = {"a": "value1", "b": "CHANGED", "c": "value3"}

        hash1 = hash_row(row1, ["a", "b", "c"])
        hash2 = hash_row(row2, ["a", "b", "c"])
        hash3 = hash_row(row3, ["a", "b", "c"])

        assert hash1 == hash2  # Same values = same hash
        assert hash1 != hash3  # Different values = different hash

    def test_hash_row_with_nulls(self):
        """Test hashing handles NULL values consistently."""
        row1 = {"a": None, "b": "value"}
        row2 = {"a": None, "b": "value"}

        hash1 = hash_row(row1, ["a", "b"])
        hash2 = hash_row(row2, ["a", "b"])

        assert hash1 == hash2

    def test_compare_dataframes(self):
        """Test DataFrame comparison utility."""
        df1 = pd.DataFrame({
            "id": ["A", "B", "C"],
            "value": [1, 2, 3]
        })

        df2 = pd.DataFrame({
            "id": ["A", "B", "D"],
            "value": [1, 20, 4]  # B changed, D is new
        })

        result = compare_dataframes(
            df1, df2,
            key_columns=["id"],
            compare_columns=["value"]
        )

        assert len(result["new"]) == 1  # D
        assert len(result["changed"]) == 1  # B
        assert len(result["deleted"]) == 1  # C
        assert len(result["unchanged"]) == 1  # A


class TestValidation:
    """Tests for input validation."""

    def test_missing_natural_key_column(self):
        """Test error when natural key column is missing."""
        processor = SCDType2Processor(
            natural_key=["customer_id"],
            tracked_columns=["name"]
        )

        existing = pd.DataFrame()
        incoming = pd.DataFrame({"name": ["John"]})  # Missing customer_id

        with pytest.raises(ValueError) as exc_info:
            processor.process_changes(existing, incoming)

        assert "customer_id" in str(exc_info.value)

    def test_missing_tracked_column(self):
        """Test error when tracked column is missing."""
        processor = SCDType2Processor(
            natural_key=["id"],
            tracked_columns=["name", "email"]
        )

        existing = pd.DataFrame()
        incoming = pd.DataFrame({
            "id": ["A"],
            "name": ["John"]
            # Missing email
        })

        with pytest.raises(ValueError) as exc_info:
            processor.process_changes(existing, incoming)

        assert "email" in str(exc_info.value)


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
