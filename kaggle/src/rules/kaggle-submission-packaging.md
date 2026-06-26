---
description: Code Competition submission rules — offline notebook, exact submission filename, runtime budget, dependencies staged as Kaggle inputs.
paths:
  - "**/notebook/**"
  - "**/docs/plans/submission-checklist.md"
---

# Kaggle submission packaging

Kaggle Code Competitions score a notebook with **internet disabled** under a **runtime
cap** (commonly ≤ 9 h), and expect a specific output file. Package for offline scoring.

## Hard requirements

- Output file name must match the competition spec exactly (commonly `submission.csv`);
  header and columns must match `sample_submission.csv`.
- The scoring notebook runs with internet **off** — no model/data downloads at runtime.
- Stage every dependency as a Kaggle **input** (dataset or model):
  - base model weights and any trained adapter,
  - pip wheels, installed with `pip install --no-deps --no-index <wheel>`.
- Load everything from `/kaggle/input/...`; never call `from_pretrained(..., token=...)`
  or any network endpoint at runtime.

## Runtime discipline

- Inference over the hidden test set is usually the binding constraint, not training.
- Measure wall-clock on the example/public test slice before the full run; size batch,
  max-length, and quantization to fit the cap with margin.

## Before submitting

Run through `docs/plans/submission-checklist.md`. At minimum verify: row count matches
the test set, probabilities are valid (no NaN/negatives, rows sum to 1 where required),
no leakage features, and the offline notebook reproduces the local prediction.

> Project-specific packaging steps (exact package script, container, hardware) belong in
> the project's `docs/plans/` or an ADR — keep this rule competition-agnostic.
