# docs

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**Author:** Mark Susol

Deploys your global ruleset to `~/.claude/rules/`, Claude Code's own rules directory,
so your rules are available in every project without per-project setup. Claude Code-native
only — this plugin does not support Cline.

## Why

Claude Code loads `@`-imported files referenced from `~/.claude/CLAUDE.md` automatically in
every session — no symlinks, no per-project configuration. Keeping `src/rules/` as the
committed source of truth means you can edit rules, commit them, and deploy to a new
machine with a single command.

`deploy.zsh` copies `src/rules/*.md` into `~/.claude/rules/` and regenerates an `@-import`
block in `~/.claude/CLAUDE.md` pointing at those files, so every session picks them up
without you touching CLAUDE.md by hand.

## How it works

| Component | Purpose |
|---|---|
| `src/rules/` | Committed source of truth for your global rule files |
| `deploy.zsh` | Copies `src/rules/*.md` → `~/.claude/rules/`; regenerates `@-imports` in `~/.claude/CLAUDE.md` |
| `collect.zsh` | Copies `~/.claude/rules/planning-*.md` → `src/rules/` for committing |

### Global rules — no per-project setup

`~/.claude/rules/` is where this plugin installs your rule files; `~/.claude/CLAUDE.md`
`@-imports` pointing at those files give every Claude Code session, in every project,
identical coverage. Once you run `./deploy.zsh`, the rules are active everywhere with no
further setup needed.

## Prerequisites

- macOS or Linux
- Claude Code (desktop app, VS Code extension, or CLI)

## Install

```zsh
git clone <repo-url> docs
cd docs
./deploy.zsh
```

The installer is idempotent — safe to re-run after updates.

### What `deploy.zsh` does

1. Creates `~/.claude/rules/` if it does not exist
2. Copies `src/rules/*.md` to `~/.claude/rules/` (installs new files, updates changed ones)
3. Regenerates the `@-import` block in `~/.claude/CLAUDE.md` to point at `~/.claude/rules/`
4. Registers this repo as a Claude Code plugin marketplace and installs the `docs` plugin

## Keeping rules in sync

`src/rules/` is the committed source of truth for your rule files.

- **`./collect.zsh`** — copies `~/.claude/rules/planning-*.md` → `src/rules/` so you can commit changes.
- **`./deploy.zsh`** — copies `src/rules/*.md` → `~/.claude/rules/` (runs automatically on install; re-run after pulling updates).

Typical workflow after editing a rule:

```zsh
# 1. Edit ~/.claude/rules/some-rule.md directly
./collect.zsh        # pull changes into the repo
# commit and push
# on another machine: git pull && ./deploy.zsh
```

## Uninstall

```zsh
./uninstall.zsh
```

Removes the plugin's rule files from `~/.claude/rules/` and unregisters the plugin.

## Migrating off Cline

This plugin is Claude Code-native only — it no longer writes to `~/.cline/rules/`. If
you'd previously deployed an older, Cline-supporting version of this plugin (or
`git-guard`) on this machine, it may have left rule files behind under `~/.cline/rules/`.
Since Claude Code no longer reads from there, those files are dead weight — clean them up
by hand:

```zsh
rm -f ~/.cline/rules/planning-*.md ~/.cline/rules/git-branch-naming.md
```

Only remove the specific files above, not the whole `~/.cline/` directory — Cline itself
may still keep other config there if you use it for anything unrelated to these rules.
`~/.claude/rules/` and the `@-imports` in `~/.claude/CLAUDE.md` are the only things this
repo's plugins read from or write to going forward.

## Rule naming and load order

Rules use a `plugin-name-` prefix to identify ownership and avoid collisions across plugins.
`collect.zsh` scopes to `planning-*.md` so it only ever syncs files owned by this plugin —
files owned by other plugins in this repo (e.g. `dbguard-*.md` from [db-guard](../db-guard),
`git-branch-naming.md` from [git-guard](../git-guard)) are never touched.

When adding a new rule to this plugin, use the `planning-` prefix.

Claude Code loads all `@`-imported files in `~/.claude/CLAUDE.md` as a combined context —
order does not affect how rules are applied.

## Package layout

```
docs/
├── README.md
├── collect.zsh                             # Pull ~/.claude/rules/ into src/rules/ for committing
├── deploy.zsh                              # Installer
├── uninstall.zsh                           # Uninstaller
├── plugins/
│   └── docs/
│       └── .claude-plugin/
│           └── plugin.json                 # Plugin manifest
└── src/
    └── rules/                              # Committed rule files (source of truth)
        ├── planning-global.md
        └── ...
```

The top-level `.claude-plugin/marketplace.json` (one directory up, shared by all 5
plugins) declares this repo as a Claude Code plugin marketplace — it isn't nested inside
`docs/` itself.
