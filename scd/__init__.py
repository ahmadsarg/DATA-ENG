"""
Slowly Changing Dimension (SCD) Type 2 Implementation

This module provides tools for managing SCD Type 2 dimensions
in data warehouse environments.
"""

from .type2 import SCDType2Processor
from .utils import generate_surrogate_key, hash_row

__version__ = "1.0.0"
__all__ = ["SCDType2Processor", "generate_surrogate_key", "hash_row"]
