# claude-code-plugins

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**Author:** Mark Susol

Personal collection of [Claude Code](https://claude.ai/code) plugins.

## Plugins

| Plugin | Description |
|--------|-------------|
| [clinerules](clinerules/) | Deploys `planning-*` rules to `~/.cline/rules/` (Cline) and `~/.claude/CLAUDE.md` `@-imports` (Claude Code) — one rule file, both clients |
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

## Plugin design: rules vs rules + hook

Some plugins use only a rule file; others add a PreToolUse hook on top. The distinction is whether there is a runtime event worth intercepting.

**clinerules — rule only, no hook**

Clinerules is pure context injection. Rules are loaded into the model's context at session start via `~/.cline/rules/` (Cline, native) or `@-imports` in `~/.claude/CLAUDE.md` (Claude Code). There is no tool call to intercept — the rules are already present before any tool fires. A hook would have nothing to gate on; the rule file *is* the enforcement mechanism.

**db-guard — rule + PreToolUse hook**

Db-guard needs two layers because there are two distinct threat surfaces:

- SQL visible in the Bash command string (e.g. `psql -c "DROP TABLE ..."`) — caught by the hook at tool-use time, before execution.
- SQL inside Python scripts where the SQL is not in the command string — caught by the rule file, which defines the investigation-first workflow as a cognitive constraint.

The hook blocks the first class; the rule handles the second. Neither layer covers both cases alone.

**git-guard — the same pattern as db-guard**

Git-guard adds a hook for the same reason: `git commit` and `git push` are specific, interceptable Bash events. The hook blocks them at tool-use time; the rule file defines the sanctioned commit workflow.

The pattern is: if the risk is a specific runtime Bash event, add a hook. If the risk is a reasoning failure (wrong workflow, wrong sequence, missing verification), a rule is sufficient.

## Known Behaviors

### Auto-memory + commit rule interaction

When testing these plugins in a project that has active clinerules (especially
`planning-commit-description.md`), you may see Claude spontaneously say something like
"save a memory about the db-guard pattern and commit." This is not the plugin acting —
it is two Claude Code behaviors colliding:

1. **Auto-memory** — Claude Code's built-in memory system writes `.md` files to
   `~/.claude/projects/.../memory/` when it encounters something it considers significant
   (such as a newly installed guard pattern or a schema it just inspected).
2. **Commit rule** — if `planning-commit-description.md` is active, Claude sees the new
   memory files as uncommitted changes and offers to commit them.

Neither behavior originates from the plugin itself. If this is unwanted, the commit
commit rule can be scoped to exclude the memory directory, or the auto-memory system can
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
- Rule: `~/.cline/rules/dbguard-destructive-ops.md` — cognitive enforcement for Python-driven SQL
     (installed by db-guard/deploy.zsh; see db-guard/src/rules/dbguard-destructive-ops.md)
- Skill: `/db-drop` — the sanctioned investigation-first path

**Bypass sentinel:** `DB_GUARD_SANCTIONED=1 psql ... "DROP TABLE ..."` — required even
after verbal confirmation.

**Sanctioned workflow:** count rows → schema/FK audit → recovery check → present
findings → explicit confirm → execute with sentinel.
```
