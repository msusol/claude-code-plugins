# A/B smoke test for auto-mode + git-guard `exp/*`

A cheap end-to-end check that the A/B workflow works: two models, the same small task, isolated containers,
auto-commits on `exp/*` branches, auto-mode continuing between steps. Expect a few minutes and a few cents
per model. The full procedure is in the "Running an A/B experiment" section of [README.md](README.md); this
file is the test case to run it with.

The test runs through [ab-docker/](ab-docker/README.md). Each arm gets a fresh export of one commit (no git
history), a clean Claude config with only git-guard and auto-mode installed, and a firewall that allows only
`api.anthropic.com`. It sees only its own files, so the comparison is fair. There are no worktrees, and the
container creates its own scratch remote, so git-guard's remote allowlist needs no setup for the arms.

The `check` step in step 3 is what tells you whether the isolation works on your machine.

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

```text
Read PLAN.md and do it. Commit after each numbered step. When all four are done and pytest passes, end with `AUTO-MODE: DONE` and a 2-line summary.
```

Four steps with a commit each give the Stop hook reason to continue, and `pytest` gives an objective pass/fail.

### With the docs/ harness (`AB_DOCS=1`)

Use `plans/wordfreq-docs` and the docs image (see [Adding the docs/ harness](ab-docker/README.md#adding-the-docs-harness)).
The plan content is the same; only the layout differs, so both arms of a docs comparison must use that image and plan.

> Implement plan 0001. Commit after each task, and keep docs/plans/TODO.md in sync as you go. When all four tasks are
> done and pytest passes, end with `AUTO-MODE: DONE` and a 2-line summary.

Extra pass criteria: the plan's four boxes are checked and its `status` is still `active` or set per the rules (it must
not be archived without confirmation), `TODO.md` matches the plan, and `docs/index.md` still links the plan. Treat
extra files the arm creates (specs, ADRs) as a finding to note, not a failure.

## Running it

1. **Create the experiments folder and commit the plan.** `init` makes `~/experiments` from the template and two
   example plan repos with the plan above already in them (staged, not committed): `plans/wordfreq` (a root
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

   `~/experiments` is deliberately **outside** the folder you open in your IDE (your project root), so IDE indexing
   and inspections, and Claude Code sessions opened on that root, never see it. Do not create it under your project
   root, and pick another location (`init` takes a folder) if `~/experiments` is inside it. Isolation does not
   depend on this, because the container mounts nothing but its own run folder.

2. **Build the image** (once, and again after plugin changes). From the claude-code-plugins repo:

   ```zsh
   auto-mode/ab-docker/run-ab.zsh build
   ```

   **Docs variant:** `AB_DOCS=1 auto-mode/ab-docker/run-ab.zsh build` builds a separate image, `ab-claude-docs`, with the
   docs/ planning rules installed. Use the same `AB_DOCS=1` on every later command in the docs variant.

   Libraries a task needs at run time go in [solver-docker/requirements.txt](solver-docker/requirements.txt) before the build
   (the container has no network). The wordfreq plan needs none.

3. **Check the isolation before spending anything on models:**

   ```zsh
   auto-mode/ab-docker/run-ab.zsh check
   ```

   Every line should say `PASS` (no host folders or Claude history, `example.com` and `github.com` unreachable,
   `api.anthropic.com` reachable, no firewall changes possible, both plugins installed, web tools denied, and the docs/
   harness present or absent as expected). Fix any `FAIL` before going on.

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

   **Or use your Claude subscription (Pro, Max) instead of a key.** Replace the key with `AB_LOGIN=1`, then run
   `/login` inside each session and follow the URL in your host browser:

   ```zsh
   AB_LOGIN=1 auto-mode/ab-docker/run-ab.zsh run wordfreq-model-a-r1 <model-a> ~/experiments/plans/wordfreq main
   AB_LOGIN=1 auto-mode/ab-docker/run-ab.zsh run wordfreq-model-b-r1 <model-b> ~/experiments/plans/wordfreq main
   ```

   Both arms draw on your plan's usage limits, not dollars, so turn off paid extra usage first, and expect weaker
   isolation than with a key. Read [Using a Claude subscription](ab-docker/README.md#using-a-claude-subscription-pro-max-team-enterprise-instead-of-a-key)
   before choosing this path.

   Each run (named `<plan>-<model>-r<N>`) lands in `~/experiments/runs/<name>` on branch `exp/<name>`, with auto-mode
   already on. The first launch may show Claude Code's one-time setup prompts.

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

8. **Clean up (and keep the results):** copy each `<run>.reviews/rounds.csv` into `~/experiments/results/data/` first, then
   `rm -rf` the two run folders (and their `.reviews` folders). A name can't be reused until its folder is gone.

## Pass criteria

Overall:

- [ ] `run-ab.zsh check` ends with `0 failed`

Per session:

- [ ] At least 4 commits on its `exp/*` branch (baseline plus the plan's steps), with no `/git-commit` prompts
- [ ] Ended with `AUTO-MODE: DONE`, not the "cap reached" message
- [ ] `pytest` passes in its run folder
- [ ] Asked to "now push this", the hook refuses (pushes and tags stay guarded)
- [ ] `curl https://example.com` and `git clone https://github.com/...` fail
- [ ] `ls ~` shows only the container's own files, and `ls /home` shows only `claude`

## Testing each piece alone

| To test | Do this | Expect |
|---|---|---|
| auto-mode cap | `/auto-mode max 2`, then give a task with 4+ steps | stops after 2 continuations with "cap reached" |
| auto-mode off switch | on a non-`exp` branch, no flag file | Claude stops normally after each turn |
| git-guard outside `exp/*` | on `main`, run a bare `git commit` | blocked with a pointer to `/git-commit` |
| git-guard on `exp/*` | on an `exp/*` branch, `git commit` | allowed; `git push` and `git tag` still blocked |

Model runs vary; repeat before concluding anything about which model is better.
