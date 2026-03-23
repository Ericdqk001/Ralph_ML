## PRD template

Create `tasks/<method_name>/prd.json` with one story per test file:

```json
{
  "project": "<Method Name>",
  "branchName": "ralph/<method_name>",
  "description": "<User's description of the method>",
  "userStories": [
    {
      "id": "US-001",
      "title": "<Stage title>",
      "test_file": "tests/<method_name>/test_<stage>.py",
      "implementation_order": 1,
      "passes": false,
      "notes": ""
    }
  ]
}
```

Stories are ordered by `implementation_order` matching the natural pipeline flow (load -> preprocess -> split -> train -> evaluate).
