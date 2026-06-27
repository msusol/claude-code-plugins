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
