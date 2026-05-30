#!/usr/bin/env bash
set -e

SETTINGS="$HOME/.claude/settings.json"

if [ ! -f "$SETTINGS" ]; then
  echo "Nothing to uninstall: $SETTINGS not found"
  exit 0
fi

tmp=$(mktemp)
jq 'del(.statusLine)' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"

echo "Uninstalled: statusLine removed from $SETTINGS"
