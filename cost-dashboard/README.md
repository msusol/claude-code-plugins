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
/cost-dashboard:dashboard --ab-root ~/experiments/runs   # point the A/B tab at another runs folder
/cost-dashboard:dashboard --no-ab-sessions               # keep A/B runs out of the other tabs
/cost-dashboard:dashboard serve              # a live page on http://127.0.0.1:8780/, rebuilt as your logs grow
/cost-dashboard:dashboard serve --port 8770 --days 0
```

Without `serve` the output is `~/.claude/cost-dashboard.html` (self-contained, no network, light/dark aware), a snapshot.
With `serve` a small local server keeps the page current: reload the browser to see new costs. It builds in memory and writes
nothing, serves only the page and `/data.json`, binds to `127.0.0.1`, and refuses requests that name any other host; from another
machine use an SSH tunnel to the port.

The default port is **8780**. It was 8766 up to 0.2.0: a port other local dashboards on the same host also use, so `serve` could
fail with "address in use". Pass `--port N` to use another, and update any bookmark or SSH tunnel that pointed at 8766. If the port is taken, the
server says so and exits rather than picking another.

## What it shows

Four tabs, every table with **tokens in and out and the dollars for each side**, the figures models are compared on:

| Tab | Answers |
|---|---|
| **Overview** | What did I spend? Totals, averages, cache hit rate, cost per day, cost by model |
| **Model & effort** | How do models, and effort levels on one model, compare? Cost by model and effort (effort is always shown with its model), a model x effort grid, cost per task, cost per day |
| **Context** | Why does it cost this much? Cost by token type, the price per 1M tokens for each model, and how the context grows call by call (with compactions) |
| **Sessions** | Which sessions cost the most? Paged, sortable, searchable; click a row for its tasks; Project ▸ expands to show the first prompt |

A "task" is one user prompt and everything Claude did in response, including subagents spawned in that turn.

### A/B tab (only when there are A/B runs)

When `--ab-root` (default `$AB_RUNS_DIR`, else `~/experiments/runs`) holds runs from auto-mode's `ab-docker` scripts, a fifth tab,
**A/B**, shows them side by side: one **Cost** per run (Claude and Copilot together), Claude tokens in and out, Copilot reviews, rounds to
clean, findings per round, and wall time. Pick a run to see its steps in order: the arm session, each Copilot review round, each headless fix.
Every step has a single Cost, whoever incurred it: a Claude step's cost is priced from its session log, and a Copilot review's is an average.

It reads two things per run, both written by `run-ab.zsh` (auto-mode 1.9.0 or later):

| File | What it holds |
|---|---|
| `<run>.reviews/steps.csv` | One row per step: `start,end,type,round,model,commit,detail` (UTC). A review row carries `pr`, `findings`, `status`, `premium_requests`, `effort`. |
| `<run>.session/` | The Claude Code session logs of the run's containers, priced with the same rates as every other tab. |

Each Claude call is assigned to the step whose time window it falls in (a few seconds of slack either side); calls outside every step are
shown on their own line and still count in the run's total. A run with no session logs (it ran before session capture) shows – for Claude
cost, because that cost is unknown, not zero.

**Copilot is a review count, plus an estimated average cost.** GitHub bills code review in AI credits ($0.01 each), not per request, and no
API gives a per-review price. `pricing.json` ships `copilot_usd_per_review` at 0.29: the average from GitHub's AI usage page (234.92 credits,
$2.35, over 8 reviews in Nov 2026), with its source and date beside it. A review step's Cost is that rate and is marked `~`; a run total that
includes one is marked `~` too. A real review costs more or less with its size, and on a plan with included credits you may be charged nothing.
Set it to `null` and reviews have no cost, so a run total is Claude only (a run with no session logs has no total, because leaving Claude
out would mislead). Re-measure it from github.com/settings/billing/ai_usage. In `steps.csv` the review count is written under the
historical name `premium_requests`.
With no A/B runs the tab is hidden and the data is unchanged.

**A/B sessions count in every tab.** The arms' containers log outside `--root`, so the other tabs would otherwise leave out what the A/B runs cost.
Each `<run>.session` folder under `--ab-root` is also read as ordinary sessions, named after the run (not the container's `work` folder) and
tagged **A/B** in the Sessions and Context tabs; search `a/b` to list them. Each session is counted once: the A/B tab's Claude total for a run
equals the sum of that run's sessions. A run folder with session logs but no `steps.csv` (for example an earlier smoke test) counts in the other tabs
and has no A/B tab entry. Pass `--no-ab-sessions` to leave them out of the other tabs; the A/B tab still shows them. If `--root` itself contains the
runs folder, those logs are read once, tagged, and not a second time.

**[guide/GUIDE.md](guide/GUIDE.md)** walks through each tab with example data and charts, and explains the concepts behind the numbers
(in vs out tokens, context, prompt caching, compaction, effort). [guide/example-dashboard.html](guide/example-dashboard.html) is the example
dashboard to open in a browser.

## How it works

`plugins/cost-dashboard/scripts/build_dashboard.py` reads `~/.claude/projects/**/*.jsonl`,
de-duplicates streamed assistant messages, and multiplies token usage by the per-model rates in
`plugins/cost-dashboard/pricing.json`. `scripts/serve_dashboard.py` serves the same page live. `scripts/ab_steps.py` joins an A/B run's step log to its session logs. Python 3 standard library only. Each session in the data (`/data.json`) also carries its active time, with idle gaps over 10 minutes removed, for tooling built on top of it.
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
