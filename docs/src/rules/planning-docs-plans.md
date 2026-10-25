---
description: Authoring rules for implementation plans under docs/plans/ (minimal vs expanded, sections, editing discipline)
paths:
  - docs/plans/**/*.md
---

# Planning document rules

Treat files under `docs/plans/` as implementation planning documents.

They are execution-oriented docs that explain how work should be carried out, broken down, and sequenced.

## File naming and location

- Place plans directly under `docs/plans/`. Archived plans live in `docs/plans/archive/`.
- Name new plan files `NNNN-kebab-case-title.md`, where `NNNN` is a zero-padded four-digit sequential plan number, for example `0007-search-rollout.md`.
- Allocate the next unused number by scanning **both** `docs/plans/` and `docs/plans/archive/`.
- Do not reuse numbers, even when a plan is archived, superseded, or dropped. Gaps are fine.
- Numbers are per repo: each repo's `docs/plans/` starts at `0001`.
- The number appears only in the filename. Do not repeat it in the H1. Refer to a plan as "plan 0007" in chat, commits, and other docs.
- The number stays the same when the plan is archived. Archiving moves the file; it never renames it.
- `docs/plans/TODO.md` is not a plan and stays unnumbered.
- Plans that already exist without a `NNNN-` prefix (unprefixed or date-prefixed) are not renamed unless the user asks. Renaming breaks links in other docs and repos.

## Front matter

New plans start with this front matter:

```yaml
---
status: active
date: YYYY-MM-DD
tickets: [PROJ-123]
specs: [specs/feature-name/spec.md]
adr: [adr/0007-decision-title.md]
---
```

- `status` is required. Values: `active`, `blocked`, `done`, `superseded`, `archived`.
  - When writing or editing a plan, set only `active` or `blocked`.
  - `done` and `archived` are set only after the tasks are checked against live state and the user has confirmed (see "Archiving completed plans", and the `plan-bash` skill when installed).
  - `superseded` is set with a one-line note in the plan body naming the plan that replaces it.
- `date` is required. It is the date the plan was last updated, in `YYYY-MM-DD` form. Update it whenever you change the plan or archive it.
- `tickets` is optional. List issue-tracker keys when the plan is tied to tickets. Omit it otherwise.
- `specs` and `adr` are optional. List paths relative to `docs/`.
- Do not put the plan number in the front matter; the filename is the single source of truth.
- If `status` disagrees with the checkboxes, trust the checkboxes after verifying live state, and fix `status`.
- Existing plans without front matter are not retrofitted. Add it when you next edit them, if the user wants it.

## Default (minimal) planning mode

For new or simple work, start with a minimal plan.

The minimal format should usually include:

- front matter (see above)
- `# <Feature Name> Implementation Plan`
- `## Goal`
- `## Context`
- `## Tasks`
- `## Notes` (optional)

Guidelines:

- Keep tasks as concise checklist items.
- Prefer checkbox tasks (`- [ ]`) so the plan can be synchronized into `TODO.md` when needed.
- Do not introduce extra sections until they add real value.

## When to expand a plan

Do not force every plan into a full template immediately.

Expand a plan only when one or more of the following is true:

- The work touches multiple systems, services, or components.
- The work is expected to span multiple sessions.
- The flat task list is no longer clear or easy to follow.
- There are meaningful risks, dependencies, or rollout concerns.
- Another person or agent may need to continue the work later.
- Implementation reveals unknowns that need explicit tracking.
- The user explicitly asks for a more detailed plan.

## Expanded planning sections

When a plan needs more structure, evolve the same file by adding only the sections that improve clarity, such as:

- `## Scope`
- `## Implementation approach`
- `## Risks and unknowns`
- `## Task breakdown` (grouped tasks)
- `## Ordered execution plan`
- `## TODO sync candidates`
- `## Decision log`
- `## Open questions`
- `## Exit criteria`

Rules:

- Add sections incrementally; avoid adding empty sections.
- Keep the document easy to scan; headings should reflect real needs, not ceremony.

## Relationship to other docs

- Use `docs/specs/` for design intent, rationale, and architecture-level detail (what and why).
- Use `docs/plans/` for implementation sequencing and task-level execution (how and when).
- Use `docs/investigate/` for debugging, validation, and root-cause analysis when behavior is unclear.

If a decision becomes architectural or long-lived beyond the immediate implementation, capture it in a spec update or ADR instead of overloading the plan.

## TODO.md synchronization

When `TODO.md` is in use:

- Write plan tasks so they can be copied or mapped directly into `TODO.md`.
- Keep wording concise and action-oriented.
- Follow `planning-plan-sync.md` for normal synchronization.
- Follow `planning-desync-cleanup.md` if you detect a large desync between plan files and `TODO.md`.

## Editing discipline

- Prefer evolving the existing plan file over creating duplicates.
- Preserve the minimal structure when the work is still simple.
- Expand only the sections that help for the current level of complexity.
- Keep completed plans readable; use `docs/investigate/` for detailed investigation logs instead of turning plans into mixed artifacts.

## Archiving completed plans

When all tasks in a plan are checked off (or the plan has been superseded), move it to
`docs/plans/archive/` rather than leaving it in `docs/plans/`.

### When to archive

Archive a plan when **all** of the following are true:

- Every `- [ ]` task is either `- [x]` complete or explicitly marked deferred/dropped with a note.
- No open questions remain that block future work.
- The implementation it describes is in production or the plan has been superseded.

Do not archive a plan that still has pending tasks unless those tasks have been explicitly
deferred to another plan or doc.

### How to archive

1. Mark any remaining deferred tasks with a note: `- [ ] ~~Task~~ — deferred to <other-plan.md>`
2. Set `status: archived` and bump `date` in the front matter (if the plan has it), then move the file: `mv docs/plans/<name>.md docs/plans/archive/<name>.md`
   (create `docs/plans/archive/` if it does not exist). Keep the filename, including its `NNNN-` prefix, unchanged.
3. Remove or update any `TODO.md` section that referenced the plan — add a one-line note
   such as `_Archived 2026-06-28 — see docs/plans/archive/<name>.md_`
4. Update `docs/index.md` if it linked to the plan (change the link or remove the entry).

### What not to do

- Do not delete completed plans — the archive preserves context and decision history.
- Do not archive a plan mid-implementation just to tidy up.
- Do not move plans to `docs/adr/` — if a decision in the plan deserves permanent record,
  extract it into an ADR and reference it; then archive the plan normally.
