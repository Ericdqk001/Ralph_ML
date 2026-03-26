## Example test directory layout

The exact files depend on the pipeline stages defined in stage 1. Here is a typical structure:

```
tests/<method_name>/
├── conftest.py        # Instantiates Pipeline, provides fixtures (synthetic data, paths)
├── test_load.py       # Tests pipeline.load()
├── test_preprocess.py # Tests pipeline.preprocess()
├── test_split.py      # Tests pipeline.split()
├── test_train.py      # Tests pipeline.train()
├── test_evaluate.py   # Tests pipeline.evaluate()
└── test_pipeline.py   # Tests pipeline.run() orchestration correctness
```

Every test file imports `Pipeline` from `src.<method_name>.pipeline` and calls the relevant method.
