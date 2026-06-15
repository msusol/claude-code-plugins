# claude-code-plugins

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**Author:** Mark Susol

Personal collection of [Claude Code](https://claude.ai/code) plugins.

## Plugins

| Plugin | Description |
|--------|-------------|
| [clinerules](clinerules/) | Symlinks `~/.clinerules/*` into the current project's `.clinerules/` and keeps the `@-import` block in `CLAUDE.md` in sync |
| [db-guard](db-guard/) | Two-layer guard against unauthorized `DROP TABLE`, `TRUNCATE`, `DROP DATABASE`, `DROP SCHEMA`, and `DROP COLUMN` |
| [git-guard](git-guard/) | Three-layer protection against unauthorized `git commit` and `git push` |
| [usage-statusline](usage-statusline/) | Status line showing model, context %, and subscription rate limits |

## Usage

Clone the repo, then run each plugin's installer:

```zsh
git clone https://github.com/msusol/claude-code-plugins.git
cd claude-code-plugins

./clinerules/deploy.zsh
./db-guard/deploy.zsh
./git-guard/deploy.zsh
./usage-statusline/deploy.zsh
```

All installers are idempotent — safe to re-run after pulling updates. To remove a plugin:

```zsh
./clinerules/uninstall.zsh
./db-guard/uninstall.zsh
./git-guard/uninstall.zsh
./usage-statusline/uninstall.zsh
```

## Known Behaviors

### Auto-memory + commit clinerule interaction

When testing these plugins in a project that has active clinerules (especially
`clinerules-commit-description.md`), you may see Claude spontaneously say something like
"save a memory about the db-guard pattern and commit." This is not the plugin acting —
it is two Claude Code behaviors colliding:

1. **Auto-memory** — Claude Code's built-in memory system writes `.md` files to
   `~/.claude/projects/.../memory/` when it encounters something it considers significant
   (such as a newly installed guard pattern or a schema it just inspected).
2. **Commit clinerule** — if `clinerules-commit-description.md` is active, Claude sees the new
   memory files as uncommitted changes and offers to commit them.

Neither behavior originates from the plugin itself. If this is unwanted, the commit
clinerule can be scoped to exclude the memory directory, or the auto-memory system can
be ignored for memory-file changes.

The auto-saved memory is often genuinely useful — Claude captures the *why* behind the
installation (the specific incident that prompted it, the project context, FK counts,
schema state) alongside the *how* (layers, sentinel, workflow). This project-scoped
memory then informs future sessions without needing to re-explain the setup.

Example auto-generated memory from a real db-guard install session
(`~/.claude/projects/<project>/memory/project_db_guard_installed.md`):

```markdown
---
name: project-db-guard-installed
description: db-guard plugin installed globally — protects against DROP TABLE/TRUNCATE/DROP SCHEMA with investigation-first workflow and DB_GUARD_SANCTIONED=1 sentinel
metadata:
  type: project
  originSessionId: 3f806397-a450-4e5a-8b3e-d1e25b29370d
---

db-guard plugin installed 2026-06-13. Mirrors git-guard pattern.

**Why:** User requested protection against accidental table drops (triggered by the
public.parcels issue where migration 060 was never applied and we nearly proposed
dropping a table with 8 FK references).

**Layers:**
- PreToolUse hook: `~/.claude/scripts/db-guard-hook.zsh`
- Clinerule: `~/.clinerules/dbguard-destructive-ops.md` — cognitive enforcement for Python-driven SQL
     (installed by db-guard/deploy.zsh; see db-guard/src/rules/dbguard-destructive-ops.md)
- Skill: `/db-drop` — the sanctioned investigation-first path

**Bypass sentinel:** `DB_GUARD_SANCTIONED=1 psql ... "DROP TABLE ..."` — required even
after verbal confirmation.

**Sanctioned workflow:** count rows → schema/FK audit → recovery check → present
findings → explicit confirm → execute with sentinel.
```
