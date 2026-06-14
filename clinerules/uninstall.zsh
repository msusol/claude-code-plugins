#!/usr/bin/env zsh
# clinerules uninstaller

set -euo pipefail

SCRIPT_DEST="$HOME/.claude/scripts/link-clinerules.sh"

print "==> clinerules uninstaller"
print ""

if [[ -f "$SCRIPT_DEST" ]]; then
  rm "$SCRIPT_DEST"
  print "✓ Removed script: $SCRIPT_DEST"
else
  print "  Script not found — skipping"
fi

if command -v claude &>/dev/null; then
  claude plugin uninstall clinerules 2>/dev/null || true
  print "✓ Plugin unregistered"
fi

print ""
print "==> clinerules uninstalled."
print "    Existing .clinerules/ symlinks in projects are untouched."
