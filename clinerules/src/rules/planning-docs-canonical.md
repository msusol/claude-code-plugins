---
description: Canonical layout and folder roles under docs/ (adr, specs, plans, roadmap, process, investigate, index)
paths:
  - docs/**/*.md
---

# Canonical documentation model

- Treat `docs/` as the canonical in-repo home for long-lived project documentation.
- Treat `docs/index.md` as the primary entry point to the documentation set when it exists.
- Prefer updating existing docs over creating duplicate markdown files.
- When a new long-lived document is added, update `docs/index.md` with a link when appropriate.

## Folder roles

Use the following roles under `docs/`:

- `docs/adr/`
  - Architecture Decision Records.
  - Historical decisions, tradeoffs, and superseding decisions.

- `docs/specs/`
  - Feature specifications.
  - Subsystem design docs.
  - Implementation planning at the design level: what to build and why.

- `docs/plans/`
  - Feature-level implementation plans.
  - Task decomposition and sequencing.
  - Vibe-planning artifacts with an LLM that are durable enough to keep in-repo.
  - Execution companions to specs: how to carry out the work.

- `docs/roadmap/`
  - Time-based planning.
  - Major initiative sequencing.
  - Roadmap and migration plans.

- `docs/process/`
  - Reusable operational guidance.
  - Team workflows.
  - Documentation-writing and planning processes.

- `docs/investigate/`
  - Analyst-mode issue investigations.
  - Debugging trails and validation logs.
  - Pre-GA issue punchlists and similar.

- `docs/index.md`
  - Top-level navigation entry point for the docs system.
  - Overview of the project and links to key ADRs, specs, plans, roadmap entries, process docs, and investigations.

## Practical classification rule

If a document is expected to matter in 6 months, it should probably live in `docs/`.

- Use `docs/adr/` when capturing an architectural decision, its tradeoffs, and what it supersedes.
- Use `docs/specs/` when the primary goal is capturing the design, rationale, and constraints of a feature or subsystem.
- Use `docs/plans/` when the primary goal is breaking work down into tasks, sequencing implementation, and coordinating execution.
- Use `docs/roadmap/` for time-based and cross-feature planning.
- Use `docs/process/` for reusable ways of working.
- Use `docs/investigate/` for investigation logs with lasting value.

Disambiguating ADR vs spec vs plan:

- An ADR records a single decision and the reasoning behind it. It is immutable once accepted.
- A spec describes what to build and why for a feature or subsystem. It evolves alongside the design.
- A plan describes how and when to execute the work. It evolves alongside implementation.

If a decision is large enough to drive multiple specs or plans, capture it as an ADR and reference the ADR from those documents.

## Legacy locations

- Legacy `plan.md`, `plans.md`, and top-level `plans/` paths should be treated as transitional.
- New long-lived planning artifacts should be created under `docs/plans/` rather than in legacy locations.
- As part of migration, durable content from legacy plan files should be moved into `docs/specs/`, `docs/plans/`, or `docs/roadmap/` as appropriate.
