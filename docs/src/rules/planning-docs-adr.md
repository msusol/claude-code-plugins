---
description: Authoring rules for Architecture Decision Records under docs/adr/ using the MADR 4.x template (front matter, required sections, immutability, superseding)
paths:
  - docs/adr/**/*.md
---

# Architecture Decision Record (ADR) rules

Treat files under `docs/adr/` as Architecture Decision Records.

ADRs follow the [MADR](https://adr.github.io/madr/) 4.x template, with the local additions listed under "Local additions to MADR" below. An ADR captures a single architectural decision, the context that forced it, the options considered, and the consequences of choosing it. ADRs are append-only history, not living design docs.

## When to create an ADR

Create an ADR when one or more of the following is true:

- The decision shapes architecture, technology choice, data model, integration boundary, or cross-cutting policy.
- The decision will outlive the immediate implementation and is likely to be revisited.
- The decision involves a meaningful tradeoff between alternatives that future readers will need to understand.
- A spec or plan references a decision whose rationale does not fit cleanly inside that document.
- A previous ADR needs to be superseded, deprecated, or amended.

Do not create an ADR for:

- Routine implementation choices already covered by a spec or plan.
- Reversible local refactors.
- Coding style or formatting preferences.
- Short-lived experiments or spikes.

## File naming and location

- Place ADRs directly under `docs/adr/`. This is a deliberate deviation from MADR's default folder, `docs/decisions/`; keep `docs/adr/` so existing repos and links stay valid.
- Name files `NNNN-kebab-case-title.md`, where `NNNN` is a zero-padded sequential number, for example `0007-adopt-oci-queue-for-ingestion.md`.
- Allocate the next unused number by scanning existing files in `docs/adr/`.
- Do not reuse numbers, even when an ADR is superseded or rejected.
- The number appears only in the filename. Do not repeat it in the H1.

## Template

Start every ADR from this template. Delete optional sections that add no value; never leave placeholder text behind.

```markdown
---
status: proposed
date: YYYY-MM-DD
decision-makers: name, name
consulted: name (role)
informed: team or name
---

# Short title naming the problem and the chosen solution

## Context and Problem Statement

## Decision Drivers

* driver

## Considered Options

* Option 1
* Option 2

## Decision Outcome

Chosen option: "Option 1", because ...

### Consequences

* Good, because ...
* Bad, because ...
* Neutral, because ...

### Confirmation

## Pros and Cons of the Options

### Option 1

* Good, because ...
* Bad, because ...

## More Information
```

## Front matter

- `status` is required. Use one of: `proposed`, `accepted`, `rejected`, `deprecated`, or `superseded by ADR-NNNN`.
- `date` is required. It is the date the ADR was last updated, in `YYYY-MM-DD` form. Update it when `status` changes.
- `decision-makers` is required (a local addition; MADR treats it as optional). List everyone involved in the decision.
- `consulted` is optional. List subject-matter experts whose opinion was sought (two-way communication).
- `informed` is optional. List people kept up to date (one-way communication).
- Do not add `parent`, `nav_order`, or `title`. They are Jekyll theme settings from the MADR template and have no use here.

## Sections

### Title

A short title that reflects both the problem and the chosen solution. Do not prefix it with the ADR number.

### Context and Problem Statement (required)

- Describe the forces, constraints, requirements, and prior state that motivated the decision, in terms that will still make sense in 6 months.
- Two or three sentences is enough for a small decision. Longer decisions may use a story, a table of current behavior, or a numbered list of constraints.
- It may be phrased as a question.
- Do not record the decision itself here.

### Decision Drivers (optional)

The forces and concerns that weigh on the choice, as a list. Use this when the drivers are not already obvious from the problem statement.

### Considered Options (required)

A list of the options that were seriously considered, including the chosen one. A single-option ADR is not an ADR; if there was no alternative, the decision probably belongs in a spec or plan.

### Decision Outcome (required)

- State the chosen option and why, in the form: `Chosen option: "<option>", because <justification>.`
- Add sub-sections for detail when the decision is more than a sentence. For example: how it works, phasing, key management.
- Keep the opening statement short and unambiguous, in active voice.

#### Consequences (optional, but expected)

List `Good, because ...`, `Bad, because ...`, and `Neutral, because ...` items. Include costs, risks accepted, and follow-on work or constraints on future decisions. Treat this section as expected for any ADR with real tradeoffs.

#### Confirmation (optional)

How compliance with the decision will be verified. Examples: a code review checklist item, an architecture test, a CI check, a revisit trigger or date.

### Pros and Cons of the Options (optional)

One sub-section per option with `Good`, `Bad`, or `Neutral` arguments. For a rejected option, state the reason it lost.

### More Information (optional)

Anything else a future reader needs: evidence, links to related ADRs, specs, plans, tickets, and commits, notes on retroactive capture, and when the decision should be revisited.

## Local additions to MADR

- ADRs are immutable once accepted (see "Editing discipline").
- `decision-makers` is required.
- The folder is `docs/adr/`.
- Related ADRs, tickets, commits, and external references go in `More Information`, one bullet each.
- A retroactive ADR (a decision already implemented before it was written down) must say so in `More Information`, name who needs to confirm it, and stay `proposed` until they do.

## Editing discipline

ADRs are immutable once their `status` is `accepted`. Specifically:

- Do not rewrite `Context and Problem Statement`, `Decision Outcome`, or `Consequences` of an accepted ADR.
- Fix only typographical errors and broken links in accepted ADRs.
- A one-time mechanical format migration (for example, moving an old-format ADR into the MADR template) is allowed, provided the substance of Context, Decision, and Consequences is unchanged. Say so in the commit message.
- To change a decision, write a new ADR that supersedes the old one and set the old ADR's `status` to `superseded by ADR-NNNN`.
- To retire a decision without replacement, set `status` to `deprecated` and add a short note in `More Information` explaining why.
- `proposed` ADRs may be edited freely until they reach `accepted` or `rejected`.

## Index and navigation

- When an ADR is added or its status changes, update `docs/index.md` if it links to ADRs. Show the title and, for any status other than `accepted`, the status in parentheses.
- Optionally maintain `docs/adr/README.md` as an ADR index listing each ADR by number, title, and status.

## Relationship to other docs

- Use `docs/specs/` for design and rationale at the feature or subsystem level. Specs may reference ADRs.
- Use `docs/plans/` for implementation sequencing and execution. Plans may reference ADRs but should not duplicate their reasoning.
- Use `docs/investigate/` when a decision is still being explored. Promote findings into an ADR once the decision is ready to be recorded.

If a planning or investigation document begins to read like an architectural decision, extract that decision into an ADR rather than letting the plan or investigation carry the long-term weight.
