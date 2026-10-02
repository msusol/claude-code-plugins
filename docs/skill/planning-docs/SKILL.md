---
name: planning-docs
description: Write out or update a project's docs/ folder using Mark's canonical documentation model (docs/adr, specs, plans, roadmap, process, investigate, index.md). Use when the user asks to "write out docs/", "write the docs", "create docs for this project", draft or update an ADR, spec, implementation plan, roadmap, process doc, investigation log, or docs/plans/TODO.md, or to organize/migrate existing planning notes into docs/.
---

# Planning docs

Generates and maintains a project's `docs/` tree in a fixed, opinionated layout. The detailed
authoring rules live in `references/`; read only the ones the task needs.

## Workflow

1. **Resolve the docs root.** Read `references/planning-global.md`. Work in the nearest `docs/`
   directory; if none exists in the user's material, create `docs/` at the root of what you produce.
2. **Classify each document** using the table below, then read that reference before drafting.
3. **Draft minimal first.** Specs and plans start in minimal form and expand only when content
   earns it (details in each reference).
4. **Update `docs/index.md`** with a link for every new long-lived document.
5. **Deliver the result** as real files in the `docs/` layout (one `.md` per document). When
   more than one file is produced, also deliver a zip of the `docs/` folder.

## Which reference to read

| Document type | Folder | Read |
|---|---|---|
| Single architectural decision, immutable once accepted | `docs/adr/` | `references/planning-docs-adr.md` |
| What to build and why (feature or subsystem design) | `docs/specs/` | `references/planning-docs-specs.md` |
| How to execute: tasks, sequencing | `docs/plans/` | `references/planning-docs-plans.md`, `references/planning-plan-sync.md` |
| Time-based or cross-feature sequencing | `docs/roadmap/` | `references/planning-docs-canonical.md` |
| Reusable workflows and operational guidance | `docs/process/` | `references/planning-docs-process.md` |
| Debugging trails, issue analysis | `docs/investigate/` | `references/planning-docs-investigate.md`, `references/planning-ai-skepticism.md` |
| Non-markdown files (csv, xlsx, pdf, screenshots) beside docs | alongside the doc | `references/planning-docs-artifacts.md` |
| Folder roles, index, legacy plan files | `docs/`, `docs/index.md` | `references/planning-docs-canonical.md` |
| Plans and `docs/plans/TODO.md` drifting apart | `docs/plans/` | `references/planning-desync-cleanup.md` |

Always read `references/planning-global.md` and `references/planning-docs-canonical.md` first for
a full `docs/` write-out.

## Formatting rules for every document

- Diagrams: fenced `mermaid` blocks, never ASCII art (`references/planning-markdown-diagrams.md`).
- Multi-flag shell commands in code blocks: one flag per line with continuations
  (`references/planning-markdown-codeblocks.md`).
- Prefer updating an existing doc over creating a duplicate.
- Treat anything attributed to a prior AI session as an unverified hypothesis; check it against
  the user's actual material before building a doc around it (`references/planning-ai-skepticism.md`).

## Scope note

The references are the same rule files the `docs` Claude Code plugin deploys to `~/.claude/rules/`,
with Claude Code frontmatter (`paths`, `globs`) removed. Mentions of `CLAUDE.md`, repo paths, or
git/PR steps assume a code repository; when working outside one, apply the document structure
and skip the repo-specific steps.
