---
description: Configure the Claude Code status line to show usage-statusline metrics
---

Configure the `statusLine` setting in `~/.claude/settings.json` to use the usage-statusline plugin.

Steps:
1. Find the `statusline.sh` script by searching for it under `~/.claude`:
   ```bash
   find ~/.claude -name "statusline.sh" -path "*/usage-statusline/*" 2>/dev/null | head -1
   ```
2. If not found, tell the user the plugin does not appear to be installed and stop.
3. Read `~/.claude/settings.json` (create it as `{}` if it does not exist).
4. Set `.statusLine` to `{"type": "command", "command": "bash \"<path>\""}` where `<path>` is the absolute path from step 1.
5. Write the updated JSON back to `~/.claude/settings.json`.
6. Confirm to the user: show the final `statusLine` value and note that it will appear after the first message in a new session.
