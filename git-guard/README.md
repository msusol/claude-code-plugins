# git-guard

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Three-layer protection against unauthorized `git commit` and `git push` by Claude Code.

## Why

Claude Code can commit and push autonomously — sometimes without explicit permission,
especially with `skipAutoPermissionPrompt: true` in settings. This package closes those gaps
using defenses at three independent levels, so no single failure opens the door.

| Layer | Mechanism | Bypassed by |
|---|---|---|
| Shell wrapper | OS-level, shadows `git` binary in PATH | Nothing — fires before any process |
| PreToolUse hook | Claude Code intercepts before Bash tool executes | Nothing — fires before tool runs |
| Deny rules | Absolute floor on dangerous patterns | Nothing — enforced by Claude Code runtime |
| `/commit` skill | Sanctioned path through all guards | All guards, by design — with per-step confirmation |

## How it works

### Layer 1 — Shell wrapper (`~/.local/bin/git`)

A `zsh` script placed ahead of `/usr/bin/git` in `PATH`. When Claude (or any process) runs
`git commit`, `git push`, or `git tag`, the wrapper intercepts it and checks `~/.config/git-guard/allowlist`.
If the current repo's remote URL doesn't match an approved pattern, it exits non-zero with a clear message.
All read-only operations (`status`, `diff`, `log`, etc.) pass through to the real git untouched.

This layer fires at the OS level — it cannot be bypassed by approving a permission prompt.

### Layer 2 — PreToolUse hook

Registered in `~/.claude/settings.json`. Fires before every Bash tool call Claude makes.
If the command contains `git commit`, `git push`, or `git tag`, the hook blocks the tool call
and tells Claude to use the `/commit` skill instead. This gives Claude a clear error message
early, before the shell wrapper even runs.

### Layer 3 — Deny rules

`~/.claude/settings.json` → `permissions.deny` — a list of patterns Claude Code refuses
to execute regardless of context:

- Dangerous Bash: `git push`, `git init`, `gh repo create`, `rm -rf`
- Secrets: `.env`, `*.pem`, `*.key`, `.ssh/**`
- Shell configs: `.zshrc`, `.zprofile`, `.bash_profile`
- Build artifacts, logs, vendor directories, IDE configs

These rules are enforced by the Claude Code runtime itself.

### `/commit` skill — the sanctioned path

The only way through all three guards. Invoked by `/commit` or natural language
("commit my changes", "stage and commit", "commit and push").

Workflow at each step — all with explicit confirmation before any write:

1. Show `git status` + `git diff --staged`; offer to stage files if nothing is staged
2. Check remote URL against `~/.config/git-guard/allowlist` — stop if not approved
3. Show `git config user.name` + `user.email` — confirm attribution
4. Prompt for commit message (Conventional Commits format)
5. Show the full message and ask for confirmation before committing
6. Ask whether to push; confirm branch + remote before executing

The skill uses the real git binary directly (bypassing the wrapper) because this
workflow is the intentional, audited path. The wrapper guards against unguided calls.

## Prerequisites

- macOS or Linux
- Claude Code (desktop app, VS Code extension, or CLI)
- `~/.local/bin` in your `PATH` ahead of `/usr/bin` (standard on macOS; see note below)
- Python 3

**PATH note:** The shell wrapper must shadow the real `git`. Verify with:

```zsh
which git
# Should show: /Users/yourname/.local/bin/git
```

If `~/.local/bin` is not in your PATH, add this to `~/.zshrc`:

```zsh
export PATH="$HOME/.local/bin:$PATH"
```

## Install

```zsh
git clone <repo-url> git-guard
cd git-guard
./deploy.zsh
```

The installer is idempotent — safe to re-run if you update the package.

### What deploy.zsh does

1. Detects the real git binary (`/usr/bin/git`, `/usr/local/bin/git`, or `/opt/homebrew/bin/git`)
2. Installs the wrapper to `~/.local/bin/git` with the correct real git path substituted
3. Installs the PreToolUse hook to `~/.claude/scripts/git-guard-hook.zsh`
4. Creates `~/.config/git-guard/allowlist` from the template (skips if it already exists)
5. Registers the git-guard repo as a Claude Code plugin marketplace (`claude plugin marketplace add <repo-dir>`) and installs the `git-guard` plugin from it (`claude plugin install git-guard@git-guard`). This auto-enables `/commit` in every new Claude Code session — no manual `/plugin enable` step.
6. Merges hooks + deny rules into `~/.claude/settings.json` without clobbering existing settings.
7. Best-effort removes any earlier-style installs (skill dropped inside the official marketplace, or copied into the user-skills dir) so the plugin is the single canonical source of `/commit`.

### After install

1. **Edit the allowlist** — `~/.config/git-guard/allowlist` is empty by default. Add your approved remote URL patterns before making any commits.
2. **Restart Claude Code** to load the new hook and pick up the plugin's `/commit` skill.

### Updating after pulling changes

After pulling changes from the repo, re-run the installer to be safe:

```zsh
./deploy.zsh
```

Then restart Claude Code to pick up the changes.

### Updating, disabling, uninstalling the plugin

The plugin uses Claude Code's standard plugin tooling, so day-to-day management is the same as any other plugin:

```zsh
claude plugin list                    # confirm git-guard is installed
claude plugin update git-guard        # pull latest from the repo dir
claude plugin disable git-guard       # circuit-breaker: removes /commit;
                                      # combined with the hook + wrapper this
                                      # locks the session out of git writes
claude plugin enable git-guard        # re-enable
claude plugin uninstall git-guard     # remove (deploy.zsh handles this too)
```

## Configuring the allowlist

`~/.config/git-guard/allowlist` — one substring pattern per line. Comments start with `#`.

```
# Approve all repos in your org
github.com/your-org

# Approve personal forks
github.com/yourname

# Approve an internal GitLab instance
gitlab.your-company.com
```

A remote URL is approved if it contains any pattern. The check applies to `git commit`,
`git push`, and `git tag`. If a repo has no remote `origin`, all write ops are blocked.

## Using the commit skill

In any Claude Code session, say:

- `/commit`
- "commit my changes"
- "stage and commit"
- "commit and push"

Claude will walk through the workflow described above, stopping for confirmation at each step.

## Customizing deny rules

The deny list is in `~/.claude/settings.json` under `permissions.deny`. To remove a rule
that causes friction — for example, `.vscode/**` blocking editor config reads — delete
that line from the array.

To add project-level overrides without touching the global deny list, create
`.claude/settings.json` in the project root:

```json
{
  "permissions": {
    "allow": ["Read(./.vscode/**)", "Read(./**/*.csv)"]
  }
}
```

## Testing

Unit tests for the PreToolUse hook are in `tests/test-git-guard-hook.zsh`.

```zsh
zsh tests/test-git-guard-hook.zsh
```

The suite covers:

- Bare `git commit / push / tag` — blocked (exit 2)
- `GIT_GUARD_SANCTIONED=1 git commit / push / tag` — sentinel bypasses hook (exit 0)
- Sentinel with leading whitespace — still bypasses
- Heredoc commit message with sentinel — still bypasses
- Read-only commands (`git status`, `git add`, `git diff`, `git log`, etc.) — allowed
- Malformed / empty JSON input — allowed (no false positives)
- Sentinel without required trailing space — still blocked

The grep/sed fallback path (used when `jq` is unavailable) is tested automatically
when `jq` lives in an isolated directory (e.g. MacPorts at `/opt/local/bin`). It is
skipped with a `SKIP` message when `jq` is in a shared system directory (`/usr/bin`)
where stripping it from `PATH` would break other tools the hook depends on.

## Uninstall

```zsh
./uninstall.zsh
```

Removes the wrapper, hook, skill, and git-guard entries from `~/.claude/settings.json`.
The allowlist (`~/.config/git-guard/allowlist`) is preserved.

## Files installed

| Path | Purpose |
|---|---|
| `~/.local/bin/git` | Shell wrapper |
| `~/.claude/scripts/git-guard-hook.zsh` | PreToolUse hook |
| `~/.config/git-guard/allowlist` | Allowlist (not removed on uninstall) |
| `~/.claude/settings.json` | Modified in place (hooks + deny rules merged) |
| Claude Code plugin registry | `git-guard` marketplace + plugin registered via the `claude plugin` CLI; files stay in this repo |

## Package layout

```
git-guard/
├── README.md
├── deploy.zsh                     # Installer
├── uninstall.zsh                  # Uninstaller
├── .claude-plugin/
│   └── marketplace.json           # Declares this repo as a single-plugin marketplace
├── plugins/
│   └── git-guard/
│       ├── .claude-plugin/
│       │   └── plugin.json        # Plugin manifest
│       └── skills/
│           └── commit/
│               └── SKILL.md       # Claude commit skill definition
├── src/
│   ├── git-wrapper.zsh            # Shell wrapper source (REAL_GIT substituted at install)
│   ├── git-guard-hook.zsh         # PreToolUse hook
│   └── allowlist.template         # Blank allowlist template
├── tests/
│   └── test-git-guard-hook.zsh    # Unit tests for the PreToolUse hook
└── scripts/
    └── manage-settings.py         # Idempotent settings.json merge + uninstall
```
