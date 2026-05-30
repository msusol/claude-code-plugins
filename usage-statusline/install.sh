#!/usr/bin/env bash
set -e

PLUGIN_DIR="$(cd "$(dirname "$0")" && pwd)"
SETTINGS="$HOME/.claude/settings.json"

if [ ! -f "$SETTINGS" ]; then
  echo '{}' > "$SETTINGS"
fi

tmp=$(mktemp)
jq --arg cmd "bash $PLUGIN_DIR/statusline.sh" \
  '.statusLine = {"type": "command", "command": $cmd}' \
  "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"

# Clean up old standalone script if it exists
old="$HOME/.claude/statusline-command.sh"
if [ -f "$old" ]; then
  rm "$old"
  echo "Removed legacy $old"
fi

echo "Installed: statusLine -> $PLUGIN_DIR/statusline.sh"
