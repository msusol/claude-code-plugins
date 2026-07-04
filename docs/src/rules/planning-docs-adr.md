---
description: Authoring rules for Architecture Decision Records under docs/adr/ (numbering, required sections, immutability, superseding)
paths:
  - docs/adr/**/*.md
---

# Architecture Decision Record (ADR) rules

Treat files under `docs/adr/` as Architecture Decision Records.

ADRs capture a single architectural decision, the context that forced it, the alternatives considered, and the consequences of choosing it. They are append-only history, not living design docs.

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

- Place ADRs directly under `docs/adr/`.
- Name files `NNNN-kebab-case-title.md`, where `NNNN` is a zero-padded sequential number, for example `0007-adopt-oci-queue-for-ingestion.md`.
- Allocate the next unused number by scanning existing files in `docs/adr/`.
- Do not reuse numbers, even when an ADR is superseded or rejected.

## Required structure

Every ADR must include these top-level sections in this order:

- `# NNNN. <Decision title>`
- `## Status`
- `## Context`
- `## Decision`
- `## Consequences`

Optional sections, added only when they add real value:

- `## Alternatives considered`
- `## Related decisions`
- `## References`

### Status

`## Status` must contain one of these values on its own line:

- `Proposed`
- `Accepted`
- `Superseded by ADR-NNNN`
- `Deprecated`
- `Rejected`

When superseding, link to the superseding ADR by number and title.

### Context

`## Context` describes:

- the forces, constraints, and requirements that motivated the decision
- relevant prior state, prior ADRs, or external drivers
- the problem being solved, in terms that will still make sense in 6 months

Do not record the decision itself here.

### Decision

`## Decision` states:

- what was decided
- in active voice and present tense, for example "We will use OCI Queue for ingestion."

Keep this section short and unambiguous.

### Consequences

`## Consequences` records:

- positive consequences and capabilities unlocked
- negative consequences, costs, and risks accepted
- follow-on work or constraints imposed on future decisions

### Alternatives considered

When included, list each alternative with a brief reason it was not chosen.

## Editing discipline

ADRs are immutable once their status is `Accepted`. Specifically:

- Do not rewrite `Context`, `Decision`, or `Consequences` of an accepted ADR.
- Fix only typographical errors and broken links in accepted ADRs.
- To change a decision, write a new ADR that supersedes the old one and update the old ADR's `Status` to `Superseded by ADR-NNNN`.
- To retire a decision without replacement, set `Status` to `Deprecated` and add a short note explaining why.
- `Proposed` ADRs may be edited freely until they reach `Accepted` or `Rejected`.

## Index and navigation

- When an ADR is added or its status changes, update `docs/index.md` if it links to ADRs.
- Optionally maintain `docs/adr/README.md` as an ADR index listing each ADR by number, title, and status.

## Relationship to other docs

- Use `docs/specs/` for design and rationale at the feature or subsystem level. Specs may reference ADRs.
- Use `docs/plans/` for implementation sequencing and execution. Plans may reference ADRs but should not duplicate their reasoning.
- Use `docs/investigate/` when a decision is still being explored. Promote findings into an ADR once the decision is ready to be recorded.

If a planning or investigation document begins to read like an architectural decision, extract that decision into an ADR rather than letting the plan or investigation carry the long-term weight.