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

## Telling Claude the stop protocol up front (`SessionStart`)

The Stop hook only speaks after Claude's first turn ends, and its message says "carry on with your next steps". A model that finished the asked-for work without the `AUTO-MODE: DONE` marker was
therefore sent on to its own next steps; after a planning phase that means implementing. So a prompt had to say "end with `AUTO-MODE: DONE`" itself. `plugins/auto-mode/hooks/session-protocol.zsh` (a
`SessionStart` hook) adds the protocol to the session's context from turn 1: do not ask for confirmation at each step; do what was asked up to the stopping point the request or the project rules set
(for example "stop after the documents and report"); reaching that point is finishing, so do not carry on past it or widen the task; finish with `AUTO-MODE: DONE` and a 2-line summary, or
`AUTO-MODE: BLOCKED` with what you need. (An earlier wording said "carry on without asking first", which a dump-only test showed overrode a rule's stop gate: the arm kept going and built the engine.) It is on whenever auto-mode is on; turn it off with `AUTO_MODE_PROTOCOL=off` or a file `~/.config/auto-mode/protocol` containing `off`. It only adds
context, grants nothing, and fails open (no `jq` or bad input adds nothing).

## Answering questions when nobody is there (`AskUserQuestion`)

The Stop hook only nudges Claude to continue. A model can still open the interactive question form (`AskUserQuestion`) and wait for a person, which stalls an unattended run.
In the leave-engine A/B runs Sonnet 5.5 never asked, while Fable 5.2 asked three owner-decision questions and stopped. A second hook,
`plugins/auto-mode/hooks/auto-answer.zsh` (a `PreToolUse` hook on `AskUserQuestion`), answers for it: for each question it picks the option labelled `(Recommended)`
(all of them for a multi-select, the first option if none is marked) and logs the answer to `~/.config/auto-mode/ask-log.jsonl`.

- **When:** auto-mode is on **and** the ask policy is not `off`. Policy comes from `AUTO_MODE_ASK` or the file `~/.config/auto-mode/ask`: `recommended`, `first` or `off`.
  Default: `recommended` on an `exp/*` branch; `off` when only the flag file turned auto-mode on, so on a real project you must opt in.
- **How it answers** (`AUTO_MODE_ASK_MODE`): `answers` (default) pre-fills the tool's `answers`, so the form never opens; `deny` refuses the call and puts the answers in the message.
- **These are not human decisions.** The message tells Claude to say so in its commit. Auto-picking "Accept" on an ADR or "Adopt all" on open questions makes the agent its own approver, so
  keep this to experiments, and count the auto-answers per arm in the report (the log, or the hook result in the session transcript).
- It grants no permissions, and fails open: no `jq` or unexpected input means the normal form appears.

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

Or skip the flag and work on an `exp/*` branch: auto-mode switches itself on there, so `/auto-mode on` is not needed.

To hand one `[hard]` plan task to an autonomous solver, use `/auto-mode:solve <plan> [task]`. It drafts the brief, proves the done condition fails on the unmodified ref, waits for your go-ahead (it spends money), runs `solver-docker/solver.zsh solve`, then coalesces the patch and runs the checks before anything is ticked. The installed plugin does not carry `solver-docker/`, so set `AUTO_MODE_SOLVER_DIR` to the checkout's `auto-mode/solver-docker` folder, or run it from a repo that has `auto-mode/solver-docker/solver.zsh`. See [solver-docker/BRIEF.md](solver-docker/BRIEF.md).

## Running an A/B experiment (two models, same task)

Goal: give two models the same task in isolated copies of the repo, let each work and commit without
stopping to ask, then compare the results. Needs git-guard 1.5+ (plain commits on `exp/*`) and this plugin,
both installed (`./deploy-all.zsh git-guard auto-mode`, then restart Claude Code), plus `jq`.

1. **Make one worktree per model, from the same start point.** Run in your repo:

   ```zsh
   git worktree add -b exp/ab-a ../myrepo-ab-a main
   git worktree add -b exp/ab-b ../myrepo-ab-b main
   ```

   The branch names must be `exp/<lowercase-slug>`. The start point (`main` here) must be identical.

2. **Optional: pre-approve safe commands** so runs don't stall on permission prompts. In the repo's committed
   `.claude/settings.json` (a worktree does not see another worktree's untracked `settings.local.json`):

   ```json
   { "permissions": { "allow": ["Bash(pytest:*)", "Bash(npm test:*)", "Bash(git add:*)", "Bash(git diff:*)"] } }
   ```

   Keep the deny rules. Auto-mode grants no permissions of its own.

3. **Start one Claude Code session per worktree**, each with its model, in separate terminals:

   ```zsh
   cd ../myrepo-ab-a && claude --model <model-a>
   cd ../myrepo-ab-b && claude --model <model-b>
   ```

4. **Paste the identical prompt into both.** Say what "done" means (for example "make `pytest` pass; commit as
   you go"). Each session now commits freely on its `exp/*` branch and, when it stops, is sent back to continue
   with its own recommended next steps.

5. **Know how a run ends.** It stops when the model's last message contains `AUTO-MODE: DONE` or
   `AUTO-MODE: BLOCKED`, when the cap is reached (default 8 automatic continuations per message you send;
   `/auto-mode max N` to change), or when you interrupt. Typing a new message resets the count. Pushes and tags
   are still blocked in both sessions, so nothing leaves your machine.

6. **Compare**, from the main repo:

   ```zsh
   git log --oneline main..exp/ab-a ; git log --oneline main..exp/ab-b
   git diff --stat main exp/ab-a ; git diff --stat main exp/ab-b
   git diff exp/ab-a exp/ab-b                    # head to head
   (cd ../myrepo-ab-a && pytest) ; (cd ../myrepo-ab-b && pytest)
   ```

   Judge on your own criteria: tests passing, diff size, how many continuations each needed, whether it ended
   with `DONE` or `BLOCKED`.

7. **Keep the winner, drop the rest.** To ship it, cherry-pick or merge it onto a normally named branch
   (`feature/<TICKET>-<slug>`) and use `/git-commit` and `/git-push` as usual. Then clean up:

   ```zsh
   git worktree remove ../myrepo-ab-a ; git worktree remove ../myrepo-ab-b
   git branch -D exp/ab-a exp/ab-b
   ```

A ready-made task for trying this out cheaply is in [AB-SMOKE-TEST.md](AB-SMOKE-TEST.md).

For true isolation (the model cannot see your global `~/.claude`, other projects, the other arm, or any existing
solution), run each arm in a container instead: see [ab-docker/README.md](ab-docker/README.md).

Caveats: the two runs are not perfectly controlled (model sampling varies between runs), so repeat the
experiment before concluding anything. The Stop hook sends both models the same continuation message.

## Tests

```zsh
zsh tests/test-auto-continue.zsh
```
