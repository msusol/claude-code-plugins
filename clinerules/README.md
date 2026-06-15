# clinerules

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Symlinks your global `~/.clinerules/*` ruleset into any project's `.clinerules/` directory
and keeps the `@-import` block in `~/.claude/CLAUDE.md` in sync.

## Why

Claude Code loads per-project rules from `.clinerules/`. Maintaining a separate copy in
every repo means edits to your global rules don't propagate automatically. This plugin
creates symlinks instead of copies, so every project always reflects the current state
of `~/.clinerules/`.

## How it works

| Component | Purpose |
|---|---|
| `src/link-clinerules.sh` | The linker — creates symlinks and updates `CLAUDE.md` |
| `~/.claude/scripts/link-clinerules.sh` | Where `deploy.zsh` installs it |
| `/install-clinerules` skill | The Claude Code skill that calls the linker for the current project |

### `link-clinerules.sh`

For each file in `~/.clinerules/`:

1. Creates a symlink at `<project-root>/.clinerules/<filename>` pointing to the global file.
2. Skips files already linked (pass `--force` to overwrite).
3. Skips real files (not symlinks) to avoid overwriting manual edits.

After symlinking, it regenerates the `@-import` block in `~/.claude/CLAUDE.md` to match
the current contents of `~/.clinerules/`. The block is delimited by sentinel markers so
edits outside it are preserved.

### `/install-clinerules` skill

Invoked by `/install-clinerules` or natural language ("link clinerules", "set up clinerules",
"sync clinerules") from any Claude Code session. The skill:

1. Confirms the project root (`$PWD` by default).
2. Runs `~/.claude/scripts/link-clinerules.sh "$PWD"`.
3. Reports how many rules were linked vs. skipped.
4. Verifies the `.clinerules/` directory with `ls -la`.

## Prerequisites

- macOS or Linux
- Claude Code (desktop app, VS Code extension, or CLI)

## Install

```zsh
git clone <repo-url> clinerules
cd clinerules
./deploy.zsh
```

The installer is idempotent — safe to re-run after updates.

### What deploy.zsh does

1. Copies `src/link-clinerules.sh` to `~/.claude/scripts/link-clinerules.sh`
2. Copies `src/rules/*.md` to `~/.clinerules/` (installs missing files; updates changed ones)
3. Registers this repo as a Claude Code plugin marketplace and installs `clinerules`

> **Note:** Running `claude plugin install clinerules@clinerules` alone is not sufficient.
> The skill calls `~/.claude/scripts/link-clinerules.sh`, which only `deploy.zsh` installs.
> Always run `./deploy.zsh` as the single install step.

### After install

Restart Claude Code to pick up the `/install-clinerules` skill.

### First-time setup

On a fresh machine, `~/.claude/CLAUDE.md` may not yet have the `@-import` block that
tells Claude Code to load your rules. Run `/install-clinerules` once from any project
after restarting — the script bootstraps `~/.claude/CLAUDE.md` automatically:

| State of `~/.claude/CLAUDE.md` | What the script does |
|---|---|
| Does not exist | Creates it with a `## Cline Project Rules` header and the full `@-import` block |
| Exists, sentinel markers present | Replaces only the managed block, preserving everything else |
| Exists, no sentinels | Wraps any existing bare `@~/.clinerules/` lines in sentinels, or appends the block if none are found |

After this one-time run, Claude Code loads all rules from `~/.clinerules/` in every
session globally — no further per-project setup needed for the rules themselves.

## Using the skill

From any project in Claude Code:

- `/install-clinerules`
- "link clinerules"
- "set up clinerules"
- "sync clinerules"

To overwrite existing symlinks (e.g. after adding new rules to `~/.clinerules/`):

- "force link clinerules"
- "re-sync clinerules"

Or run the script directly:

```zsh
~/.claude/scripts/link-clinerules.sh [project-root]
~/.claude/scripts/link-clinerules.sh --force [project-root]
```

## Uninstall

```zsh
./uninstall.zsh
```

Removes `~/.claude/scripts/link-clinerules.sh` and unregisters the plugin. Existing
`.clinerules/` symlinks in projects are left untouched.

## Rule numbering

Rules are numbered `NN-name.md` to control load order. Some slots are reserved by other
plugins and will not appear in `src/rules/` — they are listed in `.collectignore`:

| Slot | File | Owner |
|---|---|---|
| 15 | `15-db-guard.md` | [db-guard](../db-guard) plugin |

When adding a new rule, pick the next unused number after the highest existing one.

## Keeping rules in sync

`src/rules/` is the committed source of truth for your global rule files.

- **`./collect.zsh`** — copies `~/.clinerules/*.md` → `src/rules/` so you can commit changes.
- **`./deploy.zsh`** — copies `src/rules/*.md` → `~/.clinerules/` (runs automatically on install; re-run after pulling updates).

Typical workflow after editing a rule:

```zsh
# 1. Edit ~/.clinerules/some-rule.md
./collect.zsh        # pull changes into the repo
# commit and push
# on another machine: git pull && ./deploy.zsh
```

## Package layout

```
clinerules/
├── README.md
├── collect.zsh                             # Pull ~/.clinerules/ into src/rules/ for committing
├── deploy.zsh                              # Installer
├── uninstall.zsh                           # Uninstaller
├── .claude-plugin/
│   └── marketplace.json                    # Declares this repo as a plugin marketplace
├── plugins/
│   └── clinerules/
│       ├── .claude-plugin/
│       │   └── plugin.json                 # Plugin manifest
│       └── skills/
│           └── install-clinerules/
│               └── SKILL.md               # /install-clinerules skill definition
└── src/
    ├── link-clinerules.sh                  # Linker script (source — deployed to ~/.claude/scripts/)
    └── rules/                              # Committed rule files (source of truth)
        ├── 01-global.md
        └── ...
```
