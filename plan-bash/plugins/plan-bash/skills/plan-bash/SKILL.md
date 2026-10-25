---
name: "Plan Bash Plan Archiving"
description: >
  Use when the user gives a plan number and asks for a "plan bash", or asks
  whether a numbered plan under docs/plans/ is done or should be archived.
  Trigger on "plan bash 007", "plan-bash 7", "archive plan 007", "is plan 007
  done", "clean up plan 007", or "plan bash" with no number (list the plans
  and ask which). For a ticket key instead of a plan number, use bug-bash.
---

# Plan Bash Plan Archiving

Full procedure lives in the `docs` plugin's `planning-plan-bash-archive.md`
rule — that's the single source of truth (it's auto-loaded into every
session via `CLAUDE.md`, so the guidance applies whether or not this skill
is explicitly invoked). This skill is kept only as a discoverable trigger
for "plan bash"/plan-archive requests; it intentionally duplicates none of
the rule's content, to avoid the two drifting apart.

If you don't have the `docs` plugin installed, install it (see this repo's
top-level README) so the rule loads automatically — don't reconstruct the
procedure from memory or from an older cached copy of this file.

Covers: resolving a plan number (`007`, or `7`) to exactly one
`docs/plans/###-*.md` file, reading the plan and its `TODO.md` section,
classifying every task (done, deferred, dropped, open, unverifiable),
verifying "done" against live state, comparing the plan's front matter
`status` with its checkboxes, reporting and confirming before any change,
and archiving to `docs/plans/archive/` with the same filename so the number
never changes. It never archives a plan with open or unverifiable tasks
without the user's explicit say-so.

Ticket-keyed sweeps of every plan that mentions a ticket are the sibling
`bug-bash` skill's job.
