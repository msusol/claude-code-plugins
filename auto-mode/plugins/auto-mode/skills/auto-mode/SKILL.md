---
name: auto-mode
description: >
  Turn auto-mode on or off, show its status, or change its continuation cap. Trigger on:
  /auto-mode, "turn on auto mode", "work autonomously", "stop asking me and keep going",
  "turn off auto mode", "auto-mode status". When on, a Stop hook makes Claude continue with
  its own recommended next steps instead of stopping to ask.
version: 1.0.0
---

# auto-mode

The Stop hook in this plugin does the work; this skill only flips its switches. State lives in
`~/.config/auto-mode/` (or `$AUTO_MODE_DIR`):

| File | Meaning |
|---|---|
| `enabled` | exists -> auto-mode is on everywhere |
| `max` | integer cap on automatic continuations per user turn (default 8) |

Auto-mode is also on, with no flag file, whenever the session's directory is on an `exp/*` branch.

## Commands

Parse the argument (`on`, `off`, `status`, `max <N>`); with no argument, run `status`.

- **on** — `mkdir -p ~/.config/auto-mode && touch ~/.config/auto-mode/enabled`
- **off** — `rm -f ~/.config/auto-mode/enabled`
- **max N** — `mkdir -p ~/.config/auto-mode && echo N > ~/.config/auto-mode/max` (N must be a positive integer)
- **status** — report whether `enabled` exists, the current branch (`git branch --show-current`; `exp/*` means on), and the cap

After any change, say in one line what is now set. Do not change anything else.

## What auto-mode does NOT do

It does not grant permissions. git-guard, db-guard, `permissions.deny/ask` and approval prompts
still apply, and Claude is told not to push or take irreversible actions. To run unattended in
practice, pair it with `permissions.allow` rules for the commands you trust, and commit on an
`exp/*` branch (git-guard lets a plain `git commit` through there; see the git-guard README).

When Claude has nothing left to do it ends with `AUTO-MODE: DONE`; if it needs a human decision it
ends with `AUTO-MODE: BLOCKED`. Either one stops the loop.
