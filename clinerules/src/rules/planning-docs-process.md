---
description: Authoring rules for reusable operational guidance under docs/process/ and trigger for creating process docs when runnable artifacts are added
paths:
  - docs/process/**/*.md
---

# Process document rules

Treat files under `docs/process/` as reusable operational guides — stable
enough to live in the repo, likely to be followed repeatedly, and owned by
the team rather than a single task.

## When to create a process document

Create or update a process document when one or more of the following is true:

- A new runnable artifact is added to the repo: a script, a Docker Compose
  service, a CLI tool, a Makefile target, or a scheduled job. Add usage
  instructions before closing the task.
- A recurring workflow emerges that takes more than one non-obvious step to
  execute correctly.
- A setup or environment procedure is documented in an investigation log and
  is likely to be repeated by others. Promote the steps into a process doc
  and reference it from the investigation.
- A previous process doc needs to be updated because prerequisites, commands,
  or expected outputs have changed.

Do not create a process document for:

- One-off commands that are already covered by inline code comments or a plan.
- Short-lived setup steps that apply only to a single task.

## Trigger: runnable artifacts

Whenever a runnable artifact is added or substantially changed, check whether
a process document exists that covers it. If not, create one. If one exists,
update it.

Runnable artifacts include but are not limited to:

- `compose.yaml` services
- Shell scripts under `scripts/`
- CLI tools or entry-point binaries
- Makefile targets intended for regular use
- Cron jobs or scheduled tasks

## File naming and location

- Place process documents directly under `docs/process/`.
- Use descriptive kebab-case filenames, e.g. `dgx-gpu-workflow.md`,
  `deploy-staging.md`, `run-integration-tests.md`.
- One document per distinct workflow. Related workflows may share a file if
  they are tightly coupled (e.g., build + test + deploy in a single CI doc).

## Required structure

Every process document must include:

- `# <Workflow title>`
- `## Prerequisites` — software, credentials, environment, or access required
  before following the process
- `## Steps` — numbered, executable steps with exact commands

Optional sections, added when they add value:

- `## Expected output` — what success looks like
- `## Troubleshooting` — known failure modes and their fixes
- `## Related docs` — links to ADRs, specs, investigations, or plans that
  inform this process

## Cross-referencing specs

When a process doc implements or operates a feature described in `docs/specs/`, the link
must be bidirectional:

1. The process doc must include `## Related docs` with a relative markdown link to the spec:
   `[Title](../specs/feature-name/spec.md)`
2. The spec must include `## Related docs` with a relative markdown link back to the process doc:
   `[Title](../process/doc-name.md)`

Use relative markdown links — not backtick paths — so links are navigable in rendered markdown.
When adding a new process doc for an existing spec, update the spec's `## Related docs` in the
same commit.

## Editing discipline

Process documents are living docs — update them when the process changes.
When a step or prerequisite changes materially, update the doc in the same
commit as the artifact change. Do not let process docs lag behind the code.