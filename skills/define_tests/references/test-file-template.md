## Test file structure template

```python
"""Tests for <stage_name> stage of <method_name> pipeline."""
import pytest
import numpy as np
import pandas as pd

from src.<method_name>.pipeline import Pipeline


class TestStageName:
    """Tests for the <stage_name> stage."""

    def test_basic_functionality(self, pipeline):
        """Verify the happy path works."""
        ...

    def test_output_shape(self, pipeline):
        """Verify output dimensions match expectations."""
        ...

    def test_no_data_leakage(self, pipeline):
        """Verify no information leaks across splits."""
        ...

    def test_reproducibility(self, pipeline):
        """Verify results are deterministic with same seed."""
        ...

    def test_edge_cases(self, pipeline):
        """Verify handling of edge cases (empty data, missing values, etc.)."""
        ...
```
