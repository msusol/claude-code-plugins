---
description: Scaffold a new Kaggle competition project skeleton (docs/plans, scripts, notebook metadata) using the kaggle-project-scaffold skill.
argument-hint: <competition-slug> [project-root]
---

Scaffold a new Kaggle competition project.

Arguments: `$ARGUMENTS` (first token = Kaggle competition slug; optional second token =
destination project root).

Steps:

1. Parse the competition slug and optional root from the arguments. If no root is given,
   default to `kaggle-<slug>` under the current working directory.
2. Invoke the `kaggle-project-scaffold` skill to generate the skeleton. Run its
   `scaffold.py` with `--root`, `--slug`, and a human `--title` derived from the slug.
3. Do **not** create a per-project `CLAUDE.md` or `.clinerules/` — global rules load from
   `~/.cline/rules/`.
4. After scaffolding, fetch the competition overview/rules and fill
   `docs/plans/competition-overview.md` (metric, data, deadlines, code-competition
   constraints), registering sources in `docs/plans/CITATIONS.md`.
5. Remind the user to place `~/.kaggle/kaggle.json`, accept the competition rules, then
   run `bash scripts/download_data.sh`.
