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
nothing, serves only the page, `/data.json` and (when there are A/B runs) `/raw/<session id>`, binds to `127.0.0.1`, and refuses requests that name any other host; from another
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
| **Sessions** | Which sessions cost the most? Paged, sortable (newest first by default; click Cost to rank by spend), searchable; click a row for its tasks; Project ▸ expands to show the first prompt |

A "task" is one user prompt and everything Claude did in response, including subagents spawned in that turn.

### Nested runs: a solver under the session that launched it

When one session starts a run (an orchestrator handing a task to a solver with `run-ab.zsh solve`, or driving an A/B arm), the Sessions tab
shows that run's session **nested under the session that launched it**: the launching row opens (▸ to ▾) to its runs, so you can see which
model orchestrated and which model did the work:

- The launching row gets an `ORCHESTRATOR` tag and nothing else added: its Model, calls, tokens and Cost are its own, and each nested row shows
  its own, so the orchestrator's model and the solvers' models read side by side.
- The launching row is closed until you open it, and opening it shows its runs in place of its own task list (a launcher can have hundreds of
  prompts). A search shows the matching nested rows even while it is closed.
- Each nested row carries `SOLVER` (a run made by `solve`) or `A/B` (an arm) and its own model and cost, indented with a gold rule.
  Click it to expand it like any session. A run's session is nearly always a single prompt (a solver or a headless fix session), which would only
  repeat the row, so it shows no Tasks count and opens to the **individual model calls** it made instead: the time of each call, **what it did** (`Bash: pytest -q`, `Read: docs/plans/0001.md`,
  `Edit: wordfreq.py`, or the start of its reply; the first tool and `(+N more)` when it ran several; the full text is the tooltip), its model and
  effort, tokens in and out, dollars in and out, and its cost (a subagent's call is marked and its cost also sits in the Subagent column). The
  calls follow the table's sort like every other level, so under Last active ↓ the newest call is first. The time on a call or task row is right-aligned,
  under the end of the dates above it. A key or token in a command is replaced
  by `[secret]`. The calls are listed for run sessions only, which keeps the page small. One with several tasks, such as an arm someone typed more prompts into, keeps
  its count and opens to its tasks as usual. Nested rows follow the table's sort: the same column and the same arrow as the top level, so
  newest first under Last active ↓, oldest first under ↑ (equal values keep the order the runs started).
- Paging and the count cover top-level sessions only. A search keeps a parent when its own row or any nested row matches, and shows
  just the matching nested rows.

The link is read from the launcher's own log: a Bash call whose command is `run-ab.zsh` (or `solver.zsh`) followed by `run`, `resume`,
`solve`, `review-loop` or `review-round` and the run's name. Nothing in the run scripts has to record it, so it works on logs you already
have. If two sessions launched the same run, the earliest wins. A run whose launching command appears in no logged session (it was typed
in a terminal that Claude Code did not log, or built from a shell variable) stays at the top level, still tagged `SOLVER` or `A/B`.
The new row fields are `parent`, `kind` and `call_list` (one entry per model call, with `what` it did), present only on A/B-tagged sessions.

### Raw logs for run sessions

Served (not a saved snapshot), a run's session links to its **raw session log**: a `raw ↗` link after its tag, and the time on each of its call
rows (in both the Sessions and the A/B tabs). It opens `/raw/<session id>` in a new tab as plain text, one JSON line per log entry, so you can
see everything behind a call's label and cost. This is the one place the server hands out file content, so it is narrow on purpose:

- **Run sessions only.** It reads `<runs folder>/<run>.session/**/<id>.jsonl` and nothing else. Ordinary sessions, subagent logs and any other
  path are 404. The id may hold only letters, digits, `_` and `-`, so no request can name a path, and a file that resolves outside the runs
  folder (a symlink, say) is refused.
- **Masked.** Keys and tokens (`sk-ant-…`, GitHub and AWS keys) are replaced by `[secret]` as the text is served; the file on disk is untouched.
  Everything else in the log, including prompts and tool output, is shown as logged.
- **Same rules as the rest.** Read-only, the same `Host` check, `no-store` and `nosniff`; a log over 64 MB is refused.
- **Off without a runs folder,** and absent from a saved page, which has no server to link to.

### A/B tab (only when there are A/B runs)

When `--ab-root` (default `$AB_RUNS_DIR`, else `~/experiments/runs`) holds runs from auto-mode's `ab-docker` scripts, a fifth tab,
**A/B**, shows them side by side: one **Cost** per run (Claude and Copilot together), Claude calls and tokens in and out, Copilot reviews, rounds to
clean, findings per round, and wall time. Open a run to see its steps in order: the arm session, each Copilot review round, each headless fix.
Every step has a single Cost, whoever incurred it: a Claude step's cost is priced from its session log, and a Copilot review's is an average.

**Grouping.** Runs are named `<plan>-<model>-r<N>`, so the table groups them: a **plan** row (`leave-engine-docs`) holds its **round** rows
(`leave-engine-docs-r4`), and each round holds the runs of its arms side by side (`…-fable-r4`, `…-sonnet-r4`). A group row shows the sums of
its runs (Claude tokens in and out, Cost, Copilot reviews, fixes, wall time), the models used, and `N of M clean` for the runs that had
reviews. A `≥` on a cost means a run in the group has no session logs, so the figure is a lower bound. A level with one child collapses into
it, so a lone run is a plain row. Models are drawn as on the Sessions tab (same swatch and `model · effort` label; a run is labelled by its main thread's model), and a call that launched a subagent is followed by a `⤷ <agent>` header row and the agent's calls, indented. A pilot's arms (`pilot-p1-a`, `-b`, `-c`) form one group row (`pilot-p1`). The **Search runs** box above the
table keeps the runs whose name or model contains the text, and the groups of those runs. Click a row (or press Enter) to open it: a plan opens to its rounds, a round to its runs, and a run to its
steps (**Arm session**, **Solve**, each **Review N** with what Copilot found, each **Fix N**), each with its own calls, tokens and cost. A step
that made Claude calls opens again, to **each call**: its time, what it did (`Bash: pytest -q`, `Edit: wordfreq.py`, `reply: …`, with a subagent's
call marked), its model, tokens in and out, and its cost, oldest first. A Copilot review made none, so it is a plain row; calls that fall
outside every step are listed the same way under "Outside any step". There is no separate steps table: everything a step shows is in the
row under its run. **Expand all** and **Collapse all** open or close everything. No cell
wraps; when the table is wider than the window it scrolls sideways and the run-name column stays pinned on the left. The plan, round and run rows start collapsed at the top level. `-fable`, `-sonnet`, `-opus`, `-haiku`, `-model-a`, `-model-b`
and a following `-loop` count as the model part of a name; any other name is its own plan.

A run made by `run-ab.zsh solve` has one headless step, `solve`, which is priced and labelled like an arm session.

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
  "Subagent" column. Since 0.5.0 each one is also put on the task row that launched it: the subagent's
  `agent-X.meta.json` names the tool call (`toolUseId`) that started it, and the task whose assistant
  message made that call gets the cost, so the task rows add up to the session. An ordinary session's task
  row lists the subagent under its prompt as `⤷ <agent type> · <model> $cost` and fills its Subagent cell; a
  run's task row leaves both out, because the subagent has its own header row among the calls (below). A
  subagent log with no meta file, or one naming a tool call that is not in the main log, stays on the
  session row only.
- **Run sessions with several tasks (0.5.0).** An A/B run's session with one task opens straight to its
  individual calls. One with several tasks (an orchestrator and its subagents) opens to its tasks in time
  order, and under each task the calls it made, so the Sessions tab shows the same call-by-call detail as the
  A/B tab. A call that launched a subagent (an `Agent` or `Task` tool call) is followed by a header row
  (`⤷ <agent type> · <model> · N calls`, with the agent's summed cost) and that agent's own calls, oldest
  first, indented and marked `[subagent]`. A subagent call whose launching call is not in the log is listed
  under "calls not tied to a task" instead of being dropped. A run's row and its task rows are labelled
  by the model that ran the main thread (the orchestrator), from the calls that are not a subagent's, and
  the subagent's model shows only in the `+N` and in its own rows, so a cheap orchestrator is not relabelled
  by an expensive agent.
- Subscription plans (Pro/Max) are not billed per token; the numbers show API-equivalent value.

## Uninstall

```zsh
./uninstall.zsh
```
