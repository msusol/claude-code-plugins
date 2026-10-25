#!/usr/bin/env zsh
# scratch-guard uninstaller — removes all installed files and settings entries.

set -euo pipefail

SCRIPT_DIR="${0:A:h}"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo "${GREEN}✓${NC}  $1" }
warn() { echo "${YELLOW}!${NC}  $1" }
skip() { echo "    $1 (not found, skipping)" }

echo "Uninstalling scratch-guard..."
echo ""

if [[ -f "$HOME/.claude/scripts/scratch-guard-hook.zsh" ]]; then
  rm "$HOME/.claude/scripts/scratch-guard-hook.zsh"
  ok "Removed ~/.claude/scripts/scratch-guard-hook.zsh"
else
  skip "~/.claude/scripts/scratch-guard-hook.zsh"
fi

if command -v claude >/dev/null 2>&1; then
  if claude plugin list 2>/dev/null | grep -qw "scratch-guard"; then
    claude plugin uninstall scratch-guard >/dev/null 2>&1 \
      && ok "Uninstalled plugin 'scratch-guard'" \
      || warn "claude plugin uninstall scratch-guard failed — try by hand"
  else
    skip "claude plugin 'scratch-guard'"
  fi
  # Shared marketplace — leave registered for other plugins (git-guard, etc.)
  skip "shared marketplace 'losus-ai' (left registered for other plugins)"
else
  warn "claude CLI not found on PATH — skipping plugin removal."
fi

if [[ -f "$HOME/.claude/settings.json" ]]; then
  python3 "$SCRIPT_DIR/scripts/manage-settings.py" uninstall
else
  skip "~/.claude/settings.json"
fi

echo ""
echo "Done. Restart Claude Code to apply changes."
