#!/usr/bin/env python3
"""Scaffold a barebones Kaggle competition project.

Derived from prior competition project layouts. Creates a docs/plans-centric
skeleton. Does NOT create CLAUDE.md or .clinerules (a Claude Code plugin owns those).

Usage:
    python3 scaffold.py --root <dir> --slug <comp-slug> --author A [--title T] [--metric M]
                        [--kaggle-user U] [--force]
"""
from __future__ import annotations
import argparse
import os
import re
from datetime import date
from pathlib import Path

DIRS = [
    "docs/plans",
    "docs/adr",
    "docs/investigate",
    "docs/images",
    "scripts",
    "notebook",
    "configs",
    "data",
]


def _license_text(author: str, year: int) -> str:
    """Derive the scaffolded project's LICENSE from this plugin's own LICENSE file
    (single source of truth for the MIT boilerplate), swapping in this project's
    copyright year/author."""
    plugin_root = Path(__file__).resolve().parents[3]  # plugins/kaggle/
    src = (plugin_root / "LICENSE").read_text()
    return re.sub(r"Copyright \(c\) \d{4} .+", f"Copyright (c) {year} {author}", src, count=1)


def tpl(slug: str, title: str, metric: str, user: str, author: str) -> dict[str, str]:
    url = f"https://www.kaggle.com/competitions/{slug}"
    year = date.today().year
    return {
        "LICENSE": _license_text(author, year),
        "README.md": f"""# {title}

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

{url}

_One-line problem statement here._

## Goal

_What you are building and the target outcome._

## Status

| Item | Value |
|---|---|
| Metric | {metric} |
| Baseline to beat | _tbd_ |
| Current best | _see docs/plans/leaderboard.md_ |

## Evaluator constraints (Code Competition defaults)

| Constraint | Value | Implication |
|---|---|---|
| Runtime | <= 9 h | Budget inference, not just training |
| Internet | disabled | Bundle weights/wheels as Kaggle inputs |
| Output | `submission.csv` | Exact filename + header |
| External data | allowed | Pretrained models permitted |

## Layout

```
docs/   plans, adr, investigate, images
scripts/  download_data.sh, ...
notebook/ Kaggle kernel + kernel-metadata.json
configs/  training YAML
data/     train/test (gitignored)
```

## Quick start

```zsh
zsh scripts/download_data.sh      # needs ~/.kaggle/kaggle.json + accepted rules
```

See `docs/plans/implementation-plan.md` for the strategy ladder.

---

Scaffolded by the [kaggle plugin](https://github.com/msusol/claude-code-plugins/tree/main/kaggle)
for Claude Code.
""",
        ".gitignore": """.env
.venv/
output/
__pycache__/
*.pyc
*.egg-info/
.cache/
.ipynb_checkpoints/
.DS_Store
.idea/

# Competition data
data/train.csv
data/test.csv
data/sample_submission.csv
data/*.jsonl
data/folds/
data/features/

# Model artifacts
adapters/**/*.safetensors
adapters/**/*.bin
checkpoints/
submission.csv
submission.zip
""",
        "requirements.txt": """# Dev / EDA stack. Heavy training typically runs in a GPU container.
pandas>=2.0
numpy>=1.26
scikit-learn>=1.4
pyarrow>=15.0
tqdm>=4.66
PyYAML>=6.0
kaggle>=1.8.0
kagglehub>=0.4.1
""",
        "docs/plans/competition-overview.md": f"""# Competition Overview

## Objective

_Describe the task._[cite:1]

## Metric

**{metric}** — _floor / must-beat value here._[cite:1]

## Data

| File | Rows | Columns |
|---|---|---|
| `train.csv` | _?_ | _?_ |
| `test.csv` | _? (hidden)_ | _?_ |
| `sample_submission.csv` | - | _?_ |

## Code competition requirements

- Notebook <= 9 h run-time.[cite:1]
- Internet disabled during scoring.[cite:1]
- Public external data + pretrained models allowed.[cite:1]
- Submission file named `submission.csv`.[cite:1]

## Timeline / format

_Deadlines or rolling-leaderboard notes._[cite:1]
""",
        "docs/plans/implementation-plan.md": """# Implementation Plan - Strategy Ladder

Each rung yields a valid `submission.csv` + a CV score, so a working offline pipeline
exists before adding model complexity.

## Rung 0 - Pipeline skeleton
- Download data; emit a trivial/uniform submission; confirm it scores at the floor.

## Rung 1 - Cheap baseline
- Simple features + a fast model. Validate CV harness + submission format.

## Rung 2 - Stronger model
- _e.g. a finetuned transformer; confirm runtime fits 9 h._

## Rung 3 - Contender
- _The model that wins; see versioned plan vX.Y._

## Rung 4 - Squeeze
- Ensemble, TTA, calibration.

## Cross-validation
- 5-fold stratified; trust CV->LB correlation.

## Offline submission (do early)
1. Upload weights/adapter/wheels as Kaggle inputs.
2. Notebook: internet off, load from /kaggle/input/..., write submission.csv.
""",
        "docs/plans/v0.1-baseline-plan.md": """# v0.1 - Baseline Plan

Goal: lock the offline submission pipeline and CV harness with a cheap model.

## Steps
1. `zsh scripts/download_data.sh`.
2. EDA: target balance, key distributions, leakage checks.
3. Simple features + fast model, 5-fold.
4. Predict test, write `submission.csv`, verify header + row count.

## Acceptance
- CV beats the trivial floor.
- Offline notebook produces a valid `submission.csv`.
- Record CV/LB in leaderboard.md.
""",
        "docs/plans/TODO.md": """# TODO

## Phase 0 - Setup
- [ ] ~/.kaggle/kaggle.json present
- [ ] `zsh scripts/download_data.sh` exits 0 (halts + prints a rules-acceptance URL if
      the competition rules haven't been accepted yet — accept them and re-run)
- [ ] Trivial submission scores at the floor (sanity)

## Phase 1 - Baseline (v0.1)
- [ ] EDA
- [ ] Baseline model + 5-fold CV
- [ ] First offline submission; record in leaderboard.md

## Phase 2+ - Stronger models
- [ ] _fill from implementation-plan.md_
""",
        "docs/plans/leaderboard.md": """# Leaderboard

Update after **every** completed run + validation pass. OOF = out-of-fold CV.

| Version | Model | Key change | OOF | Kaggle LB | Notes |
|---|---|---|---|---|---|
| floor | - | trivial baseline | - | - | must-beat |
| v0.1 | - | baseline feats | _tbd_ | _tbd_ | plumbing |

## Run log
_(append dated entries: config, OOF, LB, takeaway)_
""",
        "docs/plans/CITATIONS.md": f"""# Citations

Inline references use `[cite:N]`. N = max existing + 1; never reuse.

| N | Source | URL |
|---|---|---|
| 1 | {title} - competition overview | {url}/overview |
""",
        "docs/plans/submission-checklist.md": """# Submission Checklist

## File format
- [ ] File named exactly `submission.csv`.
- [ ] Header + columns match sample_submission.csv.
- [ ] One row per test id; row count matches test set.
- [ ] No NaN / invalid values.

## Target format (check the one that applies)
- [ ] **Categorical / hard label:** predicted values are an exact string/value match to
      the categories used in sample_submission.csv (case, spelling, no unseen labels).
- [ ] **Probability / soft label:** no NaN or negatives; rows sum to 1 where multiple
      class-probability columns are expected.

## Offline / environment
- [ ] Notebook `enable_internet=false`.
- [ ] All weights/wheels loaded from /kaggle/input/... (no downloads).

## Runtime
- [ ] Full hidden-test run verified < 9 h (measure on example set first).

## Modeling sanity
- [ ] CV recorded in leaderboard.md and beats current best.
- [ ] No leakage features used.
""",
        "docs/adr/0001-offline-submission-packaging.md": """# 0001 - Offline submission packaging

## Status
Accepted

## Context
Code Competition: scoring notebook runs with internet disabled and a runtime cap,
and must emit `submission.csv`.[cite:1]

## Decision
Stage all dependencies (weights, adapters, wheels) as Kaggle inputs; load offline.

## Consequences
- No network calls at runtime.
- Runtime becomes the binding constraint -> batched/quantized inference.
""",
        "scripts/download_data.sh": f"""#!/usr/bin/env zsh
# Download competition data. Requires ~/.kaggle/kaggle.json and accepted rules.
#
# Rule acceptance is a hard prerequisite: Kaggle refuses to serve any competition
# file until you've clicked "I Understand and Accept" on the competition's rules
# page. This script halts with clear instructions instead of a raw API error if
# that hasn't happened yet.
set -euo pipefail

COMP="{slug}"
DEST="$(cd "$(dirname "$0")/.." && pwd)/data"
mkdir -p "$DEST"

STDERR_LOG="$(mktemp)"
if ! kaggle competitions download -c "$COMP" -p "$DEST" 2> "$STDERR_LOG"; then
  # kaggle CLI 2.x returns a bare "403 Client Error: Forbidden" for this endpoint with
  # no mention of "rules" — older 1.x CLIs spelled out "You must accept this
  # competition's rules...". Match both since either can show up depending on version.
  if grep -qiE "rules|403|forbidden" "$STDERR_LOG"; then
    echo ""
    echo "HALTED: competition rules not yet accepted for $COMP (or you have not"
    echo "joined the competition)."
    echo "  1. Visit https://www.kaggle.com/competitions/$COMP/rules"
    echo "  2. Click \\"I Understand and Accept\\""
    echo "  3. Re-run: zsh scripts/download_data.sh"
    rm -f "$STDERR_LOG"
    exit 1
  fi
  cat "$STDERR_LOG" >&2
  rm -f "$STDERR_LOG"
  exit 1
fi
rm -f "$STDERR_LOG"

unzip -o "$DEST/${{COMP}}.zip" -d "$DEST"
rm -f "$DEST/${{COMP}}.zip"

echo "Downloaded to $DEST:"
ls -lh "$DEST"
""",
        "notebook/kernel-metadata.json": f"""{{
  "id": "{user}/{slug}-submission",
  "title": "{title} - Submission",
  "code_file": "submission.ipynb",
  "language": "python",
  "kernel_type": "notebook",
  "is_private": true,
  "enable_gpu": true,
  "enable_internet": false,
  "dataset_sources": [],
  "competition_sources": [
    "{slug}"
  ],
  "model_sources": []
}}
""",
        "configs/.gitkeep": "",
        "data/.gitkeep": "",
        "docs/investigate/.gitkeep": "",
        "docs/images/.gitkeep": "",
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--slug", required=True)
    ap.add_argument("--title", default=None)
    ap.add_argument("--metric", default="score")
    ap.add_argument("--kaggle-user", default="USERNAME")
    ap.add_argument("--author", required=True, help="Copyright holder for LICENSE")
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()

    title = args.title or args.slug.replace("-", " ").title()
    root = Path(args.root).expanduser()

    for d in DIRS:
        (root / d).mkdir(parents=True, exist_ok=True)

    files = tpl(args.slug, title, args.metric, args.kaggle_user, args.author)
    created, skipped = [], []
    for rel, content in files.items():
        path = root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        if path.exists() and not args.force:
            skipped.append(rel)
            continue
        path.write_text(content)
        created.append(rel)

    dl = root / "scripts/download_data.sh"
    if dl.exists():
        os.chmod(dl, 0o755)

    print(f"Scaffolded: {root}")
    print(f"  created ({len(created)}): " + ", ".join(sorted(created)))
    if skipped:
        print(f"  skipped existing ({len(skipped)}): " + ", ".join(sorted(skipped)))
    print("Next: fill competition-overview.md + implementation-plan.md, then "
          "`zsh scripts/download_data.sh`.")


if __name__ == "__main__":
    main()
