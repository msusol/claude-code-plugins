---
name: commit
description: >
  Use this skill whenever the user wants to commit changes, stage files, push code, or save work to git.
  Trigger on: /commit, "commit my changes", "commit and push", "stage and commit", "save my work",
  "push this", "make a commit", "commit these changes", or any request to create a git commit.
  This is the ONLY sanctioned path for git write operations — it bypasses the shell wrapper
  that blocks unguided git commit/push calls, because it enforces explicit per-step confirmation.
version: 1.0.0
---

# Safe Commit Workflow

This skill walks through each stage of a git commit with explicit confirmation at every step.
It uses the real git binary directly (bypassing the `~/.local/bin/git` guard wrapper) because
this workflow IS the sanctioned, audited path — the wrapper exists to block unguided calls, not this skill.

Determine the real git path once at the start:

```bash
# Use the system git, not the wrapper
REAL_GIT=$(command -v -p git 2>/dev/null || echo /usr/bin/git)
```

Use `$REAL_GIT` in place of `git` for all commands in this workflow.

**For write operations** (`add`, `commit`, `push`, `tag`), prepend the
sanctioned-path sentinel `GIT_GUARD_SANCTIONED=1` so the PreToolUse hook
recognises the call originated from this audited workflow:

```bash
GIT_GUARD_SANCTIONED=1 $REAL_GIT push -u origin <branch>
```

Read-only commands (`status`, `diff`, `log`, `config`, `branch --show-current`,
`remote get-url`) do NOT need the sentinel — the hook only intercepts
`commit`/`push`/`tag`. The sentinel is intentionally visible in the
command shown to the operator before any write; that visibility is the
audit signal.

## Step 1 — Inspect the working tree

Run these in parallel and show the results:

```bash
$REAL_GIT status
$REAL_GIT diff --staged
```

If nothing is staged, also run:

```bash
$REAL_GIT diff
```

Present a clear summary: what is staged, what is unstaged, what is untracked.

## Step 2 — Stage files (if nothing is staged)

If `git diff --staged` is empty, ask the user which files to stage.
Offer specific choices based on the `git status` output — do not stage everything blindly with `git add .`.
Wait for explicit confirmation before running any `git add` commands.

Use `$REAL_GIT add <file>` for each file the user approves. The sentinel is not needed here — the hook does not intercept `git add`.

## Step 3 — Allowlist check

Run:

```bash
$REAL_GIT remote get-url origin 2>/dev/null
```

Read `~/.config/git-guard/allowlist` (one pattern per line, `#` lines are comments).
If the remote URL matches any pattern, proceed.
If it does not match — or if there is no remote — stop and tell the user:
- The current remote URL
- The allowlist location (`~/.config/git-guard/allowlist`)
- That they can add a pattern to the allowlist to approve this repo

Do NOT proceed past this step if the remote is not in the allowlist.

## Step 4 — Confirm attribution

Run:

```bash
$REAL_GIT config user.name
$REAL_GIT config user.email
```

Show the name and email. Ask the user to confirm this attribution is correct before continuing.
If they want to change it, help them update the git config before proceeding.

## Step 5 — Commit message

Ask the user for a commit message. Suggest one based on the staged diff if helpful.

Follow Conventional Commits format:
- Format: `type(optional scope): description`
- Types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`
- Body: optional bullet points explaining the main changes and why
- Footer: issue/PR references (e.g. `Closes #123`)

Append the Co-Authored-By trailer with the current Claude model version.

Show the full commit message to the user and ask for explicit confirmation before committing.

## Step 6 — Execute the commit

Only after the user explicitly confirms, pass the message via heredoc to preserve formatting:

```bash
GIT_GUARD_SANCTIONED=1 $REAL_GIT commit -m "$(cat <<'EOF'
<message here>
EOF
)"
```

Show the commit result (hash + subject line).

## Step 7 — Push decision

Ask the user: push now, or leave as a local commit?

If they want to push:
- Show the current branch: `$REAL_GIT branch --show-current`
- Show the configured remote: `$REAL_GIT remote -v`
- Confirm: "Push branch `<branch>` to `<remote>`?"
- Wait for explicit yes before running: `GIT_GUARD_SANCTIONED=1 $REAL_GIT push`

If the branch has no upstream yet, propose:

```bash
GIT_GUARD_SANCTIONED=1 $REAL_GIT push -u origin <branch>
```

Show the full command before executing it.

## Decision discipline

Never execute a write operation (add, commit, push, tag) without showing the exact command
to the user and receiving an explicit confirmation. "OK" or "yes" is sufficient, but silence
or ambiguity is not.

If at any step the user says stop, abort cleanly and report the current state of the working tree.
