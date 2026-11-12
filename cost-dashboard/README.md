# cost-dashboard

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**Author:** Mark Susol

Claude Code plugin that turns your local session logs into a self-contained HTML dashboard of
**estimated** cost per session, task, model, day, and subagent.

## Install

```zsh
./deploy.zsh
```

Or directly from the marketplace:

```zsh
claude plugin marketplace add msusol/claude-code-plugins
claude plugin install cost-dashboard@losus-ai
```

## Use

```
/cost-dashboard:dashboard                    # last 30 days, all projects
/cost-dashboard:dashboard --days 7
/cost-dashboard:dashboard --project re-lead  # filter by project dir / cwd substring
/cost-dashboard:dashboard --days 0           # everything
```

Output: `~/.claude/cost-dashboard.html` (self-contained, no network, light/dark aware).

## What it shows

- KPIs: total, per session, per task, subagent share, cache hit rate
- Cost per day and cost by model
- Sessions table (sortable, filterable); click a row for the per-task (user prompt) breakdown

A "task" is one user prompt and everything Claude did in response, including subagents spawned in that turn.

## How it works

`plugins/cost-dashboard/scripts/build_dashboard.py` reads `~/.claude/projects/**/*.jsonl`,
de-duplicates streamed assistant messages, and multiplies token usage by the rates in
`plugins/cost-dashboard/pricing.json`. Python 3 standard library only. No rules and no hooks —
there is no runtime event to intercept, so this plugin is a command only.

## Caveats

- Costs are **estimates**. The rates in `pricing.json` are defaults; verify and edit them. Models
  that match no rate use the fallback and are flagged on the dashboard.
- Subagent transcripts stored in separate files count toward the session total and the
  "Subagent" column, but cannot always be tied to a specific task row.
- Subscription plans (Pro/Max) are not billed per token; the numbers show API-equivalent value.

## Docs

Planning docs live in [docs/](docs/index.md).

## Uninstall

```zsh
./uninstall.zsh
```
