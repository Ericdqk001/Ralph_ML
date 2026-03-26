## Key test patterns to include

**Data loading tests:**
- Data loads without error
- Expected columns are present
- Dtypes are correct
- No silent row loss

**Preprocessing tests:**
- Missing values are handled
- Output shapes are consistent
- Fit on train only, transform all splits (leakage check)
- No unexpected NaN introduced

**Split tests:**
- Split ratios are approximately correct
- No overlap between splits
- Stratification preserved (if applicable)
- Reproducible with same seed

**Training tests:**
- Model trains without error
- Loss decreases over epochs (if applicable)
- Model is serializable/saveable
- Reproducible with same seed

**Evaluation tests:**
- Metrics are computed correctly
- Metrics are within expected range (sanity check, not exact values)
- Metrics results are saved/returned in a structured format

**Orchestration / pipeline.run() tests:**
- Data augmentation applied to training split only, not val/test
- Preprocessing fitted on train, transformed on all splits
- Stages execute in correct order
- Output of one stage feeds correctly into the next
