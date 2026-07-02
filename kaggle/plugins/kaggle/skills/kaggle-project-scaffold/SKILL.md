---
name: kaggle-project-scaffold
description: Scaffold a barebones Kaggle competition project folder with a docs/plans structure (competition-overview, implementation-plan, versioned vX.Y plans, TODO, leaderboard, CITATIONS, submission-checklist), docs/adr + docs/investigate, scripts/, notebook/ with Kaggle kernel metadata, configs/, data/, README, requirements, and .gitignore. Use when the user wants to "start", "set up", "scaffold", or "bootstrap" a new Kaggle competition project, or asks for a barebones project skeleton for a competition. Does NOT generate CLAUDE.md or .clinerules (a separate Claude Code plugin owns those).
---

# Kaggle Project Scaffold

Bootstraps a consistent project skeleton for attacking a Kaggle competition,
derived from prior competition projects. The structure separates **planning docs**
(the source of truth) from **code** and **Kaggle packaging metadata**.

## When to use

Trigger when the user wants to begin a new Kaggle competition project — phrases like
"start a project for <competition>", "scaffold/bootstrap a barebones project",
"set up the folder structure for <competition>".

## What it creates

```
<project-root>/
  README.md                     competition link, goal, evaluator-constraints table, layout;
                                 MIT license badge + footer link back to this plugin
  LICENSE                       MIT, derived from this plugin's own LICENSE (--author, default
                                 "Mark Susol")
  .gitignore                    data + model artifacts + submission files
  requirements.txt              dev/EDA stack (note: heavy training in container/Spark)
  docs/
    plans/
      competition-overview.md   frozen rules, data, metric, deadlines
      implementation-plan.md    the strategy ladder (rung 0 → squeeze)
      v0.1-baseline-plan.md     first versioned plan
      TODO.md                   phased checklist, kept in sync with active plan
      leaderboard.md            one row per run: OOF / LB / takeaway
      CITATIONS.md              [cite:N] registry
      submission-checklist.md   pre-submit gate
    adr/                        NNNN-title.md decision records
    investigate/                investigation logs
    images/                     plots, dashboards
  scripts/
    download_data.sh            kaggle competitions download + unzip
  notebook/
    kernel-metadata.json        kaggle kernels push metadata (internet off)
  configs/                      training YAML
  data/                         train/test (gitignored)
```

Conventions carried over from prior projects:
- **Versioned plans** `vX.Y-<slug>-plan.md`; `TODO.md` mirrors the active plan.
- **`[cite:N]`** inline citations registered in `docs/plans/CITATIONS.md` (N = max + 1).
- **`leaderboard.md`** updated after every completed run + validation pass.
- Kaggle Code-Competition assumptions baked into templates: offline notebook,
  `submission.csv`, runtime cap.
- **Excluded on purpose:** `CLAUDE.md` and `.clinerules/` — a separate Claude Code
  plugin manages those. Do not create them.

## How to run

```zsh
python3 scripts/scaffold.py \
  --root "/path/to/Projects/Kaggle/kaggle-<slug>" \
  --slug "<competition-slug>" \
  --title "<Human Title>" \
  --metric "log loss" \
  --kaggle-user "<username>"
```

Flags:
- `--root` (required) destination project folder (created if missing).
- `--slug` (required) Kaggle competition slug (used in URLs, download script, kernel metadata).
- `--title` human-readable competition title for README/overview.
- `--metric` evaluation metric string (default: "score").
- `--kaggle-user` Kaggle username for `kernel-metadata.json` id (default: "USERNAME").
- `--author` copyright holder for the generated `LICENSE` file (default: "Mark Susol").
- `--force` overwrite existing files (default: skip files that already exist).

After scaffolding: fill `competition-overview.md` and `implementation-plan.md` with the
real rules/strategy, then `zsh scripts/download_data.sh`.

## Notes

- The script never overwrites existing files unless `--force` is passed, so it is safe
  to re-run to add any missing pieces.
- Templates use Code-Competition defaults (offline, `submission.csv`). For
  non-code competitions, edit `submission-checklist.md` and `kernel-metadata.json`
  (`enable_internet`) accordingly.
