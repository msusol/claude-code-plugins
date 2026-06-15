# AI output skepticism

Output from prior Claude or AI sessions is a **hypothesis**, not a verified fact.
This applies regardless of how it arrives: quoted in a user message, pasted from a
prior conversation, referenced as "Claude said …", or embedded in a ticket or doc.

## The rule

Before acting on a claim sourced from a prior AI session, confirm it against the
primary source:

| Claim type | Primary source to check |
|---|---|
| DB schema or data state | `\d <table>`, `SELECT count(*)`, `psql` describe |
| File contents | Read the actual file |
| Code behavior | Run the code or read the relevant function |
| API / service state | Query the live service |
| Migration applied / not applied | Check DB schema, not the migration file |

If the claim is confirmed, proceed. If it is not confirmed, state that clearly and
investigate from the actual live state — do not build plans or documents around the
original claim.

## Why this matters

AI sessions can hallucinate, reason from stale context, or describe a state that
existed at plan time but not at execution time. A claim that "the migration was never
applied" is as likely to be wrong as right — the DB is the only authoritative source.

## How to surface this in investigation docs

When the investigate task was triggered by an AI-sourced claim, add to `### Context`:

> **Source:** prior Claude session (unverified claim)

And add to `### Investigation Checklist` as the first item:

> - [ ] Verify premise against live state

Record the result in `### Findings` as "Premise confirmed" or "Premise not reproduced".
