---
description: GitFlow (Lite) branch naming convention for ARIES/WCP — cut branches from the right base and name them so the PreToolUse hook doesn't block them
globs: "**/*"
---

# Git branch naming — GitFlow (Lite) for ARIES/WCP

Source of truth: [GitFlow (Lite) — Branching & Release Process for ARIES/WCP](https://mitratechdev.atlassian.net/wiki/spaces/WCPW/pages/25939410979/GitFlow+Lite+Branching+Release+Process+for+ARIES+WCP)
(Confluence, space `WCPW`). This rule is the day-to-day summary; treat the
Confluence page as canonical if the two ever disagree.

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
feature/WCP-1234-bulk-export
bugfix/WCP-1301-null-pointer-on-save
chore/WCP-1310-bump-node-20
```

- `<TICKET>` is a Jira key (`WCP`, `WCPCO`, `WCPAC`/`AIRESAC`, etc. — see the
  target repo's own CLAUDE.md for which project key applies), uppercase, e.g. `WCP-1234`.
- `<short-kebab-description>` is lowercase, hyphen-separated, no ticket text duplication.

`release/*` and `hotfix/*` are named after the semantic version they produce
(**not** a ticket key):

```
release/2.4.0
hotfix/2.3.1
```

`main` and `develop` are the two permanent branches — never invent a
ticket-suffixed variant of either.

**Open question inherited from the source doc:** whether `chore/*` should be
exempt from the ticket-key requirement is explicitly unresolved in the
Confluence page (§11). Until that's decided, `chore/*` is enforced the same
as `feature/*`/`bugfix/*` — flag it back to Engineering if it's causing
friction rather than quietly dropping the ticket key.

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
