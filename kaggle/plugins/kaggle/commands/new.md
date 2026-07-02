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
   `scaffold.py` with `--root`, `--slug`, a human `--title` derived from the slug, and
   `--author`. `--author` is **required** — it becomes the copyright holder in the
   generated `LICENSE`, and there is no default, so it is never silently wrong for
   whoever is actually running this. Determine it by running `git config user.name`
   (global, works even before the project directory is a repo); if that's unset, ask
   the user for a name before scaffolding.
3. Do **not** create a per-project `CLAUDE.md` or `.clinerules/` — global rules load from
   `~/.cline/rules/`.
4. After scaffolding, fetch the competition overview/rules and fill
   `docs/plans/competition-overview.md` (metric, data, deadlines, code-competition
   constraints), registering sources in `docs/plans/CITATIONS.md`.
5. Tailor `docs/plans/implementation-plan.md` to this specific competition — it is
   scaffolded with a generic Rung 0-4 strategy-ladder placeholder. Based on the data
   modality and task (tabular/NLP/vision/time-series, classification/regression),
   replace the placeholder rungs with real candidate approaches (e.g. Rung 1 = gradient
   boosting on tabular features, Rung 2 = a finetuned transformer, Rung 3 = the
   specific model family expected to be competitive) and note anything specific to this
   competition's data (leakage-prone columns, class imbalance, categorical vs.
   probability target format) that should shape the ladder.
6. Remind the user to place `~/.kaggle/kaggle.json`, accept the competition rules, then
   run `zsh scripts/download_data.sh`.
7. **Hard prerequisite gate — do not skip.** Accepting the competition rules is required
   before any data-dependent step (downloading, EDA, training) can proceed.
   `scripts/download_data.sh` itself enforces this: it attempts the download and halts
   with a clear message (exit code 1) if Kaggle's API rejects it — the rejection may come
   back as a bare `403 Forbidden` (newer `kaggle` CLI) or as text explicitly mentioning
   "rules" (older CLI), and the script matches both. Run the script and check its exit
   code — do not just assume success. If it halts, stop and wait for the user to accept
   the rules at the printed URL and re-run it; do not proceed to any later step (EDA,
   model work) until the script exits 0.
