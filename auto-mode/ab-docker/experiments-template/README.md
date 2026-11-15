# experiments

Scaffold for A/B model experiments with `auto-mode/ab-docker`. Create yours with `run-ab.zsh init` (default `~/experiments`).
This folder does not need to be a git repo. If you make it one, the `.gitignore` files already keep the disposable parts out.

```
experiments/
├── .claude/              settings.example.json (tracked, inert); settings.local.json is yours, ignored   (see "Letting an assistant run the experiments")
├── plans/                one git repo per plan (an arm only ever sees its own plan)   [contents ignored, .keep tracked]
│   ├── wordfreq/         PLAN.md at the root (plain baseline)    (init creates it from examples/wordfreq)
│   └── wordfreq-docs/    docs/plans/0001-wordfreq.md, TODO.md, index.md   (same plan in the docs/ layout, for AB_DOCS=1)
├── runs/                 AB_RUNS_DIR: <plan>-<model>-r<N>/ run folders, plus <run>.session/ (Claude Code transcripts)
│                         and <run>.reviews/ (rounds.csv, steps.csv, REVIEW-N.md, fix logs)   [contents ignored, .keep tracked]
├── results/              what you keep
│   ├── index.md
│   ├── TEMPLATE-comparison.md
│   └── data/             rounds-<model>-r<N>.csv per comparison
└── docs/investigate/     narrative notes; link to results/, do not copy numbers
```

## Naming

| Thing | Pattern | Example |
|---|---|---|
| Plan repo | `plans/<plan-slug>/` | `plans/wordfreq/` |
| Run (also branch `exp/<run>`) | `<plan>-<model>-r<N>` | `wordfreq-sonnet-r1` |
| Results file | `results/<date>-<plan>-<A>-vs-<B>.md` | `results/2026-11-14-wordfreq-sonnet-vs-fable.md` |
| Raw data | `results/data/<date>-<plan>-<A>-vs-<B>/rounds-<model>-r<N>.csv` | |

Run names are lowercase letters, digits and hyphens. Put the exact model IDs inside the results file, not in file names.

## What is ignored, and why

- `runs/*` and `plans/*` (via the `.gitignore` in each, with `.keep` and `.gitignore` themselves tracked): run folders are
  disposable throwaway repos; each plan is its own repo and must not be nested inside this one.
- Inside every run folder, `REVIEW-*.md` is ignored by `.git/info/exclude`, written by `review-round`.
- Inside every plan repo, `.gitignore` keeps `__pycache__/`, `.pytest_cache/` and similar out of an arm's commits, because it is
  exported into the arm's baseline.

## Letting an assistant run the experiments

If a Claude Code session in this folder is to start the arms for you (tmux sessions, `run-ab.zsh run`, `resume`, `review-loop`), Claude Code's permission system will
block those commands until you allow them. `.claude/settings.example.json` lists the narrow set that is needed. It is **not active**: Claude Code reads only
`.claude/settings.json` and `.claude/settings.local.json`. To opt in, review it and merge its `permissions.allow` entries into `.claude/settings.local.json` yourself
(that file is gitignored, so it stays on your machine). `init` never writes it, and an assistant should not edit it for you.

What you are allowing, so decide with that in mind:

- `run`, `resume` and `review-loop` start Claude Code sessions that spend API money; `review-loop` also pushes the arm's branch to your private scratch repo
  (`AB_REVIEW_REPO`) and runs unattended fix sessions. The spend limit on the API key's workspace is the real cap, so set it first (see the ab-docker README).
- The tmux entries are limited to sessions named `ab-*`.
- Nothing here allows `git commit`, `git push` from the session itself, `rm`, or changing settings.

## First plan

`init` creates `plans/wordfreq` and `plans/wordfreq-docs` with `git init` and stages the files, but does not commit: git-guard blocks commits in a repo
without an allowlisted `origin`. Give it one that is never pushed, then commit:

```zsh
for p in wordfreq wordfreq-docs; do
  git -C plans/$p remote add origin https://github.com/<you>/$p-plan   # matches your allowlist; never pushed
  git -C plans/$p commit -m "plan: $p"
done
```
