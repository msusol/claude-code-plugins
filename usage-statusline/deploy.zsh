#!/usr/bin/env zsh
set -e

PLUGIN_DIR="$(cd "$(dirname "$0")" && pwd)"
SETTINGS="$HOME/.claude/settings.json"

if [ ! -f "$SETTINGS" ]; then
  echo '{}' > "$SETTINGS"
fi

tmp=$(mktemp)
jq --arg cmd "zsh $PLUGIN_DIR/statusline.zsh" \
  '.statusLine = {"type": "command", "command": $cmd}' \
  "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"

# Clean up old standalone script if it exists
old="$HOME/.claude/statusline-command.sh"
if [ -f "$old" ]; then
  rm "$old"
  echo "Removed legacy $old"
fi

mkdir -p "$HOME/.claude/commands"
cp "$PLUGIN_DIR/commands/setup.md" "$HOME/.claude/commands/usage-statusline-setup.md"

echo "Installed: statusLine -> $PLUGIN_DIR/statusline.zsh"
echo "Installed: /usage-statusline-setup command"
