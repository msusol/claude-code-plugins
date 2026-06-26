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

## Push pattern

The CLI requires the metadata file to be named exactly `kernel-metadata.json`. Keep a
descriptive source name in the repo and copy it to a staging dir on push:

```zsh
STAGE="$(mktemp -d)"
cp notebook/<name>.ipynb "$STAGE/"
cp notebook/<name>-kernel-metadata.json "$STAGE/kernel-metadata.json"
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
