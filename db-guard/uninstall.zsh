#!/usr/bin/env zsh
# db-guard uninstaller

set -euo pipefail

REPO_DIR="${0:A:h}"
HOOK_DEST="$HOME/.claude/scripts/db-guard-hook.zsh"
CLINERULE_DEST="$HOME/.clinerules/15-db-guard.md"

echo "==> db-guard uninstaller"
echo ""

# Remove hook script
if [[ -f "$HOOK_DEST" ]]; then
  rm "$HOOK_DEST"
  echo "✓ Removed hook: $HOOK_DEST"
else
  echo "  Hook not found — skipping"
fi

# Remove clinerule
if [[ -f "$CLINERULE_DEST" ]]; then
  rm "$CLINERULE_DEST"
  echo "✓ Removed clinerule: $CLINERULE_DEST"
else
  echo "  Clinerule not found — skipping"
fi

# Remove from settings.json
python3 "$REPO_DIR/scripts/manage-settings.py" uninstall

# Unregister plugin
if command -v claude &>/dev/null; then
  claude plugin uninstall db-guard 2>/dev/null || true
  echo "✓ Plugin unregistered"
fi

echo ""
echo "==> db-guard uninstalled. Restart Claude Code to deactivate."
