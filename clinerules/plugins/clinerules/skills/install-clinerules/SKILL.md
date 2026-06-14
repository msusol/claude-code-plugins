---
name: install-clinerules
description: >
  Use this skill whenever the user wants to install, link, or sync clinerules
  into the current project. Trigger on: /install-clinerules, "install clinerules",
  "link clinerules", "set up clinerules", "add clinerules to this project",
  "sync clinerules", or any request to wire the global ~/.clinerules/ ruleset
  into the project's .clinerules/ directory.
version: 1.0.0
---

# install-clinerules

Symlinks every file in `~/.clinerules/` into `<project-root>/.clinerules/` and
updates the `@-import` block in `~/.claude/CLAUDE.md` to match.

## Step 1 — Confirm project root

The project root is the current working directory. State it:

```
Project root: $PWD
```

If the user specified a different path, use that instead.

## Step 2 — Run the linker

```bash
~/.claude/scripts/link-clinerules.sh "$PWD"
```

To overwrite existing symlinks (re-sync after adding new rules):

```bash
~/.claude/scripts/link-clinerules.sh --force "$PWD"
```

Use `--force` when the user says "force", "overwrite", "re-sync", or "update existing".
Default (no flag) skips already-linked files and only adds new ones.

## Step 3 — Report results

Show the full output from the script. Summarise:

- How many rules were linked (new symlinks created)
- How many were skipped (already linked)
- Whether `~/.claude/CLAUDE.md` was updated

## Step 4 — Verify

Confirm the `.clinerules/` directory in the project now contains symlinks pointing
to `~/.clinerules/`:

```bash
ls -la "$PWD/.clinerules/" | head -20
```

Report any rules present in `~/.clinerules/` that are still missing from the project.
