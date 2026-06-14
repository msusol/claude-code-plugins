#!/usr/bin/env zsh
# clinerules installer — idempotent, safe to re-run.
#
# What this does:
#   1. Copies link-clinerules.sh to ~/.claude/scripts/link-clinerules.sh
#   2. Registers this repo as a Claude Code plugin marketplace and installs clinerules
#
# Prerequisites:
#   - Claude Code CLI (claude) installed

set -euo pipefail

REPO_DIR="${0:A:h}"
SCRIPT_SRC="$REPO_DIR/src/link-clinerules.sh"
SCRIPT_DEST="$HOME/.claude/scripts/link-clinerules.sh"

print "==> clinerules installer"
print ""

# 1. Install link-clinerules.sh globally
mkdir -p "$HOME/.claude/scripts"
cp "$SCRIPT_SRC" "$SCRIPT_DEST"
chmod +x "$SCRIPT_DEST"
print "✓ Installed script: $SCRIPT_DEST"

# 2. Claude Code plugin registration
if command -v claude &>/dev/null; then
  claude plugin marketplace add "$REPO_DIR" 2>/dev/null || true
  claude plugin install clinerules@clinerules 2>/dev/null || true
  print "✓ Plugin registered with Claude Code"
else
  print "⚠ claude CLI not found — skipping plugin registration"
  print "  Run manually: claude plugin marketplace add $REPO_DIR && claude plugin install clinerules@clinerules"
fi

print ""
print "==> clinerules installed."
print "    Use /install-clinerules in any project to link the global ruleset."
print "    Or run directly: ~/.claude/scripts/link-clinerules.sh [project-root]"
