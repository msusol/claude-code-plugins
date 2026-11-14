# experiments

Scaffold for A/B model experiments with `auto-mode/ab-docker`. Create yours with `run-ab.zsh init` (default `~/experiments`).
This folder does not need to be a git repo. If you make it one, the `.gitignore` files already keep the disposable parts out.

```
experiments/
├── plans/                one git repo per plan (an arm only ever sees its own plan)   [contents ignored, .keep tracked]
│   └── wordfreq/         PLAN.md, .gitignore   (init creates it from examples/wordfreq)
├── runs/                 AB_RUNS_DIR: <plan>-<model>-r<N>/ run folders and .reviews/ logs   [contents ignored, .keep tracked]
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

## First plan

`init` creates `plans/wordfreq` with `git init` and stages the files, but does not commit: git-guard blocks commits in a repo
without an allowlisted `origin`. Give it one that is never pushed, then commit:

```zsh
git -C plans/wordfreq remote add origin https://github.com/<you>/wordfreq-plan   # matches your allowlist; never pushed
git -C plans/wordfreq commit -m "plan: wordfreq"
```
