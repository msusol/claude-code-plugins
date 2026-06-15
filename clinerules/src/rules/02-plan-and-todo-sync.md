---
description: Synchronization rules between docs/plans/*.md plan files and docs/plans/TODO.md
paths:
  - docs/plans/**/*.md
---

# Plan implementation and TODO.md synchronization

`docs/plans/` holds feature-level implementation plans and task-level sequencing. `docs/plans/TODO.md` is the central live checklist for work derived from those plans, co-located with the plan files it tracks.

- Always locate `docs/plans/TODO.md` before making implementation changes.
- If `docs/plans/` contains any plan files and `docs/plans/TODO.md` does not exist, create it at `docs/plans/TODO.md` **before beginning implementation work** — do not defer creation until after tasks are completed.
- If no plan files exist yet, create `docs/plans/TODO.md` when a live checklist is first needed.
- All tasks in `TODO.md` must use GitHub-style checkboxes:
  - Open task: `- [ ] Task description`
  - Completed task: `- [x] Task description`.

## Mapping plan files to TODO sections

Each plan file in `docs/plans/` can map to its own section in `TODO.md`.

Plan file | TODO.md section
--- | ---
`docs/plans/search-rollout.md` | `Search rollout`
`docs/plans/pre-ga-hardening.md` | `Pre-GA hardening`

Rules:

- New implementation plans go in `docs/plans/` and get a new named section in `TODO.md` when a live checklist is useful.
- Each plan has its own top-level section in `TODO.md`. Do not merge tasks across sections.
- When a task is completed, mark it complete only in the section that owns it.
- When adding tasks derived from a plan file, place them under the correct section.

## Deriving tasks from plans

- Scan the relevant `docs/plans/*.md` file for bullet lists and concrete section headings.
- For each actionable item, ensure there is a corresponding checkbox entry in `TODO.md` under the matching plan section.
- Keep TODO text concise but traceable back to the originating plan (for example by using similar wording or including a short reference).

## Next steps section

- `TODO.md` should end with a `## Next steps` section when it is used.
- `Next steps` should be grouped by plan using subheadings that match or clearly reference the relevant `docs/plans/*.md` files.
- Each item should be numbered sequentially within its group when ordering matters.
- An item belongs to the plan whose work it advances; do not mix plans within a group.
- When a next step is completed or deferred, remove or demote it and renumber as needed.
- Deferred items stay in `Next steps` with a short note such as `deferred: <reason>`.
