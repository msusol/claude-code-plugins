---
description: Turn handed-over research, a vibe plan or a feature description into the docs/ set (spec, ADRs, plan, TODO, index) before any implementation
globs: "**/*"
---

# Planning intake: porting research into docs/

This rule covers the moment a person hands over planning material and asks for it to be planned or ported. The other `planning-*` rules say how each document is written; this one says which documents to create, in what order, and where to stop.

## When this applies

Both of these hold:

- The message carries a body of planning material: a research dump, a vibe plan from another tool or session, a feature description, a list of requirements.
- It asks to port, ingest, plan, document, write up or "turn this into" a plan, spec or docs. A message that calls its own content a "vibe plan" or "research dump" counts.

A message made mostly of planning material with no other instruction also counts: nothing else is being asked, so port it.

It does not apply to a bug fix, a small change, a question, a pasted error log, or a request to implement a plan that already exists. For those, follow the usual rules.

## Steps

1. **Find the docs root and what is already there.** Follow `planning-global.md`. Read `docs/index.md` and list the existing specs, ADRs and plans. Update an existing document when one covers the topic; do not start a parallel one.
2. **Classify the material** using the practical classification rule in `planning-docs-canonical.md`:
   - what to build and why, with the constraints -> a spec under `docs/specs/`
   - a decision with real tradeoffs between alternatives -> an ADR under `docs/adr/`, status `proposed`
   - tasks and their order -> a plan under `docs/plans/`, with a matching `TODO.md` section
   - dates and sequencing across initiatives -> `docs/roadmap/`
   - things the material does not settle -> `Open questions` in the spec
3. **Create the documents in this order:** spec, ADRs, plan, `TODO.md` section, then `docs/index.md` links. Number the plan and ADRs by the rules in `planning-docs-plans.md` and `planning-docs-adr.md`. Keep each one minimal; expand only where the material needs it.
4. **Do not invent and do not decide for the owner.**
   - Where the material is silent or ambiguous, write an open question with a recommended answer. Do not pick an answer and present it as agreed.
   - Leave ADRs `proposed` and plan tasks that depend on an owner decision unchecked.
   - Treat claims copied from another AI session as unverified, as `planning-ai-skepticism.md` requires, and say so in the spec.
5. **Check the tree.** If a new directory was created, update any directory listing in the nearest `CLAUDE.md` (`planning-directory-index-sync.md`).
6. **Commit the documents** under the commit rules, with the check recorded.

## Where to stop

Stop after the documents are written and committed. Do not write application code or tests unless the same message asked for implementation, or the person approves the plan afterwards. An explicit instruction in the request about how far to go (for example "planning only") always wins; this is the default when there is none.

Then report in a few lines: what was created and where, the open questions that need an owner decision, and what you would do first when told to implement.

If the same message does ask for implementation, write the documents first, then implement the plan's tasks in order, committing after each task and keeping the plan and `TODO.md` in step (`planning-plan-sync.md`).
