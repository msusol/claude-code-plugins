# DGX Spark: Claude Code mouse settings in the PyCharm SSH terminal

When Claude Code runs on `spark-db62` inside PyCharm's SSH terminal, it captures the
mouse by default, which breaks native text selection and copy. Two env vars control
this, and they are easy to confuse.

## Rule

- Set `CLAUDE_CODE_DISABLE_MOUSE_CLICKS=1` (Claude Code 2.1.195 or later). It stops
  click, drag and hover capture, so selection and copy work, and keeps wheel scrolling.
- **Never set `CLAUDE_CODE_DISABLE_MOUSE=1`.** It turns off all mouse handling,
  including the wheel, and wins over `CLAUDE_CODE_DISABLE_MOUSE_CLICKS` when both are
  set. Claude Code then shows `Scroll wheel is sending arrow keys · use PgUp/PgDn to scroll`.
- Leave `CLAUDE_CODE_DISABLE_MOUSE` unset. `=0` only restates the default.

## Diagnosing the scroll message

If that message appears, check `env | grep CLAUDE_CODE_DISABLE` and
`grep CLAUDE_CODE ~/.bashrc`. A stale `CLAUDE_CODE_DISABLE_MOUSE=1` is the cause. Remove
the line, then open a new shell (or `unset CLAUDE_CODE_DISABLE_MOUSE`) and restart
Claude Code. Sourcing `~/.bashrc` alone does not clear an already-exported variable.

Found live 2026-11-01: `~/.bashrc` still carried the older `=1` line next to the
`_CLICKS` line.

## Not related

`ubuntu-spark-setup/mx-keys-macos-layout` remaps keys in the Spark's own GNOME session
only. It does not affect this, and does nothing over SSH from PyCharm on the Mac.
