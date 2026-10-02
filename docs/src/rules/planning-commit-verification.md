---
description: Verify a change with an explicit check before it is committed, and commit the evidence with the change
globs: "**/*"
---

# Verify before commit; commit the evidence with the change

A commit confirmation is not verification. Before a commit is drafted, the change must be checked, and the proof must land in the
**same commit** as the change, not in a later one.

## Rule

1. **Name the check first.** Before staging anything or drafting a message, state the specific check that proves *this* change works
   and what a pass looks like. Pick the strongest check available:

   | Change | Check |
   |---|---|
   | Code | The unit tests for it, plus the narrowest real run (a CLI call or dry run) |
   | Deployed or live behavior | The live check: restart or apply, then a real call or chat, observed |
   | Config or infrastructure | A dry run or diff, then apply and re-run the diff to see "nothing to do" |
   | Docs only | A link or format check; render it if it has diagrams |

2. **Challenge the user to run it.** Give the command as an explicit step: "Run this before I commit: `<command>`. Paste the result."
   Checks only the user can run (restarting a production service, running a chat in a UI, applying to production, anything needing
   their credentials) always go to them. Checks the assistant can run safely (tests, read-only checks, dry runs) are run and shown,
   and still stated as the verification step.
3. **Wait for the result** before drafting the commit.
4. **Save the evidence in the same commit.** Add a short evidence record next to the change: the command, date and time, result
   (pass or fail, counts), and what it shows. Use the repo's artifact convention (see `planning-docs-artifacts.md`); if the repo has
   none, the commit message body is the record. Either way the message gets a `Verified:` section (see
   `planning-commit-description.md`).
5. **Fail closed.** If the check fails or cannot be run, say so and commit nothing until the user decides. If they decide to proceed,
   the message says `Not verified: <reason>`.
6. **No follow-up commit as a substitute.** A later commit may add evidence; the first commit must already carry some.

## Scope

Every commit, including small ones: one command and one line of result is enough. For a pure typo fix, the check is the user reading
`git diff`.

## Relationship to other rules

- `planning-commit-description.md` defines the message format, including the `Verified:` section.
- The `git-guard` plugin's `git-commit` skill applies this rule as its verification step before anything is staged.
- `planning-docs-artifacts.md` says where evidence files go when a repo has a `docs/` tree.
