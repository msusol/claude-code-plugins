---
description: Build the docs hub page (docs/.hub/index.html) for this repo, or build and serve it with live rebuilds.
argument-hint: [serve] [project | docs-dir | all [projects-dir]] [--port N]
allowed-tools: Bash
---

Build the docs hub from the planning-docs layout.

Arguments: `$ARGUMENTS` (optional first token `serve`; then a project name, a docs directory,
or `all`; optional `--port N`).

Steps:

1. Resolve what to build:
   - A project name (for example `re-lead-pipeline`): run
     `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/serve_hub.py" --find <name>` from the current
     directory. It searches each parent folder below your home directory for
     `<name>/docs` (or `<group>/<name>/docs`, such as `LosusAIOps/accountant-agent`) and
     prints the docs path. If it finds nothing, say so and stop.
   - A directory: use it, or its `docs/` subfolder if it has one.
   - `all` (optionally followed by a projects directory, default the current one): every
     `<project>/docs` below it, served together with `serve` (see step 3).
   - Nothing: walk up from the current directory and take the first `docs/` found. If none
     exists, say so and stop.
2. Without `serve`: run

   ```bash
   python3 "${CLAUDE_PLUGIN_ROOT}/scripts/build_hub.py" <docs-dir>
   ```

   Report the output path and the counts it prints (plans, ADRs, investigations, TODO items).
   Tell the user the page is `<docs-dir>/.hub/index.html` and that `file://` pages do not
   auto-reload (use `serve` or `build_hub.py --watch`).
3. With `serve`: start the server in the background (Bash `run_in_background: true`):

   ```bash
   python3 "${CLAUDE_PLUGIN_ROOT}/scripts/serve_hub.py" <docs-dir>
   ```

   Add `--port N` if the user gave one. Read its first output lines and report the printed URL, which includes the project slug
   (`http://127.0.0.1:8765/<project>/.hub/index.html` by default; nothing is written into the project).
   It binds to localhost; for another machine use an SSH tunnel or `--host`.
   For `all`, run `serve_hub.py --root <projects-dir> --port <port>` instead: each project is at
   `/<project>/.hub/index.html` and `/` lists them (built in memory, nothing written).
4. If the output shows an empty tab, say which folder was missing (`adr/`, `plans/`,
   `investigate/`); the generator expects the planning-docs layout.
5. If you ran `build_hub.py`, remind the user to add `.hub/` to `.gitignore` if it is not there already (serving does not need it).

If `${CLAUDE_PLUGIN_ROOT}` is empty in your shell, find the plugin with
`ls ~/.claude/plugins/cache/*/docs-hub/*/scripts/build_hub.py` and use that path.
