#!/usr/bin/env zsh
# db-guard installer — idempotent, safe to re-run.
#
# What this does:
#   1. Copies the PreToolUse hook to ~/.claude/scripts/db-guard-hook.zsh
#   2. Copies the clinerule to ~/.clinerules/dbguard-destructive-ops.md
#      (removes legacy ~/.clinerules/15-db-guard.md if present)
#   3. Merges the hook entry into ~/.claude/settings.json
#   4. Registers this repo as a Claude Code plugin marketplace and installs db-guard
#
# Prerequisites:
#   - Claude Code CLI (claude) installed
#   - Python 3

set -euo pipefail

REPO_DIR="${0:A:h}"
HOOK_SRC="$REPO_DIR/src/db-guard-hook.zsh"
CLINERULE_SRC="$REPO_DIR/src/clinerule-dbguard-destructive-ops.md"
HOOK_DEST="$HOME/.claude/scripts/db-guard-hook.zsh"
CLINERULE_DEST="$HOME/.clinerules/dbguard-destructive-ops.md"
CLINERULE_LEGACY="$HOME/.clinerules/15-db-guard.md"

echo "==> db-guard installer"
echo ""

# 1. Hook script
mkdir -p "$HOME/.claude/scripts"
cp "$HOOK_SRC" "$HOOK_DEST"
chmod +x "$HOOK_DEST"
echo "✓ Installed hook: $HOOK_DEST"

# 2. Clinerule
mkdir -p "$HOME/.clinerules"
cp "$CLINERULE_SRC" "$CLINERULE_DEST"
echo "✓ Installed clinerule: $CLINERULE_DEST"
if [[ -f "$CLINERULE_LEGACY" ]]; then
  rm "$CLINERULE_LEGACY"
  echo "✓ Removed legacy clinerule: $CLINERULE_LEGACY"
fi

# 3. settings.json merge
python3 "$REPO_DIR/scripts/manage-settings.py" install

# 4. Claude Code plugin registration
if command -v claude &>/dev/null; then
  claude plugin marketplace add "$REPO_DIR" 2>/dev/null || true
  claude plugin install db-guard@db-guard 2>/dev/null || true
  echo "✓ Plugin registered with Claude Code"
else
  echo "⚠ claude CLI not found — skipping plugin registration"
  echo "  Run manually: claude plugin marketplace add $REPO_DIR && claude plugin install db-guard@db-guard"
fi

echo ""
echo "==> db-guard installed. Restart Claude Code to activate the hook and /db-drop skill."
