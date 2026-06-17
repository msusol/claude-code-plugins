---
description: Workflow conventions for locating the canonical docs/ root and applying canonical folder roles
globs: "**/*"
---

# Global project workflow

## Locating the canonical docs root

Before doing significant work, find the **nearest** `docs/` root using this resolution order:

1. Check the directory containing the file being edited (or the current working directory).
2. Walk up toward the repo root, checking each ancestor directory for a `docs/` subdirectory.
3. Stop at the first directory that contains `docs/` — that is the **docs root** for this context.
4. If no `docs/` is found anywhere, create one at the repo root.

Use `docs/index.md` under the resolved docs root as the primary entry point when it exists.

This allows subdirectories that are independent repos (or sub-projects) to maintain their own `docs/` without being overridden by a parent `docs/`.

- Treat the resolved `docs/` as the canonical home for long-lived project documentation.
- Treat `docs/specs/` as the place for feature and subsystem design docs (what to build and why).
- Treat `docs/plans/` as the place for feature-level implementation plans and task-level sequencing (how to execute).
- Treat `docs/roadmap/` as the place for time-based planning and initiative sequencing.
- Treat `docs/investigate/` as the place for investigation logs and issue analysis.
- Treat `docs/process/` as the place for reusable workflow and operational guidance.

