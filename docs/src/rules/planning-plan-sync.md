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
`docs/plans/0007-search-rollout.md` | `0007 Search rollout`
`docs/plans/0012-pre-ga-hardening.md` | `0012 Pre-GA hardening`
`docs/plans/search-rollout.md` (legacy, no number) | `Search rollout`

Rules:

- A numbered plan's `TODO.md` section title starts with its plan number (`0007 Search rollout`), so the section and the file stay unambiguous. Legacy plans without a number keep their plain title.
- New implementation plans go in `docs/plans/` (named `NNNN-title.md`, see `planning-docs-plans.md`) and get a new named section in `TODO.md` when a live checklist is useful.
- Each plan has its own top-level section in `TODO.md`. Do not merge tasks across sections.
- When a task is completed, mark it complete only in the section that owns it.
- The plan file is the source of truth and its `TODO.md` section is derived from it. A commit that checks off, adds, strikes or rewords a plan task changes the same task in the plan's `TODO.md` section in the same commit; a plan file edited alone is the desync this file exists to prevent.
- When you check off or add tasks in a plan that has front matter, bump the plan's `date`.
- When adding tasks derived from a plan file, place them under the correct section.

## Shape of a TODO section

A section mirrors its plan file **task for task**: one checkbox line per plan task, in the plan's order, so the two can be compared by counting.

- Do not write phase roll-ups ("Phase 3: dry run done; stage and gate left"). A roll-up cannot be compared with the plan file, and its prose goes stale first.
- A line says what the task is and its state, nothing more: no "left: …", no "done on Monday, then …". The story goes in the plan file next to the task.
- Obsolete, dropped and deferred tasks carry the same marker as in the plan file, `- [x] ~~Task~~ — obsolete: reason` (or `dropped`, or `- [ ] ~~Task~~ — deferred to [plan NNNN](...)`). Tooling that counts progress, for example the docs-hub plugin, leaves exactly these out; a plain-text "obsolete" still counts as work.
- Under this shape the checked and unchecked counts of the section equal those of the plan file (struck-through tasks left out of both). The docs-hub plugin's Plan progress chart marks a plan where they do not.

## Moving a task between plans

When a task moves from one plan to another (a deferral), in one change: strike it in the source plan and its section with `— deferred to [plan NNNN](...)`, and add it, unchecked, to the destination plan file and its section with a note such as `_carried from plan NNNN_`. Never leave it in only one of the two places.

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
- A next step that names a date ("Monday 2026-11-02: check the first run") is a promise about a day. Once the latest date it names has passed, check it: if it is done, remove it; if it is late, say so in the item. Do not leave a past-dated item as it is. Any session that touches a plan, and `plan-bash`, makes this check. The docs-hub plugin flags such items.
- Do not copy a next step into the plan's task lines as well; a task is either a checkbox in the section or a next step, not both.
- Deferred items stay in `Next steps` with a short note such as `deferred: <reason>`.
