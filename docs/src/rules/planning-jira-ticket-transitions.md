# Jira ticket transitions as work happens

When a conversation is actively working on something tied to a Jira ticket (the
ticket was named by the user, found via search, or is the obvious owner of the
code/doc being changed), keep the ticket's status in sync with the real work
as it happens — don't leave it silently stale in Backlog while a PR ships.

## When to transition

- **To "In Progress"**: the moment real work starts on a ticket still sitting
  in Backlog/Selected for Development — a branch is cut, a PR is opened, or
  a fix is being written against it this session.
- **To "Done"** (or that project's closest terminal status — see below): once
  the fix is confirmed live, not just merged. "Confirmed live" means checked
  against the actual running system/repo state (a live `grep`/`git log` check,
  a passing test, a redeployed service), per `planning-ai-skepticism.md` — a
  merged PR alone is a strong signal but re-verify before closing if there's
  any doubt the merge actually shipped what the ticket asked for.
- **Leave alone**: tickets the conversation didn't touch. Don't sweep through
  unrelated backlog items looking for things to close — only transition
  what this session actually worked on or was asked to check.

## Before closing, add a comment with the evidence

Always add a comment recording *how* it was confirmed done before transitioning
to a terminal status — a commit hash, PR number/link, or a live command's
output. A bare status flip with no comment leaves the next reader unable to
tell whether it was verified or just assumed.

## Terminal-status quirks per workflow

Not every Jira workflow has the same terminal states — check the issue's
available transitions (or that repo's own `CLAUDE.md`) rather than assuming
"Done" always exists. Some workflows have no "Won't Do"/cancelled state at
all — in that case, to retire a ticket superseded by other work, comment with
a pointer to the replacement and transition to the closest terminal status
instead of leaving it open indefinitely.

## Don't over-scope a rename/fix to the ticket's full ask

When a ticket's description proposes a broad change (e.g. renaming a
production identifier across multiple repos and live data, not just a file)
and the work actually done only closes part of it, do **not** transition to
Done. Say plainly which slice was completed and which parts remain, and leave
the ticket open (or add a comment noting partial progress) — closing a
partially-addressed ticket erases the remaining scope for whoever looks at it
next.

## Confirm before transitioning

Transitioning a ticket's status is a shared, team-visible action — treat it
like other outward-facing changes: do it once the user has confirmed the
ticket and target status (explicitly, or unambiguously by asking to "close
this" / "mark it in progress"), not automatically as a side effect of writing
code or opening a PR.
