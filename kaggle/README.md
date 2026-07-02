# kaggle

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**Author:** Mark Susol

A light, competition-agnostic harness for Kaggle projects. Deploys `kaggle-*` rules to
`~/.cline/rules/` (and `@-imports` them into `~/.claude/CLAUDE.md`), and ships a
project-scaffold skill plus helper commands — so each competition repo stays thin and
inherits the same discipline.

## Why

The hard-won conventions for running a Kaggle competition (notebook-via-CLI, offline
submission packaging, run/leaderboard tracking, a `docs/plans` layout) are the same
across competitions. This plugin packages that **Tier-2** layer once. Each project then
carries only its **Tier-3** specifics (hardware, exact package script, competition slug)
in its own `docs/plans/` — never a duplicated `CLAUDE.md` or `.clinerules/`.

## Requirements

Before running `/kaggle:new` or `/kaggle:preflight` against real Kaggle data:

1. **Pinned CLI packages** — install into the project's venv, not just a system Python:
   ```zsh
   pip install "kaggle>=1.8.0" "kagglehub>=0.4.1"
   ```
   `kaggle<1.8.0` predates token-based auth and will fail with a misleading
   `401 Unauthorized - Unauthenticated` even when credentials are otherwise valid. Check
   `kaggle --version` against whichever interpreter is actually on `PATH` — a project
   `requirements.txt` pin doesn't help if a stale system-wide install shadows it.

2. **`~/.kaggle/` credentials** — two files, both `chmod 600`:
   - `kaggle.json` — classic API key: `{"username": "...", "key": "..."}`
   - `access_token` — a bare single-line token (no JSON wrapper), used by newer
     token-based auth. Only present if the account has been set up for it.

   Verify auth works before scaffolding: `kaggle competitions files <slug>`.

## What it installs

| Component | Purpose |
|---|---|
| `src/rules/kaggle-project-structure.md` | Canonical `docs/plans` layout + leakage/citation conventions |
| `src/rules/kaggle-notebook-workflow.md` | `kaggle kernels push`, metadata as source of truth, no UI edits |
| `src/rules/kaggle-submission-packaging.md` | Offline notebook, exact submission filename, runtime budget, staged deps |
| `src/rules/kaggle-leaderboard.md` | Track every run's OOF / LB / takeaway |
| `src/kaggle-guard-hook.zsh` | PreToolUse hook — blocks Claude from pushing notebooks directly |
| `scripts/manage-settings.py` | Registers / removes the hook in `~/.claude/settings.json` |
| `skills/kaggle-project-scaffold` | Generate a barebones competition project skeleton |
| `commands/new.md` → `/kaggle:new` | Scaffold a new competition project |
| `commands/preflight.md` → `/kaggle:preflight` | Walk the submission checklist before pushing |

## kaggle-guard hook

Notebook pushes are irreversible and burn GPU quota — so this plugin intercepts any
attempt by Claude to run `kaggle kernels push` (or its shorthand `kaggle k push`) via
a `PreToolUse` hook. Claude is blocked and told to hand control back to you.

To push, run it yourself in the terminal:

```
! zsh scripts/push_notebook.sh <slug>
```

or

```
! kaggle kernels push -p <stage-dir>
```

The `!` prefix runs the command in your Claude Code session so its output is visible
in the conversation — you stay in the loop without context switching.

**Bypass sentinel:** If you explicitly want to grant Claude a one-time push, prepend
`KAGGLE_GUARD_SANCTIONED=1` to the command. The sentinel is visible in the Bash
command shown to you before execution — any bypass is auditable.

## Install

```zsh
./kaggle/deploy.zsh
```

Idempotent — safe to re-run after pulling updates. To remove:

```zsh
./kaggle/uninstall.zsh
```

## How it works

| Component | Purpose |
|---|---|
| `src/rules/` | Committed source of truth for the `kaggle-*` rule files |
| `src/kaggle-guard-hook.zsh` | Source for the PreToolUse hook installed to `~/.claude/scripts/` |
| `scripts/manage-settings.py` | Idempotent installer/remover for the hook entry in `~/.claude/settings.json` |
| `deploy.zsh` | Copies rules → `~/.cline/rules/`; regenerates `@-import` block in `~/.claude/CLAUDE.md`; installs hook; registers plugin |
| `collect.zsh` | Copies `~/.cline/rules/kaggle-*.md` → `src/rules/` for committing |
| `uninstall.zsh` | Removes rules, `@-import` block, hook script, and hook from `settings.json` |

This plugin owns the `kaggle-*` prefix and its own `kaggle-imports` sentinel block, so it
coexists cleanly with the `clinerules` plugin (`planning-*`) and any others.

## Usage

```
/kaggle:new <competition-slug> [project-root]   # scaffold a new project
/kaggle:preflight                               # verify a submission is ready
```

## Worked example

Scaffolding and downloading against a real competition,
[`playground-series-s6e7`](https://www.kaggle.com/competitions/playground-series-s6e7)
("Predicting Student Health Risk"):

```zsh
/kaggle:new playground-series-s6e7
zsh scripts/download_data.sh
```

`/kaggle:new` fills `competition-overview.md` with real data, then tailors
`implementation-plan.md`'s Rung 0-4 ladder to this competition's actual modality/task
(tabular classification here) instead of leaving it as generic boilerplate.

`download_data.sh` enforces competition-rule acceptance as a hard prerequisite. If the
rules haven't been accepted yet, it halts instead of failing on a raw API error:

```
HALTED: competition rules not yet accepted for playground-series-s6e7 (or you have not
joined the competition).
  1. Visit https://www.kaggle.com/competitions/playground-series-s6e7/rules
  2. Click "I Understand and Accept"
  3. Re-run: zsh scripts/download_data.sh
```

Once accepted, re-running produces:

```
kaggle-playground-series-s6e7/
  docs/plans/{competition-overview,implementation-plan,TODO,leaderboard,CITATIONS,
              submission-checklist,v0.1-baseline-plan}.md
  docs/adr/0001-offline-submission-packaging.md
  notebook/kernel-metadata.json     # enable_internet: false, competition_sources: [...]
  scripts/download_data.sh
  data/
    train.csv               690,088 rows x 15 cols (id, health_condition, ...features)
    test.csv                295,753 rows x 14 cols (id, ...features)
    sample_submission.csv   295,753 rows: id, health_condition
```

`health_condition` is a **categorical** target (e.g. `at-risk`), not a probability —
`docs/plans/submission-checklist.md` has a "Target format" section covering both cases,
since not every competition's `sample_submission.csv` expects class probabilities.
