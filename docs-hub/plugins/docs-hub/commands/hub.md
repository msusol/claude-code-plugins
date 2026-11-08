---
description: Build the docs hub page (docs/.hub/index.html) for this repo, or build and serve it with live rebuilds.
argument-hint: [serve] [docs-dir]
allowed-tools: Bash
---

Build the docs hub from the planning-docs layout.

Arguments: `$ARGUMENTS` (optional first token `serve`; optional docs directory, default: the
nearest `docs/` found from the current directory upward).

Steps:

1. Resolve the docs directory. If an argument names one, use it. Otherwise walk up from the
   current directory and take the first `docs/` found. If none exists, say so and stop.
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

   Read its first output lines and report the printed URL (default `http://127.0.0.1:8765/`).
   It binds to localhost; for another machine use an SSH tunnel or `--host`.
4. If the output shows an empty tab, say which folder was missing (`adr/`, `plans/`,
   `investigate/`); the generator expects the planning-docs layout.
5. Remind the user to add `.hub/` to `.gitignore` if it is not there already.

If `${CLAUDE_PLUGIN_ROOT}` is empty in your shell, find the plugin with
`ls ~/.claude/plugins/cache/*/docs-hub/*/scripts/build_hub.py` and use that path.
