# bug-bash

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**Author:** Mark Susol

The `/bug-bash` skill — given a ticket number, sweeps `docs/plans/*.md` and
`docs/plans/TODO.md` for anything tied to that ticket and archives what's
actually done, instead of leaving completed work scattered across live
planning docs as noise for the next reader.

## Why

Bug-bash sessions ("I'll give you a ticket #, walk docs/plans and TODO.md,
archive anything related") were being done ad hoc each time, with no
consistent definition of "stale" or a repeatable archive procedure.
`planning-desync-cleanup.md` already covers a *heavy*, repo-wide desync
between plan files and `TODO.md` — this skill is the narrower, ticket-scoped
sibling: find everything about one ticket, confirm what's done, archive it
using the same mechanics.

For the same cleanup keyed by plan number instead of ticket key, see the
[`plan-bash`](../plan-bash/) skill.

## How it works

Installing this plugin adds the skill
(`plugins/bug-bash/skills/bug-bash/SKILL.md`) to every Claude Code session —
it auto-triggers on "bug bash"/ticket-cleanup requests via its `description`
frontmatter, or can be invoked directly as `/bug-bash:bug-bash`. The bare
`/bug-bash` also works as a shorthand alias, but only when no other
installed skill/command already claims that name.

This plugin is skills-only — no hooks, no wrappers. All the actual procedure
lives in the `docs` plugin's `planning-bug-bash-ticket-cleanup.md` rule,
which this skill just points to (see that rule for the full
grep/classify/confirm/archive steps).

## Installation

```zsh
./deploy.zsh
```

Or manually:

```zsh
claude plugin marketplace add msusol/claude-code-plugins
claude plugin install bug-bash@losus-ai
```

## Updating

Edit `plugins/bug-bash/skills/bug-bash/SKILL.md` (or the rule in the `docs`
plugin) and push, then run `claude plugin marketplace update` or re-run
`./deploy.zsh` on each machine.
