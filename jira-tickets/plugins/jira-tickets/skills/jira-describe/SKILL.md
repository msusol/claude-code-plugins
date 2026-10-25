---
name: "Jira Ticket Descriptions"
description: >
  Use whenever filing a new Jira ticket, or adding a new round of findings/
  addendum to an existing one — for any Jira project or instance,
  through any of the Atlassian gateway tools. Trigger on
  "file a ticket for this", "update the ticket description", "add an
  addendum to <TICKET>", "post an update to <TICKET>", or any request that
  edits or creates a Jira issue's description.
---

# Jira Ticket Descriptions

Full spec lives in the `docs` plugin's `planning-jira-ticket-descriptions.md`
rule — that's the single source of truth (it's auto-loaded into every
session via `CLAUDE.md`, so the guidance applies whether or not this skill
is explicitly invoked). This skill is kept only as a discoverable trigger
for "file a ticket"/"update this ticket" requests; it intentionally
duplicates none of the rule's content, to avoid the two drifting apart.

If you don't have the `docs` plugin installed, install it (see this repo's
top-level README) so the rule loads automatically — don't reconstruct the
guidance from memory or from an older cached copy of this file.

Covers: the required `## Current Status` + `## History` shape, when to
rewrite `Current Status` vs. only append to `History`, keeping `History`
entries short (3 to 5 sentences, findings only, no document or branch
bookkeeping, and a "See Full History" link at the bottom), archiving old
`History` entries to a repo file before the description hits Jira's size limit
(a bare 400 on a long description means check size first), `References` as
full clickable links to a ref that resolves today, description-edit vs.
comment, confirming before rewriting an existing ticket, and — critically —
which Atlassian tool you have and whether it renders real ADF headings/
lists or only a plain-string paragraph (build ADF by hand for the
`jira_update_issue_<instance>`-shaped gateway tools; real Markdown works
through the generic `claude_ai_Atlassian` connector).
