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

### With the docs/ harness (`AB_DOCS=1`)

Use `plans/wordfreq-docs` and the docs image (see [Adding the docs/ harness](ab-docker/README.md#adding-the-docs-harness)).
The plan content is the same; only the layout differs, so both arms of a docs comparison must use that image and plan.

> Implement plan 0001. Commit after each task, and keep docs/plans/TODO.md in sync as you go. When all four tasks are
> done and pytest passes, end with `AUTO-MODE: DONE` and a 2-line summary.

Extra pass criteria: the plan's four boxes are checked and its `status` is still `active` or set per the rules (it must
not be archived without confirmation), `TODO.md` matches the plan, and `docs/index.md` still links the plan. Treat
extra files the arm creates (specs, ADRs) as a finding to note, not a failure.

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

1. **Create the experiments folder and commit the plan.** `init` makes `~/experiments` from the template and an
   two example plan repos with the plan below already in them (staged, not committed): `plans/wordfreq` (a root
   `PLAN.md`, for the plain image) and `plans/wordfreq-docs` (the same plan as `docs/plans/0001-wordfreq.md` plus
   `TODO.md` and `index.md`, for the `AB_DOCS=1` image):

   ```zsh
   auto-mode/ab-docker/run-ab.zsh init
   for p in wordfreq wordfreq-docs; do
     git -C ~/experiments/plans/$p remote add origin https://github.com/<you>/$p-plan   # never pushed; satisfies git-guard
     git -C ~/experiments/plans/$p commit -m "plan: $p"
   done
   ```

   Only committed files are exported to the arms. Each plan is its own repo so an arm never sees another plan.
   See `experiments-template/README.md` for the layout, naming and what is gitignored.

2. **Build the image** (once, and again after plugin changes). From the claude-code-plugins repo:

   ```zsh
   auto-mode/ab-docker/run-ab.zsh build
   ```

   **Docs variant:** `AB_DOCS=1 auto-mode/ab-docker/run-ab.zsh build` builds a separate image, `ab-claude-docs`, with the
   docs/ planning rules installed. Use the same `AB_DOCS=1` on every later command in the docs variant.

3. **Check the isolation before spending anything on models:**

   ```zsh
   auto-mode/ab-docker/run-ab.zsh check
   ```

   Every line should say `PASS` (no host folders or Claude history, `example.com` and `github.com` unreachable,
   `api.anthropic.com` reachable, no firewall changes possible, both plugins installed, web tools denied, and the docs/ harness present or absent as expected). Fix any
   `FAIL` before going on.

   **Docs variant:** run it as `AB_DOCS=1 auto-mode/ab-docker/run-ab.zsh check`. It adds a `docs/ harness` section: with
   `AB_DOCS=1` it requires the planning rules, their `@`-imports and the docs plugin; without it, it requires that none
   of them are present, so a baseline arm cannot be running with the rules by accident. Use the same `AB_DOCS` value you
   built with, or the check fails.

4. **Start one arm per terminal**, with a dedicated, spend-limited API key (the model can read it in the container; see
   [Getting a spend-limited API key](ab-docker/README.md#getting-a-spend-limited-api-key)). Pass it inline, not exported,
   so Claude Code on your host keeps using your subscription:

   ```zsh
   ANTHROPIC_API_KEY=sk-ant-... auto-mode/ab-docker/run-ab.zsh run wordfreq-model-a-r1 <model-a> ~/experiments/plans/wordfreq main
   ANTHROPIC_API_KEY=sk-ant-... auto-mode/ab-docker/run-ab.zsh run wordfreq-model-b-r1 <model-b> ~/experiments/plans/wordfreq main
   ```

   **Docs variant:** same commands with `AB_DOCS=1` in front, the `wordfreq-docs` plan, and the plan in the run name:

   ```zsh
   AB_DOCS=1 ANTHROPIC_API_KEY=sk-ant-... auto-mode/ab-docker/run-ab.zsh run wordfreq-docs-model-a-r1 <model-a> ~/experiments/plans/wordfreq-docs main
   AB_DOCS=1 ANTHROPIC_API_KEY=sk-ant-... auto-mode/ab-docker/run-ab.zsh run wordfreq-docs-model-b-r1 <model-b> ~/experiments/plans/wordfreq-docs main
   ```

   Each run (named `<plan>-<model>-r<N>`) lands in `~/experiments/runs/<name>` on branch `exp/<name>`, with auto-mode already on. The first launch may
   show Claude Code's one-time setup prompts.

5. **Paste the same prompt into both** and let them run: the first prompt under "Prompt" for the plain variant, the one
   under "With the docs/ harness" for the docs variant.

6. **Compare on the host.** The run folders are ordinary repos:

   ```zsh
   git -C ~/experiments/runs/wordfreq-model-a-r1 log --oneline ; git -C ~/experiments/runs/wordfreq-model-b-r1 log --oneline
   git diff --no-index --stat ~/experiments/runs/wordfreq-model-a-r1 ~/experiments/runs/wordfreq-model-b-r1
   (cd ~/experiments/runs/wordfreq-model-a-r1 && pytest) ; (cd ~/experiments/runs/wordfreq-model-b-r1 && pytest)
   ```

   **Docs variant:** also check the plan's boxes, `status` and `TODO.md` against the docs criteria above, for example
   `git -C ~/experiments/runs/wordfreq-docs-model-a-r1 diff <baseline>..HEAD -- docs/` (`<baseline>` is the run's first commit).

7. **Optional: add the Copilot review loop** to compare how many review rounds each arm needs; see
   [Copilot review loop](ab-docker/README.md#copilot-review-loop-host-side).

8. **Clean up (and keep the results):** copy each `<run>.reviews/rounds.csv` into `~/experiments/results/data/` first, then `rm -rf` the two run folders (and their `.reviews` folders). A name can't be reused until its folder is gone.

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
