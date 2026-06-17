---
description: Authoring rules for implementation plans under docs/plans/ (minimal vs expanded, sections, editing discipline)
paths:
  - docs/plans/**/*.md
---

# Planning document rules

Treat files under `docs/plans/` as implementation planning documents.

They are execution-oriented docs that explain how work should be carried out, broken down, and sequenced.

## Default (minimal) planning mode

For new or simple work, start with a minimal plan.

The minimal format should usually include:

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
- Follow `.clinerules/02-plan-and-todo-sync.md` for normal synchronization.
- Follow `.clinerules/03-desync-cleanup.md` if you detect a large desync between plan files and `TODO.md`.

## Editing discipline

- Prefer evolving the existing plan file over creating duplicates.
- Preserve the minimal structure when the work is still simple.
- Expand only the sections that help for the current level of complexity.
- Keep completed plans readable; use `docs/investigate/` for detailed investigation logs instead of turning plans into mixed artifacts.
