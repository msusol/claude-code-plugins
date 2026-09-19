---
description: GitFlow (Lite) branch naming convention — cut branches from the right base and name them so the PreToolUse hook doesn't block them
globs: "**/*"
---

# Git branch naming — GitFlow (Lite)

A day-to-day summary of a GitFlow (Lite) branching model: `main`/`develop`
as permanent branches, short-lived `feature`/`bugfix`/`chore`/`release`/
`hotfix` branches cut from and merged back into the right base. Adapt the
`<TICKET>` prefix and any project-specific naming details below to
whatever issue tracker the target repo actually uses — treat this file as
a template, not a fixed standard.

## Single-branch repos are exempt

This whole model assumes a repo that actually has a permanent `develop`
branch and ticket-keyed work. **Before applying any of this, check
`git branch -a` (or equivalent) for a `develop` branch.** If the repo has
only `main`/`master` — no `develop`, no prior
`feature/*`/`bugfix/*`/`chore/*` branches in its history — this rule does
not apply at all:

- Commit and push directly to `main`/`master`, same as the repo's own
  existing history already does.
- Do not propose creating a `develop` branch, feature branches, or PRs to
  introduce this workflow unless the user explicitly asks for it.
- Do not enforce the `<type>/<TICKET>-<description>` naming pattern
  below, since there's no ticket-key convention in a repo that was never
  using one in the first place.
- The git-guard branch-creation hook still technically only blocks
  non-conforming *branch creation* commands — a single-branch repo that
  never creates branches never triggers it, so no bypass sentinel is
  needed either.

This exemption is about the *branch topology* (single branch vs.
main+develop), not the project — re-check per repo, since one person may
work across both multi-branch repos (this model applies) and single-branch
personal/other repos (it doesn't).

## Branch types

| Branch | Cut from | Merges into | Purpose |
|---|---|---|---|
| `main` | — | — | Always reflects production. Every commit is tagged. |
| `develop` | `main` (once) | — | Integration branch, always deployable to dev. |
| `feature/*` | `develop` | `develop` | New functionality. |
| `bugfix/*` | `develop` | `develop` | Non-urgent bug fixes found in `develop` or a release candidate. |
| `chore/*` | `develop` | `develop` | Non-functional work: dependency bumps, refactors, CI/tooling, docs. |
| `release/*` | `develop` | `main` **and** `develop` | Stabilizes a release candidate; no new features. |
| `hotfix/*` | `main` | `main` **and** `develop` | Urgent production fix that can't wait for the release train. |

## Naming pattern — this is what gets enforced

`feature/*`, `bugfix/*`, `chore/*` are named `<type>/<TICKET>-<short-kebab-description>`:

```
feature/PROJ-1234-bulk-export
bugfix/PROJ-1301-null-pointer-on-save
chore/PROJ-1310-bump-node-20
```

- `<TICKET>` is the issue-tracker key for the target repo/project (e.g.
  a Jira project key) — check the target repo's own CLAUDE.md or issue
  tracker for which prefix applies, uppercase, e.g. `PROJ-1234`.
- `<short-kebab-description>` is lowercase, hyphen-separated, no ticket text duplication.

`release/*` and `hotfix/*` are named after the semantic version they produce
(**not** a ticket key):

```
release/2.4.0
hotfix/2.3.1
```

`main` and `develop` are the two permanent branches — never invent a
ticket-suffixed variant of either.

**Whether `chore/*` should be exempt from the ticket-key requirement** is
a real open question for many teams adopting this model. Until the team
decides, enforce `chore/*` the same as `feature/*`/`bugfix/*` — flag it
back to the team if it's causing friction rather than quietly dropping
the ticket key.

## What the git-guard hook actually blocks

The git-guard PreToolUse hook (`~/.claude/scripts/git-guard-hook.zsh`)
intercepts branch-creation commands — `git checkout -b <name>`,
`git switch -c <name>`, `git branch <name>` — and rejects any name that
doesn't match one of:

- `^(feature|bugfix|chore)/[A-Z][A-Z0-9]+-[0-9]+-[a-z0-9]+(-[a-z0-9]+)*$`
- `^(release|hotfix)/[0-9]+\.[0-9]+\.[0-9]+$`
- the literals `main` or `develop`

Choosing a conforming name up front avoids the block entirely — that's the
point of this rule. If a name is legitimately exempt (rare), prefix the
command with `GIT_GUARD_SANCTIONED=1` the same way the commit/push sentinel
works, and say why in the conversation.

## Workflow reminders (not just naming)

- Cut `feature/*`, `bugfix/*`, `chore/*` from `develop`, not `main`.
- Cut `hotfix/*` from `main`, not `develop`.
- `release/*` and `hotfix/*` merge into **both** `main` and `develop` — don't
  forget the merge-back to `develop` or the fix/stabilization gets lost in
  the next release.
- Squash-merge `feature/*`/`bugfix/*`/`chore/*` into `develop`; use a real
  merge commit for `release/*`/`hotfix/*` into `main` and for the
  merge-back into `develop`.
