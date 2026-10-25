# plan-bash

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**Author:** Mark Susol

The `/plan-bash` skill — given a plan number (`plan-bash 0007`), checks that
one `docs/plans/NNNN-*.md` plan against live state and archives it to
`docs/plans/archive/` with its number intact, after you confirm.

## Why

Plans are numbered (`docs/plans/NNNN-title.md`, see the `docs` plugin's
`planning-docs-plans.md`), so a plan can be addressed by number the way an
ADR can. Finished plans pile up in `docs/plans/` as noise, and archiving
them by hand skips steps: checking the work actually shipped, fixing
`TODO.md`, `docs/index.md`, and links that pointed at the old path.
`plan-bash` makes that one repeatable procedure.

It is the plan-number sibling of [`bug-bash`](../bug-bash/), which is keyed
by ticket key and sweeps every plan that mentions the ticket.

| You have | Use |
|---|---|
| A plan number (`0007`) | `plan-bash 0007` |
| A ticket key (`PROJ-1234`) | `bug-bash PROJ-1234` |
| A whole `TODO.md` that has drifted | `planning-desync-cleanup.md` (in the `docs` plugin) |

## What it does

1. Resolves the number to exactly one plan file (stops on none, a duplicate, or an already-archived plan).
2. Reads the plan, its `TODO.md` section, and linked specs and ADRs.
3. Classifies every task: done, deferred, dropped, open, unverifiable.
4. Verifies "done" tasks against live state, and compares front matter `status` with the checkboxes.
5. Reports and **asks before changing anything**.
6. If archivable: sets `status: archived`, bumps `date`, moves the file with the same name, updates `TODO.md` and `docs/index.md`, and fixes links to the old path.
7. If not archivable: lists exactly what blocks it. It never marks tasks done or deferred just to make a plan archivable.

## How it works

Installing this plugin adds the skill
(`plugins/plan-bash/skills/plan-bash/SKILL.md`) to every Claude Code
session — it auto-triggers on plan-archive requests via its `description`
frontmatter, or can be invoked directly as `/plan-bash:plan-bash`. The bare
`/plan-bash` also works as a shorthand alias, but only when no other
installed skill/command already claims that name.

This plugin is skills-only — no hooks, no wrappers. The procedure lives in
the `docs` plugin's `planning-plan-bash-archive.md` rule, so install `docs`
too.

## Installation

```zsh
./deploy.zsh
```

Or manually:

```zsh
claude plugin marketplace add msusol/claude-code-plugins
claude plugin install plan-bash@losus-ai
```

## Updating

Edit `plugins/plan-bash/skills/plan-bash/SKILL.md` (or the rule in the
`docs` plugin) and push, then run `claude plugin marketplace update` or
re-run `./deploy.zsh` on each machine.
