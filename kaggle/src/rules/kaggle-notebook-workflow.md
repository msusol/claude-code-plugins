---
description: Manage Kaggle notebooks via the CLI (kaggle kernels push) with version-controlled metadata; never instruct manual Kaggle UI edits.
paths:
  - "**/notebook/**"
  - "**/kernel-metadata.json"
---

# Kaggle notebook workflow

All Kaggle notebook changes (code, metadata, kernel sources, dataset sources) are
managed via `kaggle kernels push` from the local machine. **Never instruct the user to
make changes manually in the Kaggle UI** — all configuration lives in version-controlled
metadata files.

## Notebook naming convention

Each competition phase or modelling method gets its own notebook and metadata file,
named after the version slug:

```
notebook/
  v0.1-tfidf-baseline.ipynb
  v0.1-tfidf-baseline-kernel-metadata.json
  v0.2-llama-qlora.ipynb
  v0.2-llama-qlora-kernel-metadata.json
```

- Slug format: `vX.Y-<short-method-description>` — matches the versioned plan name in
  `docs/plans/vX.Y-<slug>-plan.md`.
- Kernel title and `id` in the metadata file must also reflect the version
  (e.g. `gdataranger/llm-classification-finetuning-v01-tfidf`).
- Never reuse or overwrite a prior notebook; create a new file for each new method.
- Keep an investigation doc in `docs/investigate/` tracking run results, errors, and
  fixes for each notebook — one `##` section per slug.

## Push pattern

The CLI requires the metadata file to be named exactly `kernel-metadata.json`. Use
`scripts/push_notebook.sh <slug>` (if present in the project) or the manual pattern:

```zsh
STAGE="$(mktemp -d)"
cp notebook/<slug>.ipynb "$STAGE/"
cp notebook/<slug>-kernel-metadata.json "$STAGE/kernel-metadata.json"
kaggle kernels push -p "$STAGE"
```

## Metadata is the single source of truth

- `competition_sources`, `dataset_sources`, `model_sources` are declared in
  `kernel-metadata.json`, not added through the UI.
- `enable_internet: false` for any submission notebook (Code Competitions score offline).
- `enable_gpu: true` requests *a* GPU; the **specific GPU model cannot be set in
  metadata** and may need selection in the UI. Do not put `machine_shape` in the file —
  Kaggle treats it as read-only and may override the accelerator on push.
- After a `kernels push` that auto-starts a committed run on the wrong accelerator, stop
  it promptly so it does not burn quota; record any such project-specific accelerator
  quirk in the project's `docs/plans/` notes, not here.
