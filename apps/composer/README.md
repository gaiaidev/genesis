# composer — Core Engine

Deterministic, evidence-first orchestrator that writes 388 files per Constitution.

## Install
```bash
npm i xlsx   # optional: if you want to read .xlsx directly
```

## Run
```bash
node composer/compose.mjs final_constitution.jsonl file_line_targets_by_constitution.xlsx default
```

Outputs:
- `artifacts/reports/*.json` evidence
- `logs/run.jsonl` append-only log
- `ledger/full_log_master.json` chronological ledger
- `artifacts/checkpoints/latest.json` checkpoint pointer

CI gate:
```bash
node composer/ci_authoring_guard.mjs
```

Notes:
- Zero-line placeholders are never prefilled.
- Respect predicted ≤ lines ≤ required.
- No external HTTP; deterministic seed & clock.
