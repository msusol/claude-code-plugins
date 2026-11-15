---
description: Build the cost dashboard (per session, per task, per model) from local Claude Code logs, or serve it live on localhost.
argument-hint: "[serve] [--days N] [--project SUBSTRING] [--root DIR] [--ab-root DIR] [--no-ab-sessions] [--port N]"
allowed-tools: Bash(python3:*), Bash(open:*), Bash(xdg-open:*), Bash(ls:*)
---

Generate the Claude Code cost dashboard.

Arguments: `$ARGUMENTS`. An optional first token `serve` selects the live server; everything after it is passed through as-is.

Do not read the session log files yourself; the scripts do all parsing.

## Without `serve`: build the static page

1. Run:
   `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/build_dashboard.py" --out "$HOME/.claude/cost-dashboard.html" $ARGUMENTS`
2. The script prints a short text summary (total cost, top sessions). Show that summary to the user.
3. Tell the user the dashboard is at `~/.claude/cost-dashboard.html`. If they want it opened, run `open` (macOS) or `xdg-open` (Linux) on it. A `file://` page does not update; for a live page use `serve`.
4. Remind them costs are estimates computed from token counts and `pricing.json`; if a model was flagged as "unpriced", offer to help update `${CLAUDE_PLUGIN_ROOT}/pricing.json`.

## With `serve`: run the live dashboard

1. Start the server in the background (Bash `run_in_background: true`), passing the arguments after `serve`:

   ```bash
   python3 "${CLAUDE_PLUGIN_ROOT}/scripts/serve_dashboard.py" <arguments after serve>
   ```

   It accepts `--days N` (default 30, 0 = all), `--project SUBSTRING`, `--root DIR`, `--ab-root DIR` (A/B runs, default `$AB_RUNS_DIR` or `~/experiments/runs`), `--no-ab-sessions` (do not count the A/B runs' sessions in the other tabs), `--port N` (default 8766) and `--host`. Do not pass `--out`: the server builds in memory and writes nothing.
2. Read its first output lines and report the printed URL (`http://127.0.0.1:8766/` by default). The data behind the page is at `/data.json`.
3. If it exits with `cannot listen on`, that port is taken. Say which port, do not stop whatever holds it, and start again on the next free port, telling the user the port you used. If it exits with `No session logs found`, report the folder it searched and stop.
4. Tell the user:
   - the page rebuilds itself from the session logs when they change, so reloading the browser shows the latest costs;
   - it binds to localhost only and refuses requests with any other `Host` header; from another machine use an SSH tunnel to the port;
   - to stop it, stop the background task (or press Ctrl-C if they started it themselves).
5. Same estimate caveat as above: costs are computed from token counts and `pricing.json`, not billed amounts.

If `${CLAUDE_PLUGIN_ROOT}` is empty in your shell, find the plugin with
`ls ~/.claude/plugins/cache/*/cost-dashboard/*/scripts/build_dashboard.py` and use that path.
