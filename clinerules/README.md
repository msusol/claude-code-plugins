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
- `~/.clinerules/` populated with your global rule files

## Install

```zsh
git clone <repo-url> clinerules
cd clinerules
./deploy.zsh
```

The installer is idempotent — safe to re-run after updates.

### What deploy.zsh does

1. Copies `src/link-clinerules.sh` to `~/.claude/scripts/link-clinerules.sh`
2. Registers this repo as a Claude Code plugin marketplace and installs `clinerules`

> **Note:** Running `claude plugin install clinerules@clinerules` alone is not sufficient.
> The skill calls `~/.claude/scripts/link-clinerules.sh`, which only `deploy.zsh` installs.
> Always run `./deploy.zsh` as the single install step.

### After install

Restart Claude Code to pick up the `/install-clinerules` skill.

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

## Package layout

```
clinerules/
├── README.md
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
    └── link-clinerules.sh                  # Linker script (source — deployed to ~/.claude/scripts/)
```
