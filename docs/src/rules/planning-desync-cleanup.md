---
description: Workflow for reconciling heavy desync between docs/plans/ files and docs/plans/TODO.md
paths:
  - docs/plans/**/*.md
  - docs/plans/TODO.md
---

# Handling heavy desynchronization between plan files and TODO.md

When `docs/plans/*.md` files and `docs/plans/TODO.md` appear heavily out of sync, do not guess or silently paper over inconsistencies. Follow this cleanup workflow.

## 1. Detecting heavy desync

Treat the situation as a potential heavy desync if you notice any of the following:

- Many tasks present in `docs/plans/*.md` but missing from `docs/plans/TODO.md`.
- Many tasks present in `TODO.md` but no longer present in any current plan file.
- Widespread mismatches between checkbox states in `TODO.md` and the current reality of the implementation.
- Plan sections that appear substantially rewritten or restructured compared to their corresponding sections in `TODO.md`.

## 2. Pause and confirm with the user

Before performing large-scale edits:

- Inform the user that plan files and `TODO.md` appear out of sync.
- Propose running a one-time sync cleanup to reconcile them.
- Ask the user to confirm:
  - whether the plan files under `docs/plans/` should be treated as the source of truth
  - whether `TODO.md` should be treated as the source of truth
  - or whether they want a conservative merge that preserves both and requires manual review.

## 3. Source-of-truth strategies

If the user confirms that plan files are the source of truth:

- For each plan file in `docs/plans/`, rebuild or update its corresponding section in `docs/plans/TODO.md` to mirror the current plan tasks.
- Remove obviously stale `docs/plans/TODO.md` entries that refer to tasks no longer present in any current plan file.

If the user confirms that `TODO.md` is the source of truth:

- For each relevant plan file, update or recreate its task sections so they match the tasks and statuses currently listed in `TODO.md`.
- Optionally add a short note in each affected plan file indicating that it has been synchronized from `TODO.md`.

If the user chooses a conservative merge:

- Do not delete tasks outright.
- Create a `Review needed` or `Unmapped tasks` section in `TODO.md`.
- Move ambiguous or stale items there with a note that they require user decisions.

## 4. Mechanical cleanup steps

When performing a sync cleanup after user confirmation:

- Enumerate all plan files under `docs/plans/**/*.md`.
- Collect their task lists.
- Enumerate all sections and checkbox items in `TODO.md`.
- For each plan file:
  - ensure there is a corresponding section in `TODO.md`
  - align tasks and checkbox states between the plan and its `TODO.md` section according to the chosen source-of-truth strategy.
- For `TODO.md` items that do not map cleanly to any current plan:
  - remove them if plan files are the source of truth
  - or move them into the review section for later manual decisions.

## 5. Documentation and follow-up

After completing a heavy desync cleanup:

- Add a short note near the top of `TODO.md` describing:
  - when the cleanup occurred
  - which source-of-truth strategy was used.
- Optionally add a short note in each modified plan file indicating that it has been synchronized with `TODO.md`.
- For subsequent sessions, resume the normal synchronization behavior defined in `planning-plan-sync.md`.
- Avoid repeating heavy cleanup unless a similar large desync is detected again.

## 6. Safety constraints

- Do not delete large blocks of tasks from `TODO.md` or plan files without:
  - explaining the change to the user
  - and getting explicit confirmation for the chosen strategy.
- When in doubt about whether an item is obsolete or duplicated, prefer preserving it under a `Review needed` or `Unmapped tasks` section instead of deleting it.
