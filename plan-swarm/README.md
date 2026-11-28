# plan-swarm

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**Author:** Mark Susol

The `/plan-swarm` skill — give it one or more plan numbers (`plan-swarm 0008 0009`) and it runs their
open tasks in parallel waves of subagents, in dependency order.

## What it does

1. Resolves each number to one `docs/plans/NNNN-*.md` and checks the plan against its `TODO.md` section.
2. Builds a task graph: ID, `depends_on`, owned files, acceptance criteria, verify command.
3. Leaves out what a worker cannot do: tasks with no verify command, `[hard]` tasks (use `auto-mode:solve`),
   live checks, decisions, open questions. If nothing is left to dispatch it stops right there and spends nothing.
   Everything it left out comes back as a **Needs you** checklist, one line per item saying what to reply with.
4. Classifies each remaining task as a **worker task** (tracked files, judgment, a diff to merge) or a **background job**
   (a fixed command whose output is gitignored or needs resources a worktree lacks). Jobs run as background lanes the coordinator
   starts and checks itself, never as subagents; jobs on the same output share a lane.
5. Shows the waves and bounds (tasks, workers, one retry) and **asks before running**. Workers are in-session subagents on your subscription: no API key, no per-token bill, but they count against usage limits. For API-billed isolation use `auto-mode:solve`.
6. Per wave: one worktree subagent per ready task; the coordinator merges, runs each verify command and the
   full tests itself, then ticks the plan and `TODO.md` together and commits per task.
7. Reports a task/status/commit table and the readings workers chose where the brief was silent.

After the one go-ahead it runs to the end without further prompts, pausing only for a failed phase gate, a rate limit,
the task cap, or a worker that needs something only you can give (that goes on the Needs you list while unrelated tasks
keep running). A Stop hook or auto-mode answer never counts as a go-ahead. Each worker has a wall-clock limit
(`--worker-minutes`, default 20) enforced by the coordinator, and a run state file in `.git/plan-swarm/` lets
`--resume` continue after a dead session.

Workers never edit plan checkboxes, `TODO.md` or `docs/index.md`; only the coordinator does, which is what lets
two plans run at once. It does not push, merge to a protected branch, or archive (use `plan-bash` for that).

## When a task is not a worker task

plan-swarm hands **plan tasks that change tracked files** to subagents in worktrees and verifies them by tests. A fixed job
such as an ingest or an import is a different thing: no task to merge, and its output is usually gitignored, so a worktree
cannot carry it. The skill classifies each task (step 2, "Worker or background job") and runs the jobs itself as background lanes:
a plain process that costs no session usage while it waits, checked by its log and the files it wrote. A swarm worker is a
Claude instance that thinks and costs session usage. Jobs on the same output share a lane. For a job that is not in any
plan, run it the same way yourself. The skill's "When plan-swarm does not fit" section has the comparison table.

## Usage

```zsh
./plan-swarm/deploy.zsh
```

```text
/plan-swarm 0008
/plan-swarm 0008 0009 --max-workers 4 --max-tasks 8
/plan-swarm 0008 --dry-run
```

Install the `docs` plugin alongside it for the planning rules the skill cites.
