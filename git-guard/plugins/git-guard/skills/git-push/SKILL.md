---
name: git-push
description: >
  Use this skill whenever the user wants to push commits to a remote. Trigger on:
  /git-push, "push this", "push my changes", "push to origin", "push the commit(s)",
  or any request to push. This is the ONLY sanctioned path for git push — it bypasses
  the shell wrapper that blocks unguided push calls, because it enforces explicit
  confirmation for every single push. It does NOT commit — if there is nothing to
  push yet (no local commits ahead of the remote), tell the user to use the
  git-commit skill first.
version: 1.0.0
---

# Safe Push Workflow

This skill runs once per push, with its own explicit confirmation — it is never bundled
into the commit workflow. Every push, no matter how small, goes through this skill.

It uses the real git binary directly (bypassing the `~/.local/bin/git` guard wrapper)
because this workflow IS the sanctioned, audited path — the wrapper exists to block
unguided calls, not this skill.

Determine the real git path once at the start:

```bash
REAL_GIT=$(command -v -p git 2>/dev/null || echo /usr/bin/git)
```

Use `$REAL_GIT` in place of `git` for all commands in this workflow. The push itself
requires the sanctioned-path sentinel so the PreToolUse hook lets it through:

```bash
GIT_GUARD_SANCTIONED=1 $REAL_GIT push
```

Read-only commands (`status`, `log`, `branch --show-current`, `remote get-url`,
`remote -v`) do NOT need the sentinel.

## Step 1 — Confirm there is something to push

```bash
$REAL_GIT status -sb
$REAL_GIT log @{u}..HEAD --oneline 2>/dev/null
```

If the branch has no upstream, or shows 0 commits ahead, tell the user there is
nothing to push and stop. Do not push an empty no-op. If there is nothing staged
or committed at all, point the user to the `git-commit` skill instead.

## Step 2 — Allowlist check

```bash
$REAL_GIT remote get-url origin 2>/dev/null
```

Read `~/.config/git-guard/allowlist` (one pattern per line, `#` lines are comments).
If the remote URL matches any pattern, proceed. If it does not match — or there is no
remote — stop and tell the user:
- The current remote URL
- The allowlist location (`~/.config/git-guard/allowlist`)
- That they can add a pattern to approve this repo

Do NOT proceed past this step if the remote is not in the allowlist.

## Step 3 — Confirm the push

Show:

```bash
$REAL_GIT branch --show-current
$REAL_GIT remote -v
```

List the specific commits about to be pushed (from Step 1's `log` output). Ask
explicitly: "Push branch `<branch>` to `<remote>` (`<N>` commit(s): `<short list>`)?"
Wait for an explicit yes — "OK" or "yes" is sufficient, silence or ambiguity is not.

## Step 4 — Execute

Only after explicit confirmation:

```bash
GIT_GUARD_SANCTIONED=1 $REAL_GIT push
```

If the branch has no upstream yet, use instead:

```bash
GIT_GUARD_SANCTIONED=1 $REAL_GIT push -u origin <branch>
```

Show the full command before executing it, then show the push result.

## Decision discipline

Never push without showing the exact command and receiving explicit confirmation for
*this specific push* — a prior confirmation (e.g. from a `git-commit` run earlier in
the conversation) does not carry over. Each push gets its own gate.

If at any step the user says stop, abort cleanly and report the current state
(branch, ahead/behind count) without pushing.
