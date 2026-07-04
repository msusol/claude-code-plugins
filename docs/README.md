# docs

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**Author:** Mark Susol

Deploys your global ruleset to `~/.cline/rules/`, Cline's native global rules directory,
so your rules are available in every project without per-project setup.

## Why

Cline loads rules from `~/.cline/rules/` automatically in every session — no symlinks,
no per-project configuration. Keeping `src/rules/` as the committed source of truth
means you can edit rules, commit them, and deploy to a new machine with a single command.

`deploy.zsh` also regenerates `~/.claude/CLAUDE.md` with `@-import` lines pointing at
the same `~/.cline/rules/` files, so Claude Code loads identical rules from the same
copy. One rule file, two clients.

## Using Claude Code and Cline together

If you alternate between Claude Code and Cline — for example, switching to Cline when
Claude token limits are reached — you only want to maintain one copy of your rules.

This plugin achieves that with a single-source strategy:

```
src/rules/planning-global.md   ← committed source of truth
          │
          └─ deploy.zsh ──→  ~/.cline/rules/planning-global.md
                                   │                │
                             Cline reads it    @-import in ~/.claude/CLAUDE.md
                             (auto, native)    Claude Code reads it
```

Both clients see the same rules. To edit a rule:

1. Edit the file in `~/.cline/rules/` directly (both clients pick it up immediately).
2. Run `./collect.zsh` to pull the change into `src/rules/` for committing.

Or edit in `src/rules/`, commit, then run `./deploy.zsh` to push to `~/.cline/rules/`
and refresh the `~/.claude/CLAUDE.md` `@-import` block.

### Switching clients

| Situation | Client to use |
|---|---|
| Claude tokens available | Claude Code (`claude` CLI or IDE extension) |
| Claude tokens exhausted | Cline with an alternative model (e.g. Ollama, Gemini, OpenAI) |

Rules behave identically in both clients because they read from the same files.
The model changes; the behavioral guardrails do not.

## How it works

| Component | Purpose |
|---|---|
| `src/rules/` | Committed source of truth for your global rule files |
| `deploy.zsh` | Copies `src/rules/*.md` → `~/.cline/rules/`; regenerates `@-imports` in `~/.claude/CLAUDE.md` (auto-migrates the old `clinerules-imports` sentinel in place if found) |
| `collect.zsh` | Copies `~/.cline/rules/planning-*.md` → `src/rules/` for committing |
| `migrate-legacy-clinerules.zsh` | One-time cleanup for a pre-rename install — removes the old `clinerules@msusol` plugin registration, an orphaned marketplace entry, and a stale plugin cache directory that `deploy.zsh` can't reach |

### Global rules — no per-project setup

`~/.cline/rules/` is Cline's native global rules directory, loaded automatically in every
workspace. `~/.claude/CLAUDE.md` `@-imports` pointing at those same files give Claude Code
identical coverage. Once you run `./deploy.zsh`, both clients have the rules active
everywhere with no further setup needed.

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

1. Creates `~/.cline/rules/` if it does not exist
2. Copies `src/rules/*.md` to `~/.cline/rules/` (installs new files, updates changed ones)
3. Removes any legacy `##-prefixed` rule files left from a prior naming convention
4. Regenerates the `@-import` block in `~/.claude/CLAUDE.md` to point at `~/.cline/rules/`
5. Registers this repo as a Claude Code plugin marketplace and installs the `docs` plugin

## Keeping rules in sync

`src/rules/` is the committed source of truth for your rule files.

- **`./collect.zsh`** — copies `~/.cline/rules/planning-*.md` → `src/rules/` so you can commit changes.
- **`./deploy.zsh`** — copies `src/rules/*.md` → `~/.cline/rules/` (runs automatically on install; re-run after pulling updates).

Typical workflow after editing a rule:

```zsh
# 1. Edit ~/.cline/rules/some-rule.md directly
./collect.zsh        # pull changes into the repo
# commit and push
# on another machine: git pull && ./deploy.zsh
```

## Uninstall

```zsh
./uninstall.zsh
```

Removes the plugin's rule files from `~/.cline/rules/` and unregisters the plugin.

### Upgrading from the old `clinerules` plugin id

This plugin was renamed from `clinerules` to `docs`. `deploy.zsh`/`uninstall.zsh` already
detect and rewrite the `~/.claude/CLAUDE.md` sentinel block in place (old
`clinerules-imports` → current `docs-imports`) automatically, every time they run — no
extra step needed for that.

What they don't touch is Claude Code's own plugin-registration state, which doesn't
auto-follow a marketplace rename: a still-installed `clinerules@msusol` plugin, an
orphaned standalone `clinerules` marketplace entry, and a stale plugin cache directory.
Clean those up once with:

```zsh
./migrate-legacy-clinerules.zsh   # add --dry-run to preview first
./deploy.zsh                      # install docs@msusol and refresh the sentinel
```

Safe to run even if there's nothing to migrate — it just reports that.

## Rule naming and load order

Rules use a `plugin-name-` prefix to identify ownership and avoid collisions across plugins.
`collect.zsh` scopes to `planning-*.md` so it only ever syncs files owned by this plugin —
files from other plugins (e.g. `dbguard-*.md` from [db-guard](../db-guard)) are never touched.

When adding a new rule to this plugin, use the `planning-` prefix.

Cline loads all files in `~/.cline/rules/` as a combined context — order does not affect
how rules are applied.

## Package layout

```
docs/
├── README.md
├── collect.zsh                             # Pull ~/.cline/rules/ into src/rules/ for committing
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
