---
description: Canonical folder layout and doc conventions for a Kaggle competition project (docs/plans, versioned plans, leaderboard, citations). Use the kaggle-project-scaffold skill to generate it.
paths:
  - "**/docs/plans/competition-overview.md"
  - "**/docs/plans/leaderboard.md"
  - "**/notebook/kernel-metadata.json"
---

# Kaggle competition project structure

A Kaggle competition project keeps **planning docs as the source of truth**, separate
from code and from Kaggle packaging metadata. Generate the skeleton with the
`kaggle-project-scaffold` skill rather than hand-creating folders.

## Canonical layout

```
docs/
  plans/
    competition-overview.md   frozen rules, data, metric, deadlines
    implementation-plan.md    the strategy ladder (rung 0 → squeeze)
    vX.Y-<slug>-plan.md       versioned plans
    TODO.md                   phased checklist, synced with the active plan
    leaderboard.md            one row per run: OOF / LB / takeaway
    CITATIONS.md              [cite:N] registry
    submission-checklist.md   pre-submit gate
  adr/                        NNNN-title.md decision records
  investigate/                investigation logs
scripts/                      download_data.sh, convert/train/infer helpers
notebook/                     Kaggle kernel .ipynb + kernel-metadata.json
configs/                      training config (YAML)
data/                         competition data (gitignored)
```

## Conventions

- **Versioned plans** are named `vX.Y-<slug>-plan.md`; keep `docs/plans/TODO.md` in
  sync with the active plan.
- **Citations** use `[cite:N]` inline, registered in `docs/plans/CITATIONS.md`
  (see the kaggle-leaderboard and project citation rules; N = max existing + 1).
- **Never use `model_*` identity columns as features** if they exist in train but not
  test — that is leakage. They are valid for CV stratification and analysis only.
- Do **not** create a per-project `CLAUDE.md` or `.clinerules/`; global rules are loaded
  from `~/.cline/rules/`. Project-specific facts (hardware, packaging quirks) go in
  `docs/plans/` or an ADR, not in a duplicated rules file.
