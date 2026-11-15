# Runbook: A/B smoke test, `wordfreq-docs` (Sonnet 5.5 vs Fable 5.2, then Copilot review)

One path, no options. It replaces the docs-variant branches scattered through [AB-SMOKE-TEST.md](AB-SMOKE-TEST.md).
Background and the plain (non-docs) variant stay in that file; the script reference is [ab-docker/README.md](ab-docker/README.md).

**What you are testing:** two models do the same 4-task plan in the `docs/` layout, in isolated containers, with
auto-mode continuing between tasks. Then each arm's branch goes through Copilot PR review rounds until it comes back clean.

| | Arm A | Arm B |
|---|---|---|
| Model | Claude Sonnet 5.5 (`claude-sonnet-5-5`) | Claude Fable 5.2 (`claude-fable-5-2`) |
| Run name (also branch `exp/<name>`) | `wordfreq-docs-sonnet-r1` | `wordfreq-docs-fable-r1` |
| Run folder | `~/experiments/runs/wordfreq-docs-sonnet-r1` | `~/experiments/runs/wordfreq-docs-fable-r1` |
| Plan repo (same commit for both) | `~/experiments/plans/wordfreq-docs` @ `main` | same |
| Image | `ab-claude-docs` (built with `AB_DOCS=1`) | same |

Every `run-ab.zsh` command below needs `AB_DOCS=1` in front. If you forget it, you get the plain image, and `check` fails.

## 0. Once per shell: set variables

Run everything from the `claude-code-plugins` repo, on the Spark, in `tmux` (a dropped SSH session kills a bare container).

```zsh
tmux new -s ab
cd ~/LosusAI/Projects/Claude/claude-code-plugins
export AB=auto-mode/ab-docker/run-ab.zsh
export AB_DOCS=1
export AB_RUNS_DIR=~/experiments/runs   # overrides the old ~/.bashrc value (~/experiments/ab-runs, which no longer exists)
docker context ls    # the * must be on `default` (see dgx-spark-docker-context)
```

`export AB_DOCS=1` is safe: it is only a switch. Do **not** export `ANTHROPIC_API_KEY`; pass it inline (step 3).

**`~/.bashrc` note:** it defines `alias run-ab=...` and `export AB_RUNS_DIR=~/experiments/ab-runs`. The alias works the same as
`$AB` in an interactive shell (aliases do not expand in scripts or `zsh -c`, which is why this runbook uses `$AB`). The
`AB_RUNS_DIR` line is stale: the earlier smoke runs were moved to `~/experiments/runs`, and `ab-runs` does not exist. Without
the override above, runs and `.reviews` logs would land in `ab-runs` while every path below says `runs`. To fix it for good,
change that `.bashrc` line to `export AB_RUNS_DIR=~/experiments/runs`, then open a new shell.

## 1. Preconditions (read-only, 1 minute)

```zsh
git -C ~/experiments/plans/wordfreq-docs log --oneline          # expect: b0bbd51 plan: wordfreq-docs
git -C ~/experiments/plans/wordfreq-docs status --short         # expect: no output
ls ~/experiments/runs | grep wordfreq-docs                      # expect: no output (names can't be reused)
```

If the last command prints anything, delete those folders first, or bump the run number to `r2` everywhere below.

## 2. Build the docs image and prove isolation (no model spend)

```zsh
$AB build
$AB check
```

`check` must end with `0 failed`. Its `docs/ harness` section must say PASS (planning rules present). Any `FAIL`: stop here.

## 3. Arm A (Sonnet 5.5): terminal 1

Pick one auth method. A spend-limited key is better isolated; `AB_LOGIN=1` uses your Max plan.

```zsh
# key (inline, not exported)
ANTHROPIC_API_KEY=sk-ant-... $AB run \
  wordfreq-docs-sonnet-r1 \
  claude-sonnet-5-5 \
  ~/experiments/plans/wordfreq-docs \
  main

# or login: run /login inside the session, open the URL in your host browser
AB_LOGIN=1 $AB run \
  wordfreq-docs-sonnet-r1 \
  claude-sonnet-5-5 \
  ~/experiments/plans/wordfreq-docs \
  main
```

Claude Code opens inside the container, on branch `exp/wordfreq-docs-sonnet-r1`, auto-mode already on. Dismiss any one-time setup prompts.

**Paste this prompt, exactly (same text for both arms):**

```text
Implement plan 0001. Commit after each task, and keep docs/plans/TODO.md in sync as you go. When all four tasks are done and pytest passes, end with `AUTO-MODE: DONE` and a 2-line summary.
```

Wait for `AUTO-MODE: DONE`. If instead you see "cap reached", note it as a failure for that arm and continue.

Then, still in the session, check the guards (each one is a pass criterion):

1. Type: `now push this` → the hook must refuse.
2. Type: `run curl https://example.com` → must fail.
3. Type: `run ls ~ ; ls /home` → only container files; `/home` shows only `claude`.

Exit with `/exit`. Do **not** edit anything in the run folder by hand.

## 4. Arm B (Fable 5.2): terminal 2

Same as step 3 with the arm B name and model. Start it right after A (or in parallel).

```zsh
ANTHROPIC_API_KEY=sk-ant-... $AB run \
  wordfreq-docs-fable-r1 \
  claude-fable-5-2 \
  ~/experiments/plans/wordfreq-docs \
  main
```

Paste the **same prompt** as in step 3, then repeat the three guard checks and `/exit`.

## 5. Verify both arms on the host (before Copilot)

Run for each `R` in `wordfreq-docs-sonnet-r1` and `wordfreq-docs-fable-r1`. Do it by hand, one arm at a time:

```zsh
R=wordfreq-docs-sonnet-r1
D=~/experiments/runs/$R
git -C $D log --oneline                      # baseline + at least 4 task commits
(cd $D && python -m pytest -q)               # must pass
git -C $D diff --stat main..HEAD             # what changed
git -C $D diff main..HEAD -- docs/           # plan boxes, status, TODO.md, index.md
```

| Check | Pass |
|---|---|
| Commits on `exp/<run>` | 4 or more beyond the baseline, no `/git-commit` prompts |
| Ended with `AUTO-MODE: DONE` | yes (not "cap reached") |
| `pytest` | passes |
| `docs/plans/0001-wordfreq.md` | all four boxes `[x]`; `status` is `active` or `done`, **not** `archived` |
| `docs/plans/TODO.md` | same four tasks, same checked state as the plan |
| `docs/index.md` | still links the plan |
| Push refused, `example.com` unreachable, `ls /home` shows only `claude` | yes |
| Extra files (specs, ADRs, other docs) | not a failure; list them as a finding |

Write down per arm: commit count, test count, the `docs/` findings. You need them for the results file.

## 6. Copilot review loop

### 6a. Which model does Copilot use?

You cannot choose it, and I could not confirm which model it is. GitHub's Copilot code review has no model picker. The only
control is an **effort level** (Lite or Balanced), set per review in the PR's Reviewers menu, or as a repo or org default.
GitHub documents effort, not the underlying model, so I cannot confirm that it is non-Anthropic. Treat it as
unknown, and do two things so the comparison stays honest:

- Request every review at the same effort for both arms. Set it once on the scratch repo (Settings → Copilot → Code review)
  if you can. `review-round` requests the review through the API and cannot set effort; if you want a specific level, click
  the Reviewers menu on the PR yourself. Record which level applied. On `msusol/ab-scratch` it is **Balanced**: the repo's
  Review effort level is "Default (Balanced)" with no maximum, and each review's footer reads "Review effort: Balanced"
  (confirmed 2026-11-14/15 on both PRs).
- Put `copilot: effort <level>, model not disclosed by GitHub` in the results front matter.

Copilot code review needs a paid Copilot plan. On Copilot Free, the repo's code review settings page shows "Copilot code review
isn't enabled for your account" and reviews will not arrive. `msusol` was upgraded to Copilot Pro before these runs.

If "not Anthropic" is a hard requirement, check GitHub's current Copilot code review docs for a named model before you
rely on this. Both arms are reviewed by the same reviewer, so the A/B comparison is fair either way.

### 6b. One-time setup

```zsh
gh auth status                                  # logged in with the Copilot-licensed account
gh repo view msusol/ab-scratch --json isPrivate # must say true; create with: gh repo create ab-scratch --private
grep msusol ~/.config/git-guard/allowlist       # must match (it does today)
export AB_REVIEW_REPO=msusol/ab-scratch
```

`gh` here is `/usr/bin/gh` (the Spark). Each review uses one Copilot premium request.

### 6c. Rounds, per arm

Do arm A fully, then arm B, using the same steps. Each arm is pushed as `exp/<run>` with its own base `base/<run>`, and gets its own PR.

A round waits up to 10 minutes for Copilot, so run it in tmux. If the session drops mid-wait, the script dies, but
rerunning `review-round` is safe: it reuses the existing PR.

```zsh
tmux new -s ab-review
cd ~/LosusAI/Projects/Claude/claude-code-plugins
export AB=auto-mode/ab-docker/run-ab.zsh AB_DOCS=1 AB_RUNS_DIR=~/experiments/runs
export AB_REVIEW_REPO=msusol/ab-scratch
```

Detach with Ctrl-b then d; reattach with `tmux attach -t ab-review`. Then:

```zsh
R=wordfreq-docs-sonnet-r1
M=claude-sonnet-5-5

$AB review-round $R     # pushes, opens PR, requests Copilot, waits; logs to ~/experiments/runs/$R.reviews/
```

Every round's `REVIEW-N.md` is copied to `~/experiments/runs/$R.reviews/`. The run folder gets `REVIEW-N.md` only when there are findings.
After each round, confirm on GitHub that `copilot-pull-request-reviewer[bot]` really reviewed the arm's final commit
(`gh api repos/msusol/ab-scratch/pulls/<N>/reviews`), so an empty wait is not read as CLEAN.

- Prints `CLEAN`: this arm is done. Go to the next arm.
- Prints findings: resume the arm, paste the prompt the script printed, wait for its commits, then exit:

```zsh
AB_LOGIN=1 $AB resume $R $M      # or: ANTHROPIC_API_KEY=sk-ant-... $AB resume $R $M
$AB review-round $R              # round 2, and so on
```

Stops at `CLEAN` or at 5 rounds (`AB_MAX_ROUNDS`). If the script warns that it could not request Copilot, it keeps
waiting: open the PR and pick Copilot in the Reviewers menu. If it refuses, it says why (repo not private, uncommitted
changes, no new commits, `.github/` changed).

Repeat for arm B (`R=wordfreq-docs-fable-r1`, `M=claude-fable-5-2`), then:

```zsh
$AB review-summary wordfreq-docs-sonnet-r1 wordfreq-docs-fable-r1
```

Do not tidy the PRs or comment on them yourself.

### 6d. Unattended alternative: `review-loop`

Instead of 6c's manual `resume` and prompt pasting, one command runs the whole loop for an arm: `review-round`, a headless
fix session in the arm's container, `review-round` again, until CLEAN or 5 rounds. It needs an API key in
`~/experiments/.env` (see [ab-docker/README.md](ab-docker/README.md#unattended-review-loop-review-loop)); `AB_LOGIN=1` is refused.

```zsh
$AB review-loop wordfreq-docs-sonnet-r1 claude-sonnet-5-5
$AB review-loop wordfreq-docs-fable-r1 claude-fable-5-2
```

Run each in tmux. Per-session fix logs are in `~/experiments/runs/<run>.reviews/fix-N.log`. It stops, and says why, if a fix
session fails, makes no commit, or leaves uncommitted changes. This mode has only been tested with stubs: run it on one arm
first and read `fix-1.log`. The `origin` bug from the recorded run is fixed in `review-round` (it restores `origin` after pushing),
so the manual `set-url` workaround is only needed for runs started before that fix.

## 7. Record the results and clean up

```zsh
mkdir -p ~/experiments/results/data/2026-11-14-wordfreq-docs-sonnet-vs-fable
cp ~/experiments/runs/wordfreq-docs-sonnet-r1.reviews/rounds.csv \
  ~/experiments/results/data/2026-11-14-wordfreq-docs-sonnet-vs-fable/rounds-sonnet-r1.csv
cp ~/experiments/runs/wordfreq-docs-fable-r1.reviews/rounds.csv \
  ~/experiments/results/data/2026-11-14-wordfreq-docs-sonnet-vs-fable/rounds-fable-r1.csv
cp ~/experiments/results/TEMPLATE-comparison.md \
  ~/experiments/results/2026-11-14-wordfreq-docs-sonnet-vs-fable.md
```

Fill the results file from steps 5 and 6: exact model IDs (`claude-sonnet-5-5`, `claude-fable-5-2`), plan commit `b0bbd51`,
harness `docs/ (AB_DOCS=1)`, image ID (`docker images ab-claude-docs`), auth method, rounds to clean and findings per round,
and the Copilot line from 6a. Add a row to `~/experiments/results/index.md`.

Only then remove the run folders (a name cannot be reused until its folder is gone):

```zsh
rm -rf ~/experiments/runs/wordfreq-docs-sonnet-r1 ~/experiments/runs/wordfreq-docs-sonnet-r1.reviews
rm -rf ~/experiments/runs/wordfreq-docs-fable-r1 ~/experiments/runs/wordfreq-docs-fable-r1.reviews
```

Close the two scratch PRs in `msusol/ab-scratch` if you do not want to keep them.

## Pass criteria (tick these)

- [ ] `$AB check` ends with `0 failed`, docs section PASS
- [ ] Each arm: 4 or more task commits, `AUTO-MODE: DONE`, `pytest` passes
- [ ] Each arm: four plan boxes checked, plan not archived, `TODO.md` matches, `docs/index.md` links the plan
- [ ] Each arm: push refused, `example.com` blocked, `/home` shows only `claude`
- [ ] Each arm: Copilot review loop ended `CLEAN` or at the round cap, `rounds.csv` saved
- [ ] Results file written with the Copilot effort and model caveat

One run per model proves the pipeline works. It does not rank the models: repeat as `r2` and `r3` (3 or more) before concluding anything about Copilot rounds.

## Recorded run: 2026-11-14/15 (r1)

Plan `wordfreq-docs` @ `b0bbd51`, image `ab-claude-docs` `b6e447d50d5c`, Claude Max login, Copilot effort Balanced
(model not disclosed). Reviews went to `msusol/ab-scratch`, reviewer `copilot-pull-request-reviewer[bot]`.

| Arm | Model | Task commits | pytest | `wordfreq.py` / tests / README (lines) | Copilot rounds | PR |
|---|---|---|---|---|---|---|
| A | `claude-sonnet-5-5` | 4 | 5 passed | 32 / 21 / 27 | 1: CLEAN, 0 findings | #1, clean at `78cf984` |
| B | `claude-fable-5-2` | 4, plus fix `a442285` | 10 passed | 55 / 68 / 59 | 2: 1 finding (low), then CLEAN | #2, clean at `a442285` |

Docs criteria: identical for both arms. Four plan boxes checked, `status: active`, `TODO.md` updated in every task commit and
matching the plan, `docs/index.md` unchanged, no extra files. The plan `date` reads 2026-11-15 in both (container clock).

Arm B's round-1 finding, `test_wordfreq.py:41`: the hyphen-preservation test asserted only the top three results and
`well-known` was not among them, so removing hyphen support would still pass. Fable fixed it in `a442285` and round 2 was
CLEAN (finding marked resolved). Arm A needed no `resume`. Copilot premium requests: 3 (1 + 2). Full write-up:
`~/experiments/results/2026-11-14-wordfreq-docs-sonnet-vs-fable.md`. One run per model: do not rank the models from this;
repeat as r2 and r3.

**Loop bug found in this run (fix before the next `resume`):** `review-round` sets the run folder's `origin` to the GitHub
URL. The resumed container's git-guard only allows `example.invalid/ab`, so the arm's commit is refused. Before every `resume`, run:

```zsh
git -C ~/experiments/runs/<run> remote set-url origin https://example.invalid/ab/scratch
```

`review-round` sets the URL again at the start of the next round, so nothing else is needed.

## Recorded run: review-loop test, 2026-11-15

First run of `review-loop` against real Claude Code, GitHub and Copilot. Run `wordfreq-docs-fable-loop-r1` is a copy of arm B's run
folder reset to `af4ca71` (the commit Copilot found the hyphen-test gap in), with `origin` set to the container remote like a fresh run,
so it needed no interactive session. Model `claude-fable-5-2`, key from `~/experiments/.env` (workspace `ab-experiments`, $10/month cap).

| Round | Commit | Copilot | Result |
|---|---|---|---|
| 1 | `af4ca71` | 1 finding (same hyphen-test gap as arm B) | headless fix session started |
| fix | `dbc3b50` | n/a | `claude -p` committed the fix, 10 tests pass, `wordfreq.py` unchanged |
| 2 | `dbc3b50` | 0 findings | CLEAN after 2 rounds, PR #3 in `msusol/ab-scratch` |

Observed: the fix session ran with no TTY and only `api.anthropic.com` reachable; its commit passed git-guard normally; `origin` stayed the
container remote (the `review-round` restore works); the run folder ended clean; nothing was pushed from the container. From Copilot's first
review to CLEAN took about 2 minutes. The `Warning: N uncommitted changes` line in the output comes from `gh` run in the
`claude-code-plugins` repo, which had 5 uncommitted files at the time, not from the run folder.

Cost: **$0.68** for the one headless fix session (key `ab-loop`, workspace `ab-experiments`: $0.68 spent, 7% of the $10 cap; org balance
$79.32 to $78.64). That key had no other use, and Copilot's premium requests are not billed here. The Console Cost page had no data yet (it lags a few
hours); the Spend limits page updated within minutes, so read cost there. Not shown by this test: the timeout and budget paths against the real CLI,
and a loop that needs more than one fix. It also does not compare models: it is one
arm restarted from a known commit. Premium requests used: 2.
