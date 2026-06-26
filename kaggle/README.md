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
| `skills/kaggle-project-scaffold` | Generate a barebones competition project skeleton |
| `commands/new.md` → `/kaggle:new` | Scaffold a new competition project |
| `commands/preflight.md` → `/kaggle:preflight` | Walk the submission checklist before pushing |

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
| `deploy.zsh` | Copies `src/rules/kaggle-*.md` → `~/.cline/rules/`; regenerates the `kaggle-imports` `@-import` block in `~/.claude/CLAUDE.md`; registers the plugin |
| `collect.zsh` | Copies `~/.cline/rules/kaggle-*.md` → `src/rules/` for committing |
| `uninstall.zsh` | Removes the `kaggle-*` rules and the `kaggle-imports` block |

This plugin owns the `kaggle-*` prefix and its own `kaggle-imports` sentinel block, so it
coexists cleanly with the `clinerules` plugin (`planning-*`) and any others.

## Usage

```
/kaggle:new <competition-slug> [project-root]   # scaffold a new project
/kaggle:preflight                               # verify a submission is ready
```
