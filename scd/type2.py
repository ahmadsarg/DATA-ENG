"""
SCD Type 2 Processor

Implements Slowly Changing Dimension Type 2 logic for tracking
historical changes in dimension tables.
"""

from datetime import datetime
from typing import Optional

import pandas as pd
import numpy as np

from .utils import generate_surrogate_key, hash_row


class SCDType2Processor:
    """
    Processor for handling SCD Type 2 dimension changes.

    SCD Type 2 preserves history by:
    - Creating new records when tracked attributes change
    - Maintaining validity periods (valid_from, valid_to)
    - Flagging current records (is_current)

    Attributes:
        natural_key: Column(s) that uniquely identify a dimension entity
        tracked_columns: Columns to monitor for changes
        surrogate_key: Name of the surrogate key column
        valid_from_col: Name of the valid_from column
        valid_to_col: Name of the valid_to column
        is_current_col: Name of the is_current flag column
    """

    def __init__(
        self,
        natural_key: list[str],
        tracked_columns: list[str],
        surrogate_key: str = "sk",
        valid_from_col: str = "valid_from",
        valid_to_col: str = "valid_to",
        is_current_col: str = "is_current",
        end_of_time: Optional[datetime] = None
    ):
        """
        Initialize the SCD Type 2 processor.

        Args:
            natural_key: List of columns forming the natural/business key
            tracked_columns: List of columns to track for changes
            surrogate_key: Name for the surrogate key column
            valid_from_col: Name for the valid from date column
            valid_to_col: Name for the valid to date column
            is_current_col: Name for the current record flag column
            end_of_time: Default end date for current records (default: 9999-12-31)
        """
        self.natural_key = natural_key if isinstance(natural_key, list) else [natural_key]
        self.tracked_columns = tracked_columns
        self.surrogate_key = surrogate_key
        self.valid_from_col = valid_from_col
        self.valid_to_col = valid_to_col
        self.is_current_col = is_current_col
        self.end_of_time = end_of_time or datetime(9999, 12, 31, 23, 59, 59)

    def process_changes(
        self,
        existing_dimension: pd.DataFrame,
        incoming_data: pd.DataFrame,
        effective_date: Optional[datetime] = None
    ) -> dict:
        """
        Process incoming data against existing dimension to detect and apply changes.

        Args:
            existing_dimension: Current dimension table data
            incoming_data: New/updated records to process
            effective_date: Date when changes take effect (default: now)

        Returns:
            Dictionary containing:
                - inserts: New records to insert
                - updates: Existing records to expire (update valid_to)
                - unchanged: Records with no changes
                - stats: Processing statistics
        """
        effective_date = effective_date or datetime.now()

        # Validate inputs
        self._validate_inputs(existing_dimension, incoming_data)

        # Get current records from existing dimension
        if existing_dimension.empty:
            current_records = pd.DataFrame()
        else:
            current_records = existing_dimension[
                existing_dimension[self.is_current_col] == True
            ].copy()

        # Initialize result containers
        inserts = []
        updates = []
        unchanged = []

        # Create lookup for existing records by natural key
        existing_lookup = {}
        if not current_records.empty:
            for idx, row in current_records.iterrows():
                key = self._get_natural_key_value(row)
                existing_lookup[key] = row

        # Process each incoming record
        for idx, incoming_row in incoming_data.iterrows():
            key = self._get_natural_key_value(incoming_row)

            if key in existing_lookup:
                existing_row = existing_lookup[key]

                # Check if tracked columns have changed
                if self._has_changes(existing_row, incoming_row):
                    # Record needs to be updated (expire old, insert new)
                    expired_record = self._expire_record(
                        existing_row,
                        effective_date
                    )
                    updates.append(expired_record)

                    new_record = self._create_new_record(
                        incoming_row,
                        effective_date,
                        self._get_next_surrogate_key(existing_dimension)
                    )
                    inserts.append(new_record)
                else:
                    # No changes detected
                    unchanged.append(existing_row.to_dict())
            else:
                # Completely new record
                new_record = self._create_new_record(
                    incoming_row,
                    effective_date,
                    self._get_next_surrogate_key(existing_dimension)
                )
                inserts.append(new_record)

        # Compile statistics
        stats = {
            "total_incoming": len(incoming_data),
            "new_records": len([r for r in inserts if r.get("_is_new", False)]),
            "changed_records": len(updates),
            "unchanged_records": len(unchanged),
            "effective_date": effective_date
        }

        return {
            "inserts": pd.DataFrame(inserts) if inserts else pd.DataFrame(),
            "updates": pd.DataFrame(updates) if updates else pd.DataFrame(),
            "unchanged": pd.DataFrame(unchanged) if unchanged else pd.DataFrame(),
            "stats": stats
        }

    def apply_changes(
        self,
        existing_dimension: pd.DataFrame,
        changes: dict
    ) -> pd.DataFrame:
        """
        Apply processed changes to create updated dimension table.

        Args:
            existing_dimension: Current dimension table
            changes: Output from process_changes()

        Returns:
            Updated dimension DataFrame with all changes applied
        """
        result = existing_dimension.copy()

        # Apply updates (expire records)
        if not changes["updates"].empty:
            update_keys = changes["updates"][self.surrogate_key].tolist()
            for sk in update_keys:
                mask = result[self.surrogate_key] == sk
                update_row = changes["updates"][
                    changes["updates"][self.surrogate_key] == sk
                ].iloc[0]
                result.loc[mask, self.valid_to_col] = update_row[self.valid_to_col]
                result.loc[mask, self.is_current_col] = False

        # Apply inserts
        if not changes["inserts"].empty:
            inserts_clean = changes["inserts"].drop(columns=["_is_new"], errors="ignore")
            result = pd.concat([result, inserts_clean], ignore_index=True)

        return result

    def _validate_inputs(
        self,
        existing: pd.DataFrame,
        incoming: pd.DataFrame
    ) -> None:
        """Validate input DataFrames have required columns."""
        # Check natural key columns in incoming data
        for col in self.natural_key:
            if col not in incoming.columns:
                raise ValueError(f"Natural key column '{col}' missing from incoming data")

        # Check tracked columns in incoming data
        for col in self.tracked_columns:
            if col not in incoming.columns:
                raise ValueError(f"Tracked column '{col}' missing from incoming data")

        # Check existing dimension has SCD columns (if not empty)
        if not existing.empty:
            required_cols = [
                self.surrogate_key,
                self.valid_from_col,
                self.valid_to_col,
                self.is_current_col
            ]
            for col in required_cols:
                if col not in existing.columns:
                    raise ValueError(f"SCD column '{col}' missing from existing dimension")

    def _get_natural_key_value(self, row: pd.Series) -> tuple:
        """Extract natural key value(s) from a row."""
        return tuple(row[col] for col in self.natural_key)

    def _has_changes(self, existing: pd.Series, incoming: pd.Series) -> bool:
        """Check if any tracked columns have changed."""
        for col in self.tracked_columns:
            existing_val = existing.get(col)
            incoming_val = incoming.get(col)

            # Handle NaN comparisons
            if pd.isna(existing_val) and pd.isna(incoming_val):
                continue
            if pd.isna(existing_val) or pd.isna(incoming_val):
                return True
            if existing_val != incoming_val:
                return True

        return False

    def _expire_record(
        self,
        record: pd.Series,
        effective_date: datetime
    ) -> dict:
        """Create expired version of a record."""
        expired = record.to_dict()
        expired[self.valid_to_col] = effective_date
        expired[self.is_current_col] = False
        return expired

    def _create_new_record(
        self,
        incoming: pd.Series,
        effective_date: datetime,
        surrogate_key_value: int
    ) -> dict:
        """Create a new dimension record."""
        record = incoming.to_dict()
        record[self.surrogate_key] = surrogate_key_value
        record[self.valid_from_col] = effective_date
        record[self.valid_to_col] = self.end_of_time
        record[self.is_current_col] = True
        record["_is_new"] = surrogate_key_value not in [0]  # Mark as new for stats
        return record

    def _get_next_surrogate_key(self, existing: pd.DataFrame) -> int:
        """Generate next surrogate key value."""
        if existing.empty or self.surrogate_key not in existing.columns:
            return 1
        return int(existing[self.surrogate_key].max()) + 1

    def get_current_dimension(self, dimension: pd.DataFrame) -> pd.DataFrame:
        """Get only current (active) records from dimension."""
        if dimension.empty:
            return dimension
        return dimension[dimension[self.is_current_col] == True].copy()

    def get_history(
        self,
        dimension: pd.DataFrame,
        natural_key_value: tuple
    ) -> pd.DataFrame:
        """Get complete history for a specific entity."""
        if dimension.empty:
            return dimension

        mask = True
        for i, col in enumerate(self.natural_key):
            mask = mask & (dimension[col] == natural_key_value[i])

        history = dimension[mask].copy()
        return history.sort_values(self.valid_from_col)

    def point_in_time_lookup(
        self,
        dimension: pd.DataFrame,
        natural_key_value: tuple,
        as_of_date: datetime
    ) -> Optional[pd.Series]:
        """
        Get dimension record as it existed at a specific point in time.

        Args:
            dimension: Full dimension table with history
            natural_key_value: Natural key to look up
            as_of_date: Historical date for lookup

        Returns:
            Dimension record valid at the specified date, or None
        """
        history = self.get_history(dimension, natural_key_value)

        if history.empty:
            return None

        # Find record valid at the as_of_date
        for idx, row in history.iterrows():
            valid_from = row[self.valid_from_col]
            valid_to = row[self.valid_to_col]

            if valid_from <= as_of_date <= valid_to:
                return row

        return None
