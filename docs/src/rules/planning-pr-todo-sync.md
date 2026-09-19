# PR creation discipline: batch commits, keep TODO.md/PR metadata in sync

`planning-plan-sync.md` keeps `docs/plans/TODO.md` in sync "as work
happens," but nothing gates that sync on the actual git/GitHub events where
staleness gets locked in: opening a PR, and merging one. This rule adds
those triggers explicitly, plus a related discipline on *when* to propose a
PR at all, for three related failure modes seen in practice:

1. Proposing (or opening) a PR after a single small commit, instead of
   batching related work on a branch first — churns out many granular PRs
   for what should be one reviewable unit of work, and multiplies the
   title/body-goes-stale problem in #3 below across more PRs than
   necessary.
2. `docs/plans/TODO.md` and a `docs/plans/*.md` plan file it tracks going
   out of sync with each other (a task resolved in one, never rolled up in
   the other) while the real work already shipped in a PR.
3. A PR's own title/body going stale as it accumulates commits (e.g. a
   Draft PR kept open across many sessions) — opened to describe one small
   task, merged much later describing something far broader, with the
   title/body never updated to match.

## Single-branch repos: no PR ceremony at all

This entire rule assumes a repo where work happens on a branch and lands
via a reviewed PR. **Before applying any of it, check whether the repo
actually has more than one permanent branch** (`git branch -a` — look for
`develop` alongside `main`/`master`, or any prior `feature/*`/`bugfix/*`
branches in its history). If the repo only has `main`/`master`, and
commits have always gone straight to it:

- There is no PR to batch commits toward — commit directly to
  `main`/`master`, same as the repo's own existing history.
- Do not propose creating a branch or opening a PR to "do this properly"
  unless the user explicitly asks for that workflow.
- The batching discipline still applies in spirit, just at the
  **push** level instead of the PR level: don't push to `origin` after
  every single commit. Commit locally as each unit of work completes,
  and only push when the user asks, or when a natural batch boundary is
  reached (a checklist item fully resolved, the user says "wrap this
  up"/"push this") — the same triggers this rule uses for opening a PR,
  just applied to `git push` instead of `gh pr create`.
- `docs/plans/TODO.md`/plan-file sync (per `planning-plan-sync.md`)
  still applies fully — that discipline isn't PR-dependent, it's about
  keeping the record accurate as work lands, which happens at commit
  time either way.

This is about branch *topology*, not project identity — the same person
may work across both multi-branch repos (this rule's PR discipline
applies in full) and single-branch personal/other repos (only the
push-batching analog applies) — re-check per repo, don't assume from a
prior session in a different repo.

## Trigger: before proposing to open a PR at all

Don't ask "should I open a PR for this?" (or open one unprompted) right
after a single commit. Default to committing related work onto the same
branch and let it accumulate, the same way this session's own
`aries-agent-evals` PR #28 collected 12 commits across two full work
phases before being proposed for merge — that was the right shape, not an
oversight to avoid. Hold off proposing a PR until one of:

- The user explicitly asks for a PR right now, or asks to "wrap this up" /
  says the batch is done.
- A checklist item (or a small cluster of closely related items) in
  `docs/plans/TODO.md` is *fully* resolved — not just one commit into a
  multi-commit item.
- The change is a genuinely standalone, urgent, atomic fix (a hotfix, a
  single config value, a security patch) with no natural following work to
  batch it with — the one legitimate exception to batching.

If the user has already said to keep a specific PR open and accumulating
(a Draft PR pattern, e.g. "keep adding commits to PR#N until I say send
it"), keep committing to that branch rather than opening a second PR for
related follow-on work — more branches/PRs fragments the same reviewable
unit of work the batching discipline above is trying to keep together.

## Trigger: before opening a PR

Once a real batch of related commits exists and one of the conditions
above is met, before running `gh pr create` (or handing the user a "ready
to open a PR" recommendation):

- Confirm every commit going into the PR has a corresponding entry in
  `docs/plans/TODO.md`'s relevant section — checked off if done, still
  open if not. If the PR's work isn't reflected there yet, update
  `TODO.md` (and the `docs/plans/*.md` file it maps to, per
  `planning-plan-sync.md`) in the same commit or a preceding one, not
  after the PR is opened.
- Write the PR title/body to describe the actual accumulated diff, not
  just the first or most recent commit.

## Trigger: before marking a PR ready-for-review or merging it

This matters most for a PR kept open and accumulating commits over time
(a Draft PR the user has said to keep collecting commits into, a
long-running feature branch), where the gap between the original title/
body and the final diff grows the longest:

- Re-check `docs/plans/TODO.md` and the mapped plan file one more time
  against the PR's full commit list before merge — not just at the moment
  each commit was made. A plan file's checklist can still be stale even
  when `TODO.md` itself was updated correctly per commit (seen live,
  2026-09-16, WCP-67: `TODO.md` tracked Phase 1 as resolved commit-by-
  commit, but `docs/plans/multi-tool-orchestration-evals.md`'s own Phase 1
  checklist stayed `- [ ]` unchecked the whole time — nothing had ever
  re-diffed the plan file against TODO.md before merge).
- Re-check the PR's own title and body against `git log <base>..HEAD` (or
  `gh pr view --json commits`) — if the accumulated commits describe
  materially more than the title/body say, fix the title/body before
  merging, not after. Seen live the same day: PR #28 opened as "catch
  ALL_SUBSCRIBED_TOOLS registry drift (WCP-67 Phase 0)" but accumulated 12
  commits spanning all of Phase 1 before merge; the mismatch was only
  caught because the user asked directly, not because anything flagged it.
- Do this check even when the user's instruction to merge doesn't mention
  TODO.md or the PR title explicitly — treat "merge this" as including
  "make sure the record is accurate first," the same way
  `planning-jira-ticket-transitions.md` treats closing a ticket as
  requiring evidence, not just a status flip.

## Relationship to other rules

- `planning-plan-sync.md` governs the general TODO.md/plan-file mapping
  and Next-steps bookkeeping; this rule adds the specific PR-lifecycle
  checkpoints where that sync must be verified, not just "eventually" true.
- `planning-desync-cleanup.md` is the heavier remediation path when a
  large gap is already found; this rule is aimed at not accumulating one
  in the first place.
- Independent of `planning-jira-ticket-transitions.md` (Jira status) and
  `planning-slack-wcp-updates.md` (Slack posts) — a PR can be accurate
  here without either of those changing, and vice versa.
- `git-branch-naming.md` has the matching single-branch exemption for
  branch-naming enforcement — the two exemptions describe the same
  repo-topology check, applied to different concerns (branch naming vs.
  PR/push discipline).
