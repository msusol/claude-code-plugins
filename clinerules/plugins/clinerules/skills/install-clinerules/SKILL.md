---
name: install-clinerules
description: >
  Use this skill whenever the user wants to install, deploy, or sync clinerules
  globally. Trigger on: /install-clinerules, "install clinerules",
  "deploy clinerules", "set up clinerules", "sync clinerules", or any request
  to deploy the global ~/.clinerules/ ruleset to ~/.cline/rules/.
version: 2.0.0
---

# install-clinerules

Deploys every file in `<repo>/src/rules/` to `~/.cline/rules/`, Cline's native
global rules directory. Rules there are loaded automatically in every project —
no per-project setup needed.

## Step 1 — Locate the plugin repo

Find the clinerules plugin repo. It is typically at one of:

```bash
ls ~/LosusAI/Projects/Claude/claude-code-plugins/clinerules/deploy.zsh 2>/dev/null \
  || ls ~/claude-code-plugins/clinerules/deploy.zsh 2>/dev/null
```

Use whichever path exists. If neither exists, ask the user where the repo is cloned.

## Step 2 — Run the installer

```bash
<repo-path>/deploy.zsh
```

To force-update all rules (even unchanged ones), there is no `--force` flag —
re-running `deploy.zsh` is idempotent and always copies changed files.

## Step 3 — Report results

Show the full output from the script. Summarise:

- How many rules were installed (new files)
- How many were updated (changed files)
- The destination directory (`~/.cline/rules/`)

## Step 4 — Verify

Confirm the rules are present in `~/.cline/rules/`:

```bash
ls -1 ~/.cline/rules/
```

Report the count. Rules are loaded globally by Cline in every project — no
further per-project setup is required.