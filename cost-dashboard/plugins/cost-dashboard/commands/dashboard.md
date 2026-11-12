---
description: Build and open a cost dashboard (per session, per task, per model) from local Claude Code logs.
argument-hint: "[--days N] [--project SUBSTRING] [--root DIR]"
allowed-tools: Bash(python3:*), Bash(open:*), Bash(xdg-open:*)
---

Generate the Claude Code cost dashboard.

1. Run:
   `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/build_dashboard.py" --out "$HOME/.claude/cost-dashboard.html" $ARGUMENTS`
2. The script prints a short text summary (total cost, top sessions). Show that summary to the user.
3. Tell the user the dashboard is at `~/.claude/cost-dashboard.html`. If they want it opened, run `open` (macOS) or `xdg-open` (Linux) on it.
4. Remind them costs are estimates computed from token counts and `pricing.json`; if a model was flagged as "unpriced", offer to help update `${CLAUDE_PLUGIN_ROOT}/pricing.json`.

Do not read the session log files yourself; the script does all parsing.
