---
description: Run the Kaggle submission preflight — walk docs/plans/submission-checklist.md and verify the offline notebook is ready to push.
---

Run a Kaggle submission preflight for this project.

Steps:

1. Open `docs/plans/submission-checklist.md`. If it is missing, generate it from the
   `kaggle-submission-packaging` rule and the scaffold template.
2. Walk each item and verify against the actual notebook + artifacts:
   - Output filename + columns match `sample_submission.csv`.
   - Notebook `kernel-metadata.json` has `enable_internet: false`.
   - All weights/adapters/wheels are declared as Kaggle inputs and loaded from
     `/kaggle/input/...` (no runtime downloads, no HF tokens).
   - Predicted probabilities are valid (no NaN/negatives; rows sum to 1 where required)
     and row count matches the test set.
   - No leakage features (e.g. train-only identity columns) are used.
   - Full hidden-test runtime is within the competition cap (verified on the example set).
3. Report each item as pass / fail / unchecked. For any failure, state the concrete fix.
4. Only if all items pass, give the exact `kaggle kernels push` staging command (per the
   kaggle-notebook-workflow rule). Do not push automatically.
