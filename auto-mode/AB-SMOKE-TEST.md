# A/B smoke test for auto-mode + git-guard `exp/*`

A cheap end-to-end check that the A/B workflow works: two models, the same small task, isolated worktrees,
auto-commits on `exp/*` branches, auto-mode continuing between steps. Expect a few minutes and a few cents
per model. The full procedure is in the "Running an A/B experiment" section of [README.md](README.md); this
file is the test case to run it with.

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
