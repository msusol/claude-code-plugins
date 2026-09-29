# dgx-spark

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**Author:** Mark Susol

Host-specific Claude Code rules for `spark-db62` (the DGX Spark GB10 workstation).
Deploys `dgx-spark-*` rules **globally** to `~/.claude/rules/`, `@-imported` into
`~/.claude/CLAUDE.md` — every session on this host loads them regardless of which
project or workspace is open.

## Why global, not workspace-scoped

Unlike the `kaggle` plugin (workspace-scoped, since Kaggle conventions only matter
inside a Kaggle workspace), the facts this plugin captures are about the **machine
itself** — which Docker daemon is authoritative, what AppArmor will and won't let a
root shell touch, which container serves which shared dependency. Those are true no
matter which project you're sitting in on `spark-db62`: `ColoradoLandPartners`,
`LosusAIOps`, `Kaggle`, or anything added later. A workspace-scoped rule would mean
re-deploying (and re-syncing edits to) the same content into every one of those
workspace roots separately — global is the correct scope here, the same reasoning
that keeps the `docs` plugin's `planning-*` rules global.

## Origin

Written up live 2026-09-28 after a real incident: the DGX Spark's active Docker CLI
context had silently been switched to `desktop-linux` (Docker Desktop's own daemon),
making the entire real production stack (`ollama-server`, `mattermost`, `clp-db`,
etc. — all running fine under the native `default` context) look like it had never
been brought up. This caused a real pipeline failure (`clp-foreclosure-pipeline.service`)
and nearly caused an unnecessary outage — a believed-rogue bare-metal process was
actually a healthy container, and only Docker's own AppArmor confinement (blocking a
raw `sudo kill -9` from outside Docker's management path) prevented killing it. See
`src/rules/dgx-spark-docker-context.md` for the full diagnostic tell and rule.

## What it installs

| Component | Purpose |
|---|---|
| `src/rules/dgx-spark-docker-context.md` | Two Docker daemons/contexts on this host (`default` vs `desktop-linux`) — how to tell which one you're on, and why a raw `kill -9` on a Docker-confined PID always fails |
| `src/rules/dgx-spark-heavy-compute-jobs.md` | Host-level facts for running any heavy compute job here — the shared-host OOM risk, pausing background Docker services first, `tmux`-only long-running sessions |

## Install

```zsh
./dgx-spark/deploy.zsh
```

No target-root argument — this plugin is global, like `docs`. Idempotent; safe to
re-run after pulling rule updates. To remove:

```zsh
./dgx-spark/uninstall.zsh
```

## How it works

| Component | Purpose |
|---|---|
| `src/rules/` | Committed source of truth for the `dgx-spark-*` rule files |
| `deploy.zsh` | Copies rules → `~/.claude/rules/`; regenerates the `dgx-spark-imports` `@-import` block in `~/.claude/CLAUDE.md`; registers plugin |
| `collect.zsh` | Copies `~/.claude/rules/dgx-spark-*.md` → `src/rules/` for committing |
| `uninstall.zsh` | Removes rules and the `@-import` block from `~/.claude/CLAUDE.md` |

## Keeping rules in sync

```zsh
# 1. Edit a rule directly at the deployed location, e.g.:
#    ~/.claude/rules/dgx-spark-docker-context.md
# 2. Pull the change back into this plugin repo for committing:
./dgx-spark/collect.zsh
# 3. Review the diff in dgx-spark/src/rules/, then commit + push from this repo.
# 4. On another machine that shares this host (or after someone else's edit):
git pull
./dgx-spark/deploy.zsh
```

Or edit `src/rules/dgx-spark-*.md` directly in this repo, commit, then run
`deploy.zsh` to push the change out to `~/.claude/rules/`.

This plugin owns the `dgx-spark-*` prefix and its own `dgx-spark-imports` sentinel
block, so it coexists cleanly with `docs` (`planning-*`), `git-guard`
(`git-branch-naming.md`), and any other plugin deployed globally on this host.

## Related: kaggle plugin

`Kaggle/.claude/rules/kaggle-dgx-spark.md` (deployed by the `kaggle` plugin,
workspace-scoped, depends on `dgx-spark`) covers what's specific to a Kaggle
project's training runs on this host: the `scripts/services.sh` /
`.paused_containers` automation implementing this plugin's pause/resume
convention, and progress-reporting discipline for long-running scripts. The
host-level facts it used to duplicate — the OOM risk, pausing background
Docker services, `tmux`-only sessions — were pulled out into
`dgx-spark-heavy-compute-jobs.md` here, so any other project doing heavy
compute on this host gets them without re-deriving or duplicating the Kaggle
version.
