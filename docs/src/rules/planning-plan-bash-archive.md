---
description: Plan-number-driven check and archive of a single docs/plans/###-*.md plan (verify tasks, confirm, archive with its number intact)
paths:
  - docs/plans/**/*.md
  - docs/plans/TODO.md
---

# Plan-bash plan archiving

When the user gives a plan number and asks for a "plan bash" (for example `plan-bash 007`, "plan bash 7", "archive plan 007", "is plan 007 done?"), check that one plan against reality and archive it if it is genuinely finished.

This is the plan-number sibling of `planning-bug-bash-ticket-cleanup.md` (keyed by ticket key, sweeps every plan that mentions the ticket) and a narrower sibling of `planning-desync-cleanup.md` (repo-wide). It reuses the archive mechanics in `planning-docs-plans.md` ("Archiving completed plans") and the numbering and front matter rules defined there. Reach for this rule when the scope is "plan N".

## 1. Resolve the plan

- Normalize the argument to three digits (`7` becomes `007`).
- Find files matching `<###>-*.md` in `docs/plans/` and in `docs/plans/archive/`.
  - Exactly one match in `docs/plans/`: proceed.
  - Match only in `docs/plans/archive/`: say it is already archived and stop. Do not re-process it.
  - No match: list the plans that exist, including archived ones marked as archived, with number, title, `status`, and open/total task counts for the ones in `docs/plans/`. Ask which one was meant. Never guess a nearby number.
  - More than one match (a duplicated number): stop and report both files. Do not pick one, and do not propose a renumbering unless asked. Duplicate numbers need the user's decision.
- No argument given: list the plans in `docs/plans/` with number, title, `status`, and open/total task counts, and ask which to check.
- A ticket key instead of a number: find numbered plans whose `tickets:` front matter lists it. One match: confirm the plan number with the user and proceed. Several: list them and ask. If the user wants every plan tied to the ticket swept, use `planning-bug-bash-ticket-cleanup.md`.
- A legacy plan with no `###-` prefix cannot be addressed by number. Tell the user, and offer to run the same steps by file name. Do not rename it.

## 2. Read everything about the plan

- Read the whole plan file, including front matter, `Notes`, `Open questions`, and `Exit criteria` sections if present.
- Read the plan's section in `docs/plans/TODO.md` (a numbered plan's section title starts with its number, for example `007 Search rollout`; a legacy plan uses its plain title).
- Check `specs:` and `adr:` front matter links and any ADR or spec that links back to this plan.

## 3. Classify every task

For each task in the plan and in its `TODO.md` section:

- **Done** — `- [x]`, and confirmed against live state (see step 4).
- **Deferred** — `- [ ] ~~Task~~ — deferred to <other-plan>`, with the target plan named and existing.
- **Dropped** — marked dropped with a reason.
- **Open** — unchecked with no deferral or drop note.
- **Unverifiable** — checked, but nothing in the repo, PRs, or running system confirms it.

## 4. Verify "done" against live state

A checkbox is a claim, not proof (see `planning-ai-skepticism.md`). For each task that is checked off, confirm against the primary source: the code or file on the branch, the merged PR or commit, the deployed or running behavior, or the test result. Say which source you used. If it cannot be confirmed, classify it as unverifiable and do not count it as done.

Compare the plan's task list with its `TODO.md` section. If they differ (a task missing from `TODO.md`, a shortened or extra task, a different checkbox state), report it. A difference is not a blocker by itself, and a verified plan file wins over `TODO.md`. When the plan is archived, its `TODO.md` section is replaced anyway; when it is not, offer to sync that one section.

Also compare the plan's front matter `status` with the checkboxes. If they disagree (for example `status: active` with every task done, or `status: done` with open tasks), trust the verified checkboxes, report the mismatch, and plan to correct `status`.

## 5. Report and confirm before changing anything

Before editing or moving any file, tell the user:

- the plan file and its `TODO.md` section
- counts per classification, and each open or unverifiable task by name
- any blocking open question, unmet exit criterion, or `status` mismatch
- whether the plan is archivable, and what you would do

Then get explicit confirmation. A plan is archivable only when **all** of these hold:

- every task is done, deferred (to an existing plan or doc), or dropped with a reason
- no open question blocks future work
- the work it describes is in production, or the plan is superseded. Evidence for "in production": the merged commit or PR on the deploy branch, a linked spec with `status: shipped`, or the user saying so. If you only have weak evidence (code on disk), say that plainly in the report and let the user decide

If the plan is **not** archivable, say exactly which tasks or questions block it. Offer, without doing any of it unprompted:

- correcting `status` to match the verified checkboxes (for example `done` to `active`) and bumping `date`
- marking tasks deferred with the standard note, if the user names the destination
- setting `status: blocked`, if work is stalled
- leaving the plan alone

Never check off a task, mark one deferred, or soften a blocker to make a plan archivable.

## 6. Archive (after confirmation)

Follow "Archiving completed plans" in `planning-docs-plans.md`, with these specifics:

1. Mark remaining deferred tasks with `- [ ] ~~Task~~ — deferred to <other-plan>`.
2. In the plan's front matter, set `status: archived` and bump `date` to today. If the plan has no front matter, do not add it; move the file as is. If the user only wants to close the plan without moving it, set `status: done` and bump `date` instead, then skip the move and the link fixes (steps 3 to 7 below) but still update the plan's `TODO.md` section.
3. Move the file to `docs/plans/archive/` with the **same filename**. The `###-` prefix never changes. Use `git mv` when the file is tracked.
4. In `docs/plans/TODO.md`, keep the plan's section heading and replace its contents with one line, for example `_Archived 2026-10-25 — see docs/plans/archive/007-search-rollout.md_`, and remove it from `Next steps`.
5. Update `docs/index.md` if it linked to the plan.
6. Search the repo for links to the old path (`docs/plans/<###>-...`, relative `plans/<###>-...`, and `../plans/...`) and for bare mentions of the file name (for example `007-search-rollout.md`) in specs, ADRs, process docs, investigations, other plans, and `CLAUDE.md` files. Fix each to the archive path in the same change.
7. If an accepted ADR links to the plan, only the broken link may be fixed (see the immutability rule in `planning-docs-adr.md`).

## 7. Finish

- Show the final summary: what moved, what changed in `TODO.md` and `docs/index.md`, and which links were fixed.
- Commit through the repo's normal commit workflow (see `planning-commit-verification.md`): the verification is the evidence gathered in step 4. Do not push unless asked. If the directory is not a git repository, skip the commit and say so.
- Branch handling follows the repo: in a single-branch repo, commit to the current branch. If you created a cleanup branch in a multi-branch repo, return to the branch you started on once it is merged (same as step 6 of `planning-bug-bash-ticket-cleanup.md`).
- If the plan's work was tied to tickets (`tickets:` front matter), mention that their status may need updating, and leave the transition to `planning-jira-ticket-transitions.md` and the user's confirmation.

## What not to do

- Do not archive a plan with open or unverifiable tasks, or one marked `blocked`, without the user explicitly accepting that.
- Do not rename or renumber a plan, and never reuse its number.
- Do not touch other plans or other `TODO.md` sections while checking one plan.
- Do not delete a plan; archiving moves it.
- Do not trust `status` over verified checkboxes, or checkboxes over live state.
- If checking this one plan reveals a repo-wide mismatch between plans and `TODO.md`, stop and switch to `planning-desync-cleanup.md` rather than silently widening scope.
