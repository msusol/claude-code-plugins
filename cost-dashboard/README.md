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
/cost-dashboard:dashboard serve              # a live page on http://127.0.0.1:8766/, rebuilt as your logs grow
/cost-dashboard:dashboard serve --port 8770 --days 0
```

Without `serve` the output is `~/.claude/cost-dashboard.html` (self-contained, no network, light/dark aware), a snapshot.
With `serve` a small local server keeps the page current: reload the browser to see new costs. It builds in memory and writes
nothing, serves only the page and `/data.json`, binds to `127.0.0.1`, and refuses requests that name any other host; from another
machine use an SSH tunnel to the port.

## What it shows

Four tabs, every table with **tokens in and out and the dollars for each side**, the figures models are compared on:

| Tab | Answers |
|---|---|
| **Overview** | What did I spend? Totals, averages, cache hit rate, cost per day, cost by model |
| **Model & effort** | How do models, and effort levels on one model, compare? Cost by model and effort (effort is always shown with its model), a model x effort grid, cost per task, cost per day |
| **Context** | Why does it cost this much? Cost by token type, the price per 1M tokens for each model, and how the context grows call by call (with compactions) |
| **Sessions** | Which sessions cost the most? Paged, sortable, searchable; click a row for its tasks; Project ▸ expands to show the first prompt |

A "task" is one user prompt and everything Claude did in response, including subagents spawned in that turn.

**[guide/GUIDE.md](guide/GUIDE.md)** walks through each tab with example data and charts, and explains the concepts behind the numbers
(in vs out tokens, context, prompt caching, compaction, effort). [guide/example-dashboard.html](guide/example-dashboard.html) is the example
dashboard to open in a browser.

## How it works

`plugins/cost-dashboard/scripts/build_dashboard.py` reads `~/.claude/projects/**/*.jsonl`,
de-duplicates streamed assistant messages, and multiplies token usage by the per-model rates in
`plugins/cost-dashboard/pricing.json`. `scripts/serve_dashboard.py` serves the same page live. Python 3 standard library only. Each session in the data (`/data.json`) also carries its active time, with idle gaps over 10 minutes removed, for tooling built on top of it.
No rules and no hooks: there is no runtime event to intercept, so this plugin is a command only.

## Tests

```zsh
python3 -m unittest discover -s cost-dashboard/tests -v
```

Run from the repo root. The tests build synthetic session logs, so they need no real data. The few that run the page's script need
`node` and are skipped without it.

## Caveats

- Costs are **estimates**. `pricing.json` holds per-model rates in USD per million tokens, copied from
  [Anthropic's pricing page](https://platform.claude.com/docs/en/about-claude/pricing) and stamped with the date
  they were checked. Cache-read prices are a different fraction of the input price for different models, and
  the logs record whether each cache write used the 5-minute or 1-hour cache, so both are priced per call.
  A model that matches no entry uses the fallback rate and is flagged on the dashboard. Fast mode, batch
  and `inference_geo: us` (1.1x) are not priced: calls using them are flagged and priced at the standard rate.
  Update `pricing.json` and its `verified` date when prices change.
- Subagent transcripts stored in separate files count toward the session total and the
  "Subagent" column, but cannot always be tied to a specific task row.
- Subscription plans (Pro/Max) are not billed per token; the numbers show API-equivalent value.

## Uninstall

```zsh
./uninstall.zsh
```
