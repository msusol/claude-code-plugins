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
   entry per round (`### YYYY-MM-DD — <short label>`), each entry 3 to 5
   sentences (about 700 characters at most) on what was found/done and why it
   changed (or didn't change) the current status above; see "Keeping `History`
   entries short" below. Never edit or delete a past entry — if a past
   entry turns out to be wrong, add a new entry saying so and update
   `Current Status` accordingly; don't silently rewrite history. The one
   exception is moving old entries out of the ticket, or shortening them,
   after saving their original text in a repo file when the description gets
   too large or too wordy (see "Keeping the description under Jira's size
   limit" below). The ticket then ends its `History` with a "See Full
   History" link to that file, and records the move in no entry of its own.

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

## Keeping `History` entries short

(Found live 2026-10-17.) Entries written as a full account of the
round grew to 1,500 to 2,000 characters each, mostly bookkeeping about other
documents. That buried the finding and, with the size limit below, filled the
description. An entry says what was found or done, what is still not built or
still open, and how the status changed. The detail belongs in the spec, the
plan, the PR or the commit message, linked.

- **Length.** 3 to 5 sentences, about 700 characters at most. If it runs
  longer, the extra is detail that belongs elsewhere.
- **Leave out document and branch bookkeeping.** Which spec, plan or TODO was
  updated, which branches were pushed, that a PR was opened, ready or merged,
  and that older entries were moved or shortened (the "See Full History" link
  at the bottom covers that). The `References` section holds the current
  links.
- **Leave out "supersedes" notes.** Entries are dated snapshots; "local, not
  pushed" was true when written and does not need correcting later. Fix
  `Current Status` instead. Add a correcting entry only when an earlier
  finding turned out to be wrong, and then say what was wrong in one sentence.
- **Leave out lists and tooling detail.** No per-test lists (cite the test
  file or spec section), no commands, and no lint or type-check result unless
  it changes what can be claimed. One count, such as "186 passed, 0 failed",
  is enough.
- **One reference.** A commit or PR link when the work lives in one, as a real
  link (see "References are full links").

## Keeping the description under Jira's size limit

(Found live 2026-10-17.) A description that gets a dated entry per
round only ever grows. On one ticket two updates in a row came back as a bare
`400 Bad Request` with no message; the third went through only after eleven
History entries were moved out. The likely cause is Jira's description size
limit (32,767 characters is the usual field limit; not confirmed on that
instance, and the 400 gives no reason). Treat a bare 400 on a long
description as a size problem first, before trying other payload shapes.

Check before every update, not after a 400:

- **Count first.** Measure the characters of the text you are about to send
  (the text nodes, not the ADF wrapper). If the new description would be over
  about 24,000 characters (roughly three quarters of the limit), or `History`
  would hold more than 8 dated entries besides `Filed`, archive before
  publishing. Whichever trips first triggers it.
- **Keep `Current Status` short.** It is the section that grows by accident,
  because it is rewritten in place and tempts you to keep every open detail in
  it. If it is over about 1,500 characters or 6 sentences, cut it back to the
  net conclusion and leave the detail in `Open questions`, `References` or the
  spec. On that ticket it had reached about 3,600 characters.
- **Shrink before you archive.** If the size check trips but `History` holds 6
  or fewer entries besides `Filed`, archiving moves nothing. Cut `Current
  Status` to its cap, then shorten any `Open questions` bullet that repeats
  the spec or a `History` entry (link the spec section instead), then shorten
  over-long `History` entries to the length above. Only then look at
  archiving.
- **Archive the oldest entries, keep the recent ones.** Keep `Filed`, the
  newest 6 entries and the one you are adding. Move every older entry out, so
  one archive pass frees space for a while rather than a little each time.
  Keeping only the very latest entry loses the context a cold reader needs;
  keeping a fixed count alone misses a few very long entries, which is why the
  size check comes first.

How to archive:

1. Write the **full History as written** to a repo file under the nearest
   `docs/investigate/` as `YYYY-MM-DD-<ticket>-ticket-history.md` (see
   `planning-docs-investigate.md`), newest first. It holds the original,
   verbatim text of every entry that is leaving the ticket or being shortened,
   so nothing is lost; entries that stay unchanged in the ticket can be
   included too, so the file is the complete record. A later pass updates the
   same file. Open it with one paragraph saying why it exists and that the
   text is as written. Link it from `docs/index.md`. If the repo has no
   `docs/`, ask where it should live; do not drop the entries.
2. Check before committing: the file's entry count and headings match what is
   leaving or changing in the ticket, and the shortened entries' original
   text is in it before you rewrite them.
3. Commit it, and push it, each with its own go-ahead. The links below must
   resolve, so the file is pushed before the ticket is updated.
4. In the ticket, in one update: remove or shorten the entries; add or update
   a `References` bullet "Full History, as written" pointing at the file (the
   stable pointer, edited in place); and end `History` with a last line **See
   Full History**, the whole phrase a link to the file. **Add no `History`
   entry about the move or the shortening.** Update `Current Status` only if
   its meaning changed.
5. Confirm with the user before publishing, as for any description rewrite
   (see "Confirm before rewriting" below). Say plainly that the update removes
   or shortens entries in the ticket.

If a bare 400 still comes back after archiving, stop and report; do not
re-send blind variants of the same payload.

## References are full links

(Found live 2026-10-17.) A `References` bullet that names a repo
file as `docs/specs/foo.md (repo-name)`, or a commit as a bare short hash,
cannot be clicked, and a reader has to work out which repo and which branch
it lives on. Write every reference as a real link.

- **Full URL, as a real link.** Each repo file, branch, commit and PR in
  `References` (and in `History` entries) is an ADF `link` mark with a full
  `https://` URL, or a Markdown link on the Markdown path. The link text is the
  path, branch name or short hash, so the line still reads on its own.
- **Link to a ref that resolves today.** Before publishing, check each file
  exists at the ref you are linking to
  (`git cat-file -e origin/<ref>:<path>`). A `blob/main/...` link to a file
  that is only on a pushed branch is a 404, and a link to a file that exists on
  `main` as an older copy shows stale content. For work on a branch that has
  not merged, link the branch (`blob/<branch>/<path>`, `tree/<branch>`), and
  say in the bullet that the link moves to `main` once it merges. Change it
  then; do not leave it.
- **Link a commit only once it is pushed.** A link to an unpushed commit is
  also a 404. Until then, name it in the text as local and unpushed, and link
  it after the push.
- **Jira keys stay plain text.** The gateway tools cannot create real issue
  links (see below), so a cross-reference such as `PROJ-1499` is text, and the
  bullet says so.
- **Archive pointer.** The `References` bullet that points at an archived
  History file follows the same rule.

## Where the update goes: description edit vs. comment

Prefer editing the description itself (both sections) as the durable
record, since that's what a reader sees first and don't need to scroll a
comment thread to find. Use `jira_update_issue_*` /
`editJiraIssue`/`updateConfluencePage`-style tools to rewrite the
description in place. A comment can *additionally* flag a round happened
(useful for @-mentioning someone or cross-posting to chat), but the description's `Current Status` +
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
  `jira_create_issue_<instance>`** (a per-instance MCP gateway,
  one tool set per Jira site): passing a plain string
  for `description` wraps it in **one ADF paragraph** — confirmed live
  (2026-09-11; recurred and re-confirmed 2026-09-16): a description written with `##`/`-` Markdown came back
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
    transition endpoint, and no issue-link endpoint either (confirmed live:
    a `fields.comment` update and a `fields.status` update both 400'd;
    on 2026-09-16 `fields.issuelinks` with an `add` operation also 400'd — issue links need the dedicated `/issueLink` REST endpoint,
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
`planning-jira-ticket-transitions.md` (which governs *status* transitions) —
a ticket can update its `Current Status` section without its Jira status
changing, and vice versa.
