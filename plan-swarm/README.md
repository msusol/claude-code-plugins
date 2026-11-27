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
4. Shows the waves and bounds (tasks, workers, one retry) and **asks before running**. Workers are in-session subagents on your subscription: no API key, no per-token bill, but they count against usage limits. For API-billed isolation use `auto-mode:solve`.
5. Per wave: one worktree subagent per ready task; the coordinator merges, runs each verify command and the
   full tests itself, then ticks the plan and `TODO.md` together and commits per task.
6. Reports a task/status/commit table and the readings workers chose where the brief was silent.

Workers never edit plan checkboxes, `TODO.md` or `docs/index.md`; only the coordinator does, which is what lets
two plans run at once. It does not push, merge to a protected branch, or archive (use `plan-bash` for that).

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
