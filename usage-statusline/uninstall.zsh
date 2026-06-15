#!/usr/bin/env zsh
set -e

SETTINGS="$HOME/.claude/settings.json"

if [ ! -f "$SETTINGS" ]; then
  echo "Nothing to uninstall: $SETTINGS not found"
  exit 0
fi

tmp=$(mktemp)
jq 'del(.statusLine)' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"

cmd_file="$HOME/.claude/commands/usage-statusline-setup.md"
if [ -f "$cmd_file" ]; then
  rm "$cmd_file"
  echo "Uninstalled: /usage-statusline-setup command"
fi

echo "Uninstalled: statusLine removed from $SETTINGS"
