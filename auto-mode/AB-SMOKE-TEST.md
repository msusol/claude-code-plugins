# A/B smoke test for auto-mode + git-guard `exp/*`

A cheap end-to-end check that the A/B workflow works: two models, the same small task, isolated worktrees,
auto-commits on `exp/*` branches, auto-mode continuing between steps. Expect a few minutes and a few cents
per model. The full procedure is in the "Running an A/B experiment" section of [README.md](README.md); this
file is the test case to run it with.

There are two ways to run it:

- **Host worktrees** (the Setup section below): quick, but each arm runs as you and could see your global
  `~/.claude`, other projects and the other arm's branch.
- **Isolated containers** ([Running it in containers](#running-it-in-containers-true-isolation)): each arm sees
  only its own files and can reach only the Anthropic API. Use this when the result has to be a fair comparison.

## Setup (once)

Use a throwaway repo, not a real project.

```zsh
mkdir ab-scratch && cd ab-scratch && git init -b main
git remote add origin https://github.com/msusol/ab-scratch   # fake is fine; see below
# write PLAN.md (below), then:
git add PLAN.md && git commit -m "chore: add plan"           # on main this needs /git-commit
```

**Remote gotcha:** git-guard blocks commits when `origin` is missing or not in
`~/.config/git-guard/allowlist`. The remote does not have to exist, since nothing is pushed, but its URL must
match an allowlist pattern (here `github.com/msusol`).

Then create the worktrees and start one session per model as described in the README
(`git worktree add -b exp/ab-a ../ab-scratch-a main`, same for `exp/ab-b`;
`claude --model <model-a>` / `<model-b>` in each).

## PLAN.md

```markdown
# Plan: wordfreq CLI
1. wordfreq.py: top_words(text, n) returns the n most common words,
   lowercased, punctuation stripped, ties alphabetical.
2. test_wordfreq.py: pytest tests for empty input, ties, punctuation, n > distinct words.
3. CLI: `python wordfreq.py file.txt -n 5` prints "word count" lines.
4. README.md with usage and one example.
Done = pytest passes, CLI works on a sample file.
```

## Prompt (paste the same text into both sessions)

> Read PLAN.md and do it. Commit after each numbered step. When all four are done and pytest passes, end with
> `AUTO-MODE: DONE` and a 2-line summary.

Four steps with a commit each give the Stop hook reason to continue, and `pytest` gives an objective pass/fail.

## Pass criteria (per session)

- [ ] At least 3 commits on its `exp/*` branch, with no `/git-commit` prompts
- [ ] Ended with `AUTO-MODE: DONE`, not the "cap reached" message
- [ ] `pytest` passes in the worktree
- [ ] Asked to "now push this", the hook refuses (pushes and tags stay guarded)

Compare the two runs with `git log --oneline main..exp/ab-a`, `git diff --stat main exp/ab-a` (and the same for
`ab-b`), and `git diff exp/ab-a exp/ab-b`.

## Running it in containers (true isolation)

Uses [ab-docker/](ab-docker/README.md). Each arm gets a fresh export of one commit (no git history), a clean
Claude config with only git-guard and auto-mode installed, and a firewall that allows only `api.anthropic.com`.
It does not need the fake-remote setup above, because the container creates its own scratch remote.
This path has not been run end to end yet; the `check` step in 3 is what tells you whether it works on your machine.

1. **Make the scratch repo with the plan committed** (the export contains only committed files):

   ```zsh
   mkdir -p ~/code/ab-scratch && cd ~/code/ab-scratch && git init -b main
   # write PLAN.md (above), then commit it (on main this needs /git-commit, or a one-off sanctioned commit)
   ```

   Keep it outside the folder you open in your IDE if you want it kept out of IDE tooling. Isolation does not
   depend on that, because the container mounts nothing but its own run folder.

2. **Build the image** (once, and again after plugin changes). From the claude-code-plugins repo:

   ```zsh
   auto-mode/ab-docker/run-ab.zsh build
   ```

3. **Check the isolation before spending anything on models:**

   ```zsh
   auto-mode/ab-docker/run-ab.zsh check
   ```

   Every line should say `PASS` (no host folders or Claude history, `example.com` and `github.com` unreachable,
   `api.anthropic.com` reachable, no firewall changes possible, both plugins installed, web tools denied). Fix any
   `FAIL` before going on.

4. **Start one arm per terminal**, with a dedicated, spend-limited API key (the model can read it in the container; see
   [Getting a spend-limited API key](ab-docker/README.md#getting-a-spend-limited-api-key)). Pass it inline, not exported,
   so Claude Code on your host keeps using your subscription:

   ```zsh
   ANTHROPIC_API_KEY=sk-ant-... auto-mode/ab-docker/run-ab.zsh run model-a <model-a> ~/code/ab-scratch main
   ANTHROPIC_API_KEY=sk-ant-... auto-mode/ab-docker/run-ab.zsh run model-b <model-b> ~/code/ab-scratch main
   ```

   Each run lands in `~/ab-runs/<name>` on branch `exp/<name>`, with auto-mode already on. The first launch may
   show Claude Code's one-time setup prompts.

5. **Paste the same prompt into both** (see Prompt above) and let them run.

6. **Compare on the host.** The run folders are ordinary repos:

   ```zsh
   git -C ~/ab-runs/model-a log --oneline ; git -C ~/ab-runs/model-b log --oneline
   git diff --no-index --stat ~/ab-runs/model-a ~/ab-runs/model-b
   (cd ~/ab-runs/model-a && pytest) ; (cd ~/ab-runs/model-b && pytest)
   ```

7. **Clean up:** `rm -rf ~/ab-runs/model-a ~/ab-runs/model-b`. A name can't be reused until its folder is gone.

Extra pass criteria for the container path:

- [ ] `run-ab.zsh check` ends with `0 failed`
- [ ] Each run folder has at least 4 commits (baseline plus the plan's steps) on its `exp/*` branch
- [ ] In a session, `curl https://example.com` and `git clone https://github.com/...` fail
- [ ] In a session, `ls ~` shows only the container's own files, and `ls /home` shows only `claude`

## Testing each piece alone

| To test | Do this | Expect |
|---|---|---|
| auto-mode cap | `/auto-mode max 2`, then give a task with 4+ steps | stops after 2 continuations with "cap reached" |
| auto-mode off switch | on a non-`exp` branch, no flag file | Claude stops normally after each turn |
| git-guard outside `exp/*` | on `main`, run a bare `git commit` | blocked with a pointer to `/git-commit` |
| git-guard on `exp/*` | on an `exp/*` branch, `git commit` | allowed; `git push` and `git tag` still blocked |

## Clean up

```zsh
git worktree remove ../ab-scratch-a ; git worktree remove ../ab-scratch-b
git branch -D exp/ab-a exp/ab-b
```

Model runs vary; repeat before concluding anything about which model is better.
