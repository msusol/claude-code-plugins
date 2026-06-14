# db-guard

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Two-layer protection against unauthorized `DROP TABLE`, `TRUNCATE`, `DROP DATABASE`,
`DROP SCHEMA`, and `ALTER TABLE … DROP COLUMN` by Claude Code.

Mirrors the [git-guard](../git-guard) pattern exactly.

## Why

Claude Code can execute destructive SQL autonomously — sometimes before the human has
verified what is in a table. A DB restore is expensive and not always possible.
This package closes that gap using two independent defenses.

| Layer | Mechanism | Bypassed by |
|---|---|---|
| PreToolUse hook | Intercepts `DROP TABLE` / `TRUNCATE` in Bash tool calls before they run | Nothing — fires before tool executes |
| Clinerule `15-db-guard.md` | Cognitive enforcement for Python-driven SQL; defines investigation-first workflow | Nothing — always applies |
| `/db-drop` skill | Sanctioned path through both layers, with per-step confirmation | Both layers, by design — with explicit confirmation |

## How it works

### Layer 1 — PreToolUse hook (`~/.claude/scripts/db-guard-hook.zsh`)

Registered in `~/.claude/settings.json`. Fires before every Bash tool call.
If the command contains `DROP TABLE`, `DROP DATABASE`, `DROP SCHEMA`, `TRUNCATE <table>`,
or `ALTER TABLE … DROP COLUMN`, the hook blocks the call (exit 2) and tells Claude to
use the `/db-drop` skill instead.

**Bypass sentinel:** prepend `DB_GUARD_SANCTIONED=1 ` to the command. The sentinel is
only produced by the `/db-drop` skill after the user explicitly confirms — it is
intentionally visible in the command string shown before execution.

This layer fires before the Bash tool runs — it cannot be bypassed by approving a
permission prompt.

**Scope:** only intercepts SQL patterns visible in the Bash command string (e.g.,
`psql -c "DROP TABLE ..."`). For Python-driven SQL, Layer 2 (the clinerule) is
the enforcement layer.

### Layer 2 — Clinerule (`~/.clinerules/15-db-guard.md`)

Loaded into every Claude Code session. Defines the investigation-first workflow
and applies it to ALL destructive SQL, including Python-driven operations where
the SQL is not visible in the Bash command string.

### `/db-drop` skill — the sanctioned path

The only way through both layers. Invoked with `/db-drop` or natural language
("drop this table", "truncate the table", "apply this destructive migration").

Workflow at each step — all with explicit confirmation before any destructive write:

1. Identify the target and operation
2. Count rows and sample 5 rows from the table
3. Audit column schema, inbound foreign keys, and views that reference it
4. State explicitly what is irreversibly lost and whether recovery is possible
5. Present a summary block and ask for explicit confirmation
6. Execute with `DB_GUARD_SANCTIONED=1` prefix to pass the hook
7. Verify the drop with `SELECT to_regclass('<schema>.<table>')`

## Prerequisites

- macOS or Linux
- Claude Code (desktop app, VS Code extension, or CLI)
- Python 3

## Install

```zsh
git clone <repo-url> db-guard
cd db-guard
./deploy.zsh
```

The installer is idempotent — safe to re-run after updates.

### What deploy.zsh does

1. Copies `src/db-guard-hook.zsh` to `~/.claude/scripts/db-guard-hook.zsh`
2. Copies `src/clinerule-15-db-guard.md` to `~/.clinerules/15-db-guard.md`
3. Merges the PreToolUse hook entry into `~/.claude/settings.json`
4. Registers this repo as a Claude Code plugin marketplace and installs `db-guard`

### After install

Restart Claude Code to load the new hook and pick up the `/db-drop` skill.

## Using the /db-drop skill

In any Claude Code session, say:

- `/db-drop`
- "drop this table"
- "truncate the leads table"
- "apply this destructive migration"

Claude will walk through the investigation-first workflow, stopping for confirmation
at each step.

## Narrow exceptions (no workflow required)

The following operations are not guarded:

- `DROP INDEX` — reversible (index can be rebuilt from the table)
- `DROP TABLE IF EXISTS <tmp_*>` — clearly temporary tables
- A migration that drops and immediately recreates the same table in a single transaction

Even for exceptions, state what is being dropped before running.

## Uninstall

```zsh
./uninstall.zsh
```

## Package layout

```
db-guard/
├── README.md
├── deploy.zsh                         # Installer
├── uninstall.zsh                      # Uninstaller
├── .claude-plugin/
│   └── marketplace.json               # Declares this repo as a plugin marketplace
├── plugins/
│   └── db-guard/
│       ├── .claude-plugin/
│       │   └── plugin.json            # Plugin manifest
│       └── skills/
│           └── db-drop/
│               └── SKILL.md          # /db-drop sanctioned path skill
├── src/
│   ├── db-guard-hook.zsh              # PreToolUse hook (source)
│   └── clinerule-15-db-guard.md       # Clinerule (source — deployed to ~/.clinerules/)
└── scripts/
    └── manage-settings.py             # Idempotent settings.json merge + uninstall
```
