# Jira ticket descriptions: living summary + append-only history

A ticket that gets multiple rounds of investigation/addendums (a comment per
round, or description edits per round) rots the same way an out-of-sync
`TODO.md` does: each round adds detail, but nobody rolls the *net effect*
back up, so a reader opening the ticket cold has to reconstruct current
status by reading every round in order. Apply the same "mutable current-state
summary + append-only log" shape used for ADRs/investigate-docs
(`planning-docs-adr.md`, `planning-docs-investigate.md`) to Jira ticket
descriptions instead of a markdown file.

## Required shape

Every ticket description this applies to (see "When this applies" below)
keeps two parts, in this order:

1. **`## Current Status`** — a short paragraph (3-6 sentences) stating what
   is true *right now*: the real, net conclusion after every round of
   investigation so far, not a chronological narrative. **Rewritten in
   place** on every update that changes the actual state of the ticket —
   never just appended to. A reader should be able to read only this
   section and know where things stand without opening a single comment.
2. **`## History`** — an append-only, reverse-chronological log, one dated
   entry per round (`### YYYY-MM-DD — <short label>`), each entry a few
   sentences on what was found/done and why it changed (or didn't change)
   the current status above. Never edit or delete a past entry — if a past
   entry turns out to be wrong, add a new entry saying so and update
   `Current Status` accordingly; don't silently rewrite history.

The original ticket description content (the initial ask/context) becomes
the first `### YYYY-MM-DD — Filed` entry in `History` when this structure is
first applied to an existing free-form ticket, rather than being discarded.

## When to update `Current Status` vs. just adding a `History` entry

- **Both**, whenever a round of work changes what's actually true about the
  ticket: a hypothesis gets confirmed/refuted, scope changes, a blocker
  appears/clears, or a fix ships. `Current Status` must reflect the new
  reality; `History` records how you got there.
- **`History` only**, when a round adds detail or evidence without changing
  the net conclusion (e.g. a second confirmatory test run that agrees with
  the first) — note it in `History`, leave `Current Status` as-is unless its
  wording specifically overclaimed confidence the new evidence refines.
- Never leave `Current Status` describing a state that's since been
  superseded just because the correction only happened in a `History` entry
  or a comment — that's exactly the rot this convention exists to prevent.

## Where the update goes: description edit vs. comment

Prefer editing the description itself (both sections) as the durable
record, since that's what a reader sees first and don't need to scroll a
comment thread to find. Use `jira_update_issue_*` /
`editJiraIssue`/`updateConfluencePage`-style tools to rewrite the
description in place. A comment can *additionally* flag a round happened
(useful for @-mentioning someone or a Slack cross-post per
`planning-slack-wcp-updates.md`), but the description's `Current Status` +
`History` should never depend on comments to stay accurate — a ticket
should be understandable from its description alone.

## When this applies

Apply this structure to a ticket once it's had (or is clearly heading
toward) more than one round of real investigation/findings — a ticket that
gets filed and closed in one round doesn't need the ceremony. Retrofit an
existing ticket into this shape the first time you're asked to add a
second/later round of findings to it, rather than leaving the first round
as loose free-form text and only structuring rounds two onward.

## Confirm before rewriting an existing ticket's description

Rewriting a ticket's description (as opposed to adding a comment) is a
shared, team-visible edit to a document other people may be mid-read on or
have linked to — treat it like other outward-facing changes per
`planning-jira-ticket-transitions.md`'s "confirm before transitioning": do
the retrofit/rewrite once the user has confirmed it, not silently as a side
effect of investigating.

## Markdown headings vs. real Jira formatting — check which tool you have

Jira Cloud stores descriptions as ADF (Atlassian Document Format), not
Markdown. Which Atlassian tool is available for the target instance changes
whether `##`/`-`/`**bold**` syntax in the string you pass actually renders,
or shows up as literal punctuation:

- **Gateway tools shaped like `jira_update_issue_<instance>`/
  `jira_create_issue_<instance>`** (this org's per-instance MCP gateway,
  covering `hrsolutionsdev`/`dev`/`mineral` etc.): passing a plain string
  for `description` wraps it in **one ADF paragraph** — confirmed live
  (WCP-86, 2026-09-11; recurred and re-confirmed on WCP-112–115,
  2026-09-16): a description written with `##`/`-` Markdown came back
  verbatim as literal text inside a single paragraph node, not real
  headings/lists. **Markdown syntax in the string does not render**
  through this path.
  - To get real headings/lists through one of these tools, build the ADF
    document yourself instead of a plain string: a top-level `{"type":
    "doc", "version": 1, "content": [...]}` with `heading` nodes
    (`"attrs": {"level": 2}`) for `Current Status`/`History`, `bulletList`/
    `listItem` nodes for bullets, `text` nodes with `marks`
    (`{"type": "strong"}`, `{"type": "code"}`, `{"type": "link", "attrs":
    {"href": ...}}`) for inline formatting, and `paragraph`/`hardBreak`/
    `rule` nodes for prose, line breaks, and horizontal rules. Pass that
    object as `fields.description` (or `fields.summary` for a plain string
    field, which has no such concern).
  - If building full ADF is overkill for a quick update, plain-text with
    `##`-style markers is still an acceptable **fallback** — it preserves
    the Current-Status/History structure for a reader scanning the raw
    text, it just won't render as styled headings in Jira's UI. Say so
    plainly if you take this shortcut rather than silently under-delivering
    on "markdown format."
  - These same gateway tools are typically **fields-only** — no comment or
    transition endpoint, and no issue-link endpoint either (confirmed live,
    WCP-86: a `fields.comment` update and a `fields.status` update both
    400'd; WCP-115, 2026-09-16: `fields.issuelinks` with an `add` operation
    also 400'd — issue links need the dedicated `/issueLink` REST endpoint,
    which this tool shape doesn't expose). If a request also needs a
    comment posted, a status transitioned, or a formal issue link created
    and only this kind of tool is available, say so explicitly rather than
    silently skipping it — a cross-reference in the description text is a
    reasonable substitute for a link, but say plainly that it isn't a real,
    queryable Jira link.
- **The generic `claude_ai_Atlassian` connector tools**
  (`createJiraIssue`/`editJiraIssue`/`addCommentToJiraIssue`, gated to
  whichever cloud site is explicitly granted to the user — check via
  `getAccessibleAtlassianResources` first, since an ungranted `cloudId`
  errors outright) genuinely support **real Markdown** via
  `contentFormat: "markdown"` on the relevant parameter, converted to ADF
  server-side. Prefer this path when the target instance is reachable
  through it — real headings/lists render correctly with no ADF
  hand-construction needed.

Check which path is actually available for the target instance before
promising Markdown rendering — don't assume the fancy path works just
because it exists for some other Jira site in the same session.

## Relationship to other rules

This is a description-content convention, independent of
`planning-jira-ticket-transitions.md` (which governs *status* transitions)
and `planning-slack-wcp-updates.md` (which governs Slack posts about a
ticket) — a ticket can update its `Current Status` section without its
Jira status or Slack presence changing, and vice versa.
