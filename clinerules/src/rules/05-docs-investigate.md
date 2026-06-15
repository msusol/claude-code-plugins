---
description: Per-issue structure for analyst-mode investigation logs under docs/investigate/
paths:
  - docs/investigate/**/*.md
---

# Investigation document rules

- Treat files under `docs/investigate/` as analyst-mode documents, not specs or ADRs.
- A single investigation file may contain one issue or many issues.
- Treat each level-2 heading (`##`) as a separate issue entry.
- Preserve user-authored issue headings and initial freeform context.

## File naming and location

- No artifacts: flat file — `docs/investigate/YYYY-MM-DD-issue-name.md`
- With artifacts: named subdirectory — `docs/investigate/YYYY-MM-DD-issue-name/` with the
  anchor doc named `YYYY-MM-DD-issue-name.md` inside it alongside the artifacts.
- Use the same date-prefix convention for subdirectory names as for flat files.

See `.clinerules/14-docs-artifacts.md` for the full artifact co-location rule.

## Per-issue structure

When actively working an issue, add these subsections if they are missing:

- `### Context`
- `### Investigation Checklist`
- `### Findings`
- `### Actions Taken`
- `### Resolution`
- `### Follow-ups`

## Section meanings

### Findings

`### Findings` must contain:

- observations
- evidence
- confirmed causes
- explicitly marked hypotheses
- conclusions drawn from investigation

Do not record changes, edits, mitigations, or commands here.

### Actions Taken

`### Actions Taken` must contain:

- code changes
- config changes
- commands run
- mitigations applied
- rollbacks performed
- verification steps executed

Do not restate findings here.

### Resolution

Always add or update `### Resolution` after meaningful progress on an issue.

`### Resolution` must include one of these statuses:

- `resolved`
- `partially resolved`
- `unresolved`
- `deferred`
- `not reproducible`

Add a brief statement describing the current outcome and, when applicable, how it was verified.

### Follow-ups

Use `### Follow-ups` for:

- remaining risks
- open questions
- deferred work
- additional validation needed
- next steps

## Verify the premise first

When an `investigate:` task is based on a quoted claim, a prior session's output, a
ticket description, or any externally-sourced description of live state, **verify the
claim against ground truth before any analysis, planning, or document creation.**

- For DB issues: run `\d <table>` and a row count before drawing schema conclusions.
- For file issues: read the actual file before accepting a description of its contents.
- For runtime issues: reproduce or check logs before accepting a reported symptom.

Do not treat a quoted claim as fact. Treat it as a hypothesis to confirm or refute.
Record the verification result in `### Findings` with "Premise: confirmed" or
"Premise: not reproduced — actual state is …".

## Editing discipline

- Only modify issue entries actively being worked on.
- Avoid unnecessary rewrites of untouched issue entries.
- Preserve numbered issue headings such as `## 1. Some issue found` when they already exist.
