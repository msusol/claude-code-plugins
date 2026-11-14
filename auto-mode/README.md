# auto-mode

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**Author:** Mark Susol

A Stop hook that makes Claude Code carry on with its own recommended next steps instead of stopping
to ask — a more autonomous mode, with a hard cap and an off switch.

## How it works

When Claude finishes a turn, the hook (`plugins/auto-mode/hooks/auto-continue.zsh`) checks whether
auto-mode is on. If so, it blocks the stop and sends Claude back with a fixed message: continue with
your recommended next steps; don't push, don't run destructive commands, don't bypass any guard.

On when **either**:

- `~/.config/auto-mode/enabled` exists (`/auto-mode on`), or
- the session's directory is on an `exp/*` git branch (see git-guard's experiment branches).

Stops when **any** of:

- Claude ends its message with `AUTO-MODE: DONE` (finished) or `AUTO-MODE: BLOCKED` (needs a human);
- the cap is reached — 8 continuations per user turn by default; `/auto-mode max N`, the `max` file, or `AUTO_MODE_MAX`;
- you type something new (the counter resets on every user turn).

It fails open: without `jq`, or on bad input, Claude just stops normally.

## What it does not do

It grants no permissions. Approval prompts, `permissions.deny/ask`, git-guard and db-guard apply
unchanged. For fewer prompts, add `permissions.allow` rules for commands you trust (tests, linters,
`git add`, `git diff`) in project `.claude/settings.json`. Pushes stay gated by `/git-push`.

## Install

```zsh
./deploy.zsh      # registers the losus-ai marketplace and installs auto-mode
```

Restart Claude Code afterwards. Requires `jq`.

## Use

```
/auto-mode on        # flag file on: auto-mode everywhere
/auto-mode off
/auto-mode status
/auto-mode max 12
```

Or skip the flag and work on an `exp/*` branch. A/B example: two worktrees, `exp/ab-sonnet` and
`exp/ab-fable`, one model each; both commit freely and keep going, and you diff the branches at the end.

## Tests

```zsh
zsh tests/test-auto-continue.zsh
```
