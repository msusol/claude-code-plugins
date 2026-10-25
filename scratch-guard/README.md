# scratch-guard

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**Author:** Mark Susol

A PreToolUse hook that blocks scratch/test scripts from being materialized
as standalone files in a shared system temp directory (`/tmp`,
`/private/tmp`, `/var/folders`) outside a Claude Code session's own
scratchpad subdirectory.

## Why

A scratch test script left at a top-level `/tmp` path sits outside any
session sandbox, visible to other users and processes on the machine and to
any endpoint-security tooling independently of the tool that wrote it. It
is also easy to forget and leaves clutter in a shared directory. The risk
compounds when the script's own content looks obfuscated, most commonly a
base64 decode-into-exec pattern (`base64 -d` piped into
`exec`/`eval`/`sh -c`/`python3 -c`), a textbook malware signature even when
the intent is entirely benign, such as working around nested shell-quoting
when building a remote `--command` string.

Claude Code gives every session its own scratchpad directory (a
`.../scratchpad/` subdirectory); scratch files belong there.

## What it blocks

1. A script-looking file (`.sh`/`.zsh`/`.bash`/`.py`/`.pl`/`.rb`/
   `.command`) written directly under a temp dir, outside a
   `.../scratchpad/` subdirectory — via shell redirection (`>`, `>>`,
   `tee`) in a `Bash` call, or directly via the `Write` tool.
2. Any file, anywhere, whose content embeds a base64 decode-into-exec
   pattern.

## What it does NOT block

- Plain, non-executable drafts under top-level `/tmp` — e.g. the
  `planning-dm-pbcopy.md` workflow's `/tmp/<name>.txt` DM/Slack drafts.
  Those are a sanctioned, everyday use of `/tmp` and are left alone.
- Anything written inside a session's own
  `.../scratchpad/` subdirectory.
- Script files written to a real project/repo path (not a temp dir) —
  e.g. committing `scripts/verify-grant.sh` to a repo is
  unaffected, even though that script legitimately contains a base64
  encode/decode step as part of its real, reviewed function.

## Bypass

A `Bash` command prefixed with `SCRATCH_GUARD_SANCTIONED=1 ` is treated as
a deliberate, explained override (mirrors `git-guard`'s sentinel). The
sentinel is intentionally visible in the command the operator confirms —
any bypass shows up in the rendered Bash command. The `Write` tool has no
shell prefix to carry a bypass; write to the scratchpad path instead.

## Install

```zsh
zsh deploy.zsh
```

Idempotent — safe to re-run. Registers:

- `~/.claude/scripts/scratch-guard-hook.zsh`
- A `scratch-guard@losus-ai` plugin install (via the shared
  `losus-ai` marketplace, registered once for this whole repo)
- Two `PreToolUse` hook entries in `~/.claude/settings.json` (matchers
  `Bash` and `Write`), both pointing at the same hook script

## Uninstall

```zsh
zsh uninstall.zsh
```
