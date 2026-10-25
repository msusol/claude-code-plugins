---
description: Ticket-driven sweep of docs/plans/*.md and docs/plans/TODO.md to find and archive stale entries tied to a given ticket number
paths:
  - docs/plans/**/*.md
  - docs/plans/TODO.md
---

# Bug-bash ticket cleanup

When the user gives a ticket number and asks for a "bug bash" (or otherwise
asks to sweep `docs/plans/` for stale entries related to that ticket), walk
`docs/plans/*.md` and `docs/plans/TODO.md` looking for everything tied to
that ticket, and archive what's actually done — rather than leaving
completed work scattered across live planning docs as noise for the next
reader.

This is a narrower, ticket-scoped sibling of `planning-desync-cleanup.md`
(which handles a *heavy*, repo-wide desync between plan files and
`TODO.md`) and reuses its source-of-truth and archiving mechanics. Reach for
this rule when the scope is "everything about ticket X", and reach for
`planning-desync-cleanup.md` when the scope is "the whole TODO.md looks out
of sync."

## 1. Locate everything tied to the ticket

- Check the `tickets:` front matter of numbered plans too, then grep `docs/plans/**/*.md` and `docs/plans/TODO.md` for the ticket key
  (exact match, e.g. `PROJ-1234`) and for its branch names
  (`feature/PROJ-1234-*`, `bugfix/PROJ-1234-*`, `chore/PROJ-1234-*`) in case a
  plan references the branch rather than the key.
- Also check `docs/plans/archive/` — if the ticket's work was already
  archived, say so and stop rather than re-processing it.
- Read each matching plan file in full, not just the matched line, since
  the ticket's work may span multiple sections of a larger plan.

## 2. Classify each hit

For each plan file and each `TODO.md` entry tied to the ticket, classify it:

- **Done and stale** — the checklist item(s) are checked off, or the
  described work is verifiably shipped (confirm against live state per
  `planning-ai-skepticism.md` — don't trust a stale "done"-looking comment
  without checking the actual code/branch/PR), and nothing else in the
  owning plan file still references open work.
- **Still open** — unchecked tasks, open questions, or follow-ups remain.
  Leave these alone.
- **Partially done** — some tasks for the ticket are complete, others
  aren't, inside the same plan file. Do not archive the whole file; only
  touch the ticket's own completed items (see step 4).
- **Unrelated** — matched the grep but isn't actually about this ticket
  (e.g. a coincidental substring match). Leave alone.

## 3. Confirm before archiving

Before moving or deleting anything, tell the user what was found: which
plan file(s), which `TODO.md` section(s), and which classification each
fell into. Get explicit confirmation before archiving — this follows the
same pause-and-confirm discipline as `planning-desync-cleanup.md` step 2,
scoped to just this ticket's hits instead of the whole repo.

## 4. Archive mechanics

- **Whole plan file fully resolved for this ticket, and the plan file is
  only about this ticket**: archive it per `planning-docs-plans.md`'s
  "Archiving completed plans" section (`mv` to `docs/plans/archive/`,
  update `TODO.md` and `docs/index.md`). The file keeps its `NNNN-` prefix, and its front matter `status`/`date` are updated as that section describes. `plan-bash <NNNN>` runs the same archive by plan number.
- **Plan file partially resolved, or a plan covers more than one ticket**:
  do not move the file. Instead:
  - Check off the ticket's own tasks in both the plan file and its
    `TODO.md` section.
  - Add a short inline note next to the ticket's resolved section, e.g.
    `_PROJ-1234 work completed 2026-10-01; see commit/PR <ref>_`, so a
    future pass (or a future bug-bash on a different ticket) doesn't
    re-flag it.
  - Leave the rest of the plan file and its other `TODO.md` tasks exactly
    as they are.
- **`TODO.md` entries with no corresponding open plan work**: remove the
  checked-off line(s) for this ticket once confirmed, same as a normal
  completed-task cleanup — don't leave long-done checkboxes accumulating.

## 5. Check the ticket's own status in the issue tracker

**This step is not optional when step 2 classified the ticket's work as
"done and stale."** That classification already required confirming every
cited PR/commit is merged and the work is live — those are exactly the
conditions `planning-jira-ticket-transitions.md` uses to justify
transitioning a ticket to Done. A bug-bash that cleans up the docs trace of
a ticket's work but leaves the ticket itself sitting in Backlog/Selected/In
Progress is an incomplete cleanup, not a finished one — the tracker ticket is
as much a stale trace of the old work as the TODO.md entry was.

- Look up the ticket's current tracker status before finishing the bug-bash.
- If it's already in a terminal status (Done, or that workflow's closest
  equivalent), nothing to do — say so.
- If it is not, tell the user explicitly: "PROJ-XXXX's docs trace is
  cleaned up, but the ticket itself is still <status> — want me to
  transition it to Done?" Don't let the cleanup read as complete without
  surfacing this.
- Transition only after the user confirms, per
  `planning-jira-ticket-transitions.md`'s own confirmation step, and add
  the evidence comment that rule requires (commit hash/PR link/live-check
  output) — the same evidence already gathered in step 2 usually suffices
  verbatim.
- If the sweep also turned up a comment worth posting for other reasons
  (e.g. the cleanup itself as evidence of completion), that also follows
  `planning-jira-ticket-transitions.md` — still gated on the user's
  go-ahead, but don't skip the status check above just because a comment
  wasn't obviously warranted.
- If the sweep for this one ticket turns up evidence of a *heavier*,
  repo-wide desync (many unrelated stale entries, not just this ticket's),
  stop and flag it — switch to `planning-desync-cleanup.md`'s full
  workflow rather than silently expanding scope.

## 6. Return to the starting branch

Once the cleanup commit's branch is pushed, PR'd, and merged, switch the
local working tree back to whatever branch you were on when the bug-bash
started (usually `develop` in a GitFlow-lite repo — see
`git-branch-naming.md` — or `main` in a single-branch repo) and make sure it's fast-forwarded to match the
merge. Don't leave the working tree sitting on the now-deleted cleanup
branch just because the task that created it is done — a bug-bash is a
drive-by cleanup, not a reason to change what branch the user is
nominally working from afterward.

- If the merge command itself already fast-forwarded the starting branch
  as a side effect (e.g. `gh pr merge` fetching and updating `develop`
  locally), a plain `git checkout <starting-branch>` is enough.
- If not, `git checkout <starting-branch> && git pull --ff-only` (or
  equivalent) after confirming the working tree is clean.
- This applies whether the PR was merged by this session or by the user
  manually — check `git branch --show-current` before ending the bug-bash
  and switch back if it still points at the cleanup branch.

## What not to do

- Don't archive a plan file just because this ticket's piece of it is
  done — check the whole file for other open work first.
- Don't delete `TODO.md` history for other tickets while sweeping for one
  ticket — stay scoped to what was asked.
- Don't skip the live-state verification in step 2 — a `TODO.md` checkbox
  or plan note can be stale in either direction (marked done but not
  shipped, or marked open but actually shipped).
- Don't finish a bug-bash having cleaned up the docs trace while leaving
  the ticket itself stale in the tracker — step 5's status check is part of the
  cleanup, not an optional add-on.
