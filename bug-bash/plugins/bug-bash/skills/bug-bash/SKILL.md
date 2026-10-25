---
name: "Bug Bash Ticket Cleanup"
description: >
  Use when the user gives a ticket number and asks for a "bug bash", or
  otherwise asks to sweep docs/plans/ for stale entries tied to a specific
  ticket. Trigger on "let's do a bug bash", "bug bash PROJ-1234", "clean up
  the plans for <TICKET>", or "archive anything related to <TICKET> in
  docs/plans".
---

# Bug Bash Ticket Cleanup

Full procedure lives in the `docs` plugin's
`planning-bug-bash-ticket-cleanup.md` rule — that's the single source of
truth (it's auto-loaded into every session via `CLAUDE.md`, so the guidance
applies whether or not this skill is explicitly invoked). This skill is kept
only as a discoverable trigger for "bug bash"/ticket-cleanup requests; it
intentionally duplicates none of the rule's content, to avoid the two
drifting apart.

If you don't have the `docs` plugin installed, install it (see this repo's
top-level README) so the rule loads automatically — don't reconstruct the
procedure from memory or from an older cached copy of this file.

Covers: grepping `docs/plans/**/*.md` and `docs/plans/TODO.md` (and
`docs/plans/archive/`) for a given ticket key and its branch names,
classifying each hit (done-and-stale / still-open / partially-done /
unrelated), confirming before archiving, the archive mechanics for a
fully-resolved plan file vs. a partially-resolved one, and when to escalate
to the broader `planning-desync-cleanup.md` workflow instead.

For the same cleanup keyed by plan number instead of ticket key ("plan bash 0007"), use the `plan-bash` skill.
