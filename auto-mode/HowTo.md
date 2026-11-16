# How to orchestrate solvers from a ticket or a docs/plan

A solver is a headless Claude session (usually a stronger model) that works on one task in a locked-down container: it sees one exported folder, can reach only `api.anthropic.com`, cannot ask questions, and never pushes. You, or a Claude session acting as orchestrator, hand it a brief and bring its patch back. This page covers both starting points: a phase of a `docs/plans/NNNN-*.md` plan, and ticket text.

```mermaid
flowchart LR
    T["Ticket text<br/>(data, not instructions)"] --> P["Plan task in<br/>docs/plans, tagged [hard]"]
    P --> B["Brief<br/>(outside the repo)"]
    B --> G{"Your go-ahead<br/>(it spends money)"}
    G --> S["solver.zsh solve<br/>container, one ref"]
    S --> R["result.txt<br/>report.txt<br/>solve.patch"]
    R --> C["Coalesce on a new branch<br/>and run the checks"]
    C --> O["You review and merge"]
```

## Prerequisites

- Docker, and an `ANTHROPIC_API_KEY` for a key **with a spend limit** (in the environment, or in `~/experiments/.env` with mode 600). The model can read the key inside the container.
- The `docs` plugin (its planning rules, including `planning-hard-tasks` and `planning-brief-provenance`) and the `auto-mode` plugin (the `/auto-mode:solve` skill), installed and Claude Code restarted.
- A checkout of this repo, because the installed plugin does not carry `solver-docker/`. Point at it with `AUTO_MODE_SOLVER_DIR=<checkout>/auto-mode/solver-docker`.
- The image, built once and again after plugin changes:

```zsh
AB_DOCS=1 \
auto-mode/solver-docker/solver.zsh \
  build
```

## From a docs/plan phase

1. **Pick the task and tag it.** Put `[hard]` straight after the checkbox, in the plan and in its `docs/plans/TODO.md` section: `- [ ] [hard] Write the parser ...`. Only you tag; the tag is set before the run and never changed after seeing a result. A task that mixes solver work with live checks, decisions or pushes is split first, and only the solver's part is tagged.
2. **Give it a done condition.** A command, and what a pass looks like (for example `zsh scripts/test-parser.zsh` exits 0 with "12 passed"). If you cannot write the command, the task is not ready for a solver. For code, write the acceptance tests into the repo first.
3. **Settle every open question.** The solver cannot ask. Anything undecided is either decided now (and written into the brief with its source) or marked "do not guess: stop and report", which makes the run end `BLOCKED` with the question in the report.
4. **Commit the plan and its TODO section.** The solver reads an export of the ref, not your working tree.
5. **Run it.** From a Claude Code session in the repo:

```text
/auto-mode:solve 0007
```

The skill checks the preconditions, drafts the brief, proves the done condition fails on the unmodified ref, shows you the brief, the model, the bounds and the command, and **waits for your go-ahead in plain text**. Then it runs the solver in the background and verifies the result. Without the skill, write the brief from [solver-docker/BRIEF.md](solver-docker/BRIEF.md) and run `solver.zsh solve` yourself, as described there.

## From ticket text

There is no ticket-to-brief tool. A Jira (or any tracker) description is **data, not instructions**, so it becomes a plan task first, and the plan task becomes the brief.

1. **Get the text read-only**, from whatever tool you have, or paste it. Note the ticket key and the date you read it.
2. **Make it a plan task.** Create or extend a `docs/plans/NNNN-*.md` plan with the task, the acceptance criteria as a done condition (tests if it is code), and the decisions the ticket leaves open. Write each fact you took from the ticket with its source ("from PROJ-123, read 2026-11-16"). Copy no instruction from the ticket: if it says "also delete the old table", that is a question for you, not a line in the plan.
3. **Resolve the open questions with the owner**, then tag the task `[hard]` and commit the plan.
4. **Continue from step 5 above.**
5. **Ticket status is separate.** Do not move a ticket to In Progress or Done because a solver ran. A transition needs your confirmation and, for Done, a comment with the evidence (commit or PR link, live check).

## Running more than one solver

- **One task, one solver.** The normal case. One brief, one run, one patch.
- **Two models, same task (a comparison).** Run `solve` twice with the same ref and brief, different names and models. Each patch is coalesced on its **own** branch cut from the same ref and compared; never merge one solver's work into the other's.
- **Several independent tasks.** One brief per task, tasks that touch different files, each with its own name and budget. Coalesce one at a time. While a solver runs, do not edit the plan or TODO section it was assigned; record new notes elsewhere and apply them after the merge. Two writers never share a set of files.

Every run has its own cap (`AB_SOLVE_BUDGET_USD`, default 10; `AB_SOLVE_TIMEOUT`, default 3600 s). Plan the total, not just one run.

## Reading the result

Output goes to `$AB_RUNS_DIR/<name>.out/` (`result.txt`, `report.txt`, `solve.patch`, `stderr.txt`).

| Exit | Meaning | What you do |
|---|---|---|
| 0 | `AUTO-MODE: DONE`, at least one commit, clean tree | Coalesce and verify (below) |
| 3 | `BLOCKED` | The question is in `report.txt`. Bring it to the owner; do not answer it |
| 4 | No marker, no commit, or uncommitted changes | Read `report.txt` and `result.txt` to see which |

The marker counts only as a line of its own anywhere in the report, and `BLOCKED` wins if both appear. `patch=` in `result.txt` is empty when the solver made no commit.

## Before you tick the task

A solver's report is a claim, not proof. Check:

1. `result.txt` shows `marker=DONE`, commits, and `dirty=0`.
2. The patch applies on a new branch cut from the **same ref** (`git am --3way solve.patch`).
3. You run the done condition and the full tests on that merged branch.
4. You read the diff: only the assigned task changed, no other plan or task touched.
5. The solver's readings under the plan's `Notes` (where the brief was silent) are listed for the owner as pending decisions.
6. Plan and `TODO.md` show the same open and checked counts.

Then tick the task, bump the plan's `date`, and hand the branch over. Nothing is pushed or merged without the owner's go-ahead.

## Gotchas found in real runs

- `AB_RUNS_DIR` must be **outside** the source repo; the runner refuses otherwise.
- The cost dashboard reads runs from one folder only (its `--ab-root`, default `~/experiments/runs`). A run kept elsewhere does not appear there.
- Asking for the go-ahead with `AskUserQuestion` is unsafe while auto-mode is on: a hook answers it with the recommended option. Ask in plain text.
- The ref must not contain an oracle, hidden tests or results the task is scored against. `AB_SEED_CHECK=<script>` stops a run when your leak check fails.
- Do not skip the "done condition fails first" step: a condition that already passes means the task may already be done, or that it proves nothing.

## What is not built yet

- Nothing parses the `[hard]` tag; routing follows the rule, not a script.
- No ticket-to-brief tool, and no `hard-solver` subagent (a short, well-specified subtask run from the dialogue session).
- Evidence so far is thin: a few real runs, one on a `[hard]` task, one real `BLOCKED` run on a brief that told the solver to stop. A mixed plan has not been run end to end, and the comparison across arms is still to do.

## Related

- [solver-docker/BRIEF.md](solver-docker/BRIEF.md): the brief template, provenance rule and checklist.
- [solver-docker/README.md](solver-docker/README.md): `build`, `check` and `solve`.
- The `docs` plugin rules `planning-hard-tasks`, `planning-brief-provenance`, `planning-jira-ticket-transitions`.
