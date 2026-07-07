# kaggle

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**Author:** Mark Susol

A light, competition-agnostic harness for Kaggle projects. Deploys `kaggle-*` rules once
to your **Kaggle workspace root** — the parent directory holding all your competition
projects (`<workspace-root>/.cline/rules/`, `@-imported` into `<workspace-root>/CLAUDE.md`)
— and ships a project-scaffold skill plus helper commands, so every competition beneath
that root inherits the same discipline without duplicating rules into each one.

## Why

The hard-won conventions for running a Kaggle competition (notebook-via-CLI, offline
submission packaging, run/leaderboard tracking, a `docs/plans` layout) are the same
across competitions. This plugin packages that **Tier-2** layer once, at the workspace
root — not globally (it would pollute unrelated, non-Kaggle projects) and not per
competition (that would duplicate the same rules into every competition folder). Each
competition project then carries only its **Tier-3** specifics (hardware, exact package
script, competition slug) in its own `docs/plans/` — never a duplicated `CLAUDE.md` or
`.cline/rules/`.

The `kaggle-guard` PreToolUse hook is the one exception: it stays registered globally
(`~/.claude/settings.json`), since it's cheap, project-agnostic guard logic that already
scopes its effect by matching `Bash` command content (`kaggle kernels push`) rather than
by directory.

## Requirements

This plugin depends on the `docs` plugin (declared in `plugin.json`) — Claude Code
installs it automatically alongside `kaggle`. The `kaggle-*` rules this plugin deploys
assume the `planning-*` rules (`docs/plans/` layout, TODO sync, etc.) are already in
place; `kaggle-project-structure.md` builds directly on `planning-docs-plans.md`.

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
| `src/rules/kaggle-dgx-spark.md` | DGX Spark GB10 conventions — service pausing, `tmux`-only training sessions |
| `src/rules/kaggle-discussions.md` | Read competition Discussion threads via the `kaggle` CLI, not browser automation |
| `src/rules/kaggle-kernel-alerts.md` | SMS alert watcher pattern for long-running kernel completion |
| `src/kaggle-guard-hook.zsh` | PreToolUse hook — blocks Claude from pushing notebooks directly |
| `scripts/manage-settings.py` | Registers / removes the hook in `~/.claude/settings.json` (global) |
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
./kaggle/deploy.zsh <workspace-root>
```

`<workspace-root>` is the parent directory holding your Kaggle competition projects
(e.g. `~/LosusAI/Projects/Kaggle/`) — defaults to `$PWD` if omitted. Run it once per
workspace, not once per competition; it's idempotent, so re-running it later (e.g. after
pulling rule updates, or before scaffolding another competition under the same workspace)
is always safe. To remove:

```zsh
./kaggle/uninstall.zsh <workspace-root>
```

### Upgrading from a pre-workspace-scoping install

If you installed this plugin before workspace-scoping existed, you have a legacy global
install: `kaggle-*.md` rules in `~/.cline/rules/` and a `kaggle-imports` block in the
global `~/.claude/CLAUDE.md`. The new `uninstall.zsh` won't clean this up on its own — it
looks for `<target-root>/CLAUDE.md` directly, not the legacy `~/.claude/CLAUDE.md` path.
Retire the old global footprint once, then deploy fresh to your real workspace root:

```zsh
./kaggle/migrate-legacy-global.zsh   # add --dry-run to preview first
./kaggle/deploy.zsh <workspace-root>
```

`migrate-legacy-global.zsh` only touches the legacy global rule files and CLAUDE.md
block — it leaves the `kaggle-guard` hook and its `settings.json` registration alone
(those stay global regardless of workspace scoping). Safe to run even if there's nothing
to migrate; it just reports that.

## How it works

| Component | Purpose |
|---|---|
| `src/rules/` | Committed source of truth for the `kaggle-*` rule files |
| `src/kaggle-guard-hook.zsh` | Source for the PreToolUse hook installed to `~/.claude/scripts/` (global) |
| `scripts/manage-settings.py` | Idempotent installer/remover for the hook entry in `~/.claude/settings.json` (global) |
| `deploy.zsh <target-root>` | Copies rules → `<target-root>/.cline/rules/`; regenerates `@-import` block in `<target-root>/CLAUDE.md`; installs the hook (global); registers plugin |
| `collect.zsh <target-root>` | Copies `<target-root>/.cline/rules/kaggle-*.md` → `src/rules/` for committing |
| `uninstall.zsh <target-root>` | Removes rules and `@-import` block from `<target-root>`; removes the hook script and its `settings.json` entry (global) |
| `migrate-legacy-global.zsh` | One-time cleanup for a pre-workspace-scoping install — removes the legacy global `~/.cline/rules/kaggle-*.md` and `~/.claude/CLAUDE.md` block that `uninstall.zsh` can't reach |

## Keeping rules in sync

`src/rules/` in **this plugin repo** is the committed source of truth — not the copies
deployed into your Kaggle workspace. Unlike the `docs` plugin (always global, so
`deploy.zsh`/`collect.zsh` default to `$HOME` with no path to think about), kaggle's
workspace root is a **different directory** from this plugin repo, so both commands need
the workspace-root argument regardless of which directory you're actually standing in:

```zsh
# 1. Edit a rule directly at the deployed location, e.g.:
#    ~/LosusAI/Projects/Kaggle/.cline/rules/kaggle-notebook-workflow.md
# 2. Pull the change back into this plugin repo for committing — run from anywhere,
#    pointing at the workspace root:
/path/to/claude-code-plugins/kaggle/collect.zsh ~/LosusAI/Projects/Kaggle
# 3. Review the diff in kaggle/src/rules/, then commit + push from this repo.
# 4. On another machine (or to pick up someone else's rule change): git pull, then
/path/to/claude-code-plugins/kaggle/deploy.zsh ~/LosusAI/Projects/Kaggle
```

Or edit `src/rules/kaggle-*.md` directly in this repo, commit, then run `deploy.zsh
<workspace-root>` to push the change out to the workspace.

`collect.zsh` scopes to `kaggle-*.md` so it only ever syncs files owned by this plugin —
rules from other plugins deployed into the same workspace (if any) are never touched.

Everything except the `kaggle-guard` hook is scoped to `<target-root>` — point it at your
Kaggle workspace root. **This only reliably reaches Claude Code, not Cline:**

- **Claude Code** is expected to inherit the rules in every competition subdirectory via
  its directory walk-up (loading the nearest `CLAUDE.md` toward `/`, not stopped by git
  boundaries) — based on documented behavior, though not independently re-confirmed in a
  live session.
- **Cline does NOT inherit these automatically** if each competition directory is its own
  git repo (as it is in this project's real workspace layout) — confirmed live: opening
  Cline inside a competition subdirectory and checking Workspace Rules (the scale icon)
  does not show the workspace-root `.cline/rules/` files. Cline's project-rules resolution
  appears to scope to the nearest repo root, and stops at the competition folder's own
  `.git` boundary rather than walking further up into the shared workspace. Asking Cline
  directly "what rules apply" can surface them anyway, since the assistant will go read
  the filesystem on request — but that's not the same as automatic context loading.

If you need Cline to load these automatically, either open Cline from the workspace root
itself (not from inside a competition subdirectory), or duplicate/symlink the rule files
into each competition's own `.cline/rules/` — the latter reintroduces the per-competition
duplication this design was meant to avoid, so it's a real tradeoff, not a clean fix.

This plugin owns the `kaggle-*` prefix and its own `kaggle-imports` sentinel block, so it
coexists cleanly with the `docs` plugin (`planning-*`, which stays **global** — it's
genuinely cross-project) and any others — and requires `docs` to be installed (see
`dependencies` in `plugins/kaggle/.claude-plugin/plugin.json`).

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
(tabular classification here) instead of leaving it as generic boilerplate. It also
deploys the `kaggle-*` rules to the shared workspace root (the parent directory of the
scaffolded project) the first time a competition is scaffolded there — later competitions
under the same workspace inherit the rules automatically, with no repeated deploy step.

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
  notebooks/kernel-metadata.json    # enable_internet: false, competition_sources: [...]
  scripts/download_data.sh
  data/
    train.csv               690,088 rows x 15 cols (id, health_condition, ...features)
    test.csv                295,753 rows x 14 cols (id, ...features)
    sample_submission.csv   295,753 rows: id, health_condition
```

`health_condition` is a **categorical** target (e.g. `at-risk`), not a probability —
`docs/plans/submission-checklist.md` has a "Target format" section covering both cases,
since not every competition's `sample_submission.csv` expects class probabilities.
