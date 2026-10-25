# jira-tickets

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**Author:** Mark Susol

The `/jira-describe` skill — keeps a Jira ticket's description readable across multiple rounds
of investigation/findings, distilled from real friction hit filing and updating multi-round tickets.

## Why

A ticket that gets multiple rounds of addendums (a comment or description edit per round) rots
the same way an out-of-sync `TODO.md` does: each round adds real detail, but nobody rolls the
*net effect* back up, so reading the ticket cold means reconstructing current status from a
chain of comments/edits in order.

This skill packages one fix: every multi-round ticket keeps a **`## Current Status`** section
(rewritten in place, always the net-current truth) followed by an append-only **`## History`**
log (one dated entry per round, never edited). It also documents a real gotcha hit live doing
this: which Atlassian tool is available for the target Jira instance decides whether Markdown
syntax in a description actually renders, or shows up as literal `##`/`-` characters — see the
skill body for the two paths and when each applies.

## How it works

Installing this plugin adds this skill (`plugins/jira-tickets/skills/jira-describe/SKILL.md`) to
every Claude Code session — it auto-triggers on Jira ticket filing/updates via its `description`
frontmatter, or can be invoked directly as `/jira-tickets:jira-describe` (the namespaced form,
always reliable). The bare `/jira-describe` also works as a shorthand alias, but only when no
other installed skill/command already claims that name.

This plugin is skills-only — no hooks, no wrappers, nothing to enforce at the tool layer. It's
guidance content only.

## Installation

```zsh
./deploy.zsh
```

Or manually:

```zsh
claude plugin marketplace add msusol/claude-code-plugins
claude plugin install jira-tickets@losus-ai
```

## Updating

Edit `plugins/jira-tickets/skills/jira-describe/SKILL.md` directly and push — Claude Code
plugins update by re-pulling the marketplace source, so a `claude plugin marketplace update` (or
just re-running `./deploy.zsh`) on each machine picks up the change.
