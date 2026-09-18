#!/usr/bin/env zsh
# db-guard installer — idempotent, safe to re-run.
#
# What this does:
#   1. Copies the PreToolUse hook to ~/.claude/scripts/db-guard-hook.zsh
#   2. Copies the rule to ~/.claude/rules/dbguard-destructive-ops.md
#   3. Adds a managed @-import block to ~/.claude/CLAUDE.md for Claude Code
#   4. Merges the hook entry into ~/.claude/settings.json
#   5. Registers this repo as a Claude Code plugin marketplace and installs db-guard
#
# Claude Code-native only — this plugin does not support Cline. Rules live in
# ~/.claude/rules/ (Claude Code's own rules directory) and are pulled into every
# session via @-imports in ~/.claude/CLAUDE.md.
#
# Prerequisites:
#   - Claude Code CLI (claude) installed
#   - Python 3

set -euo pipefail

REPO_DIR="${0:A:h}"
HOOK_SRC="$REPO_DIR/src/db-guard-hook.zsh"
RULE_SRC="$REPO_DIR/src/rules/dbguard-destructive-ops.md"
HOOK_DEST="$HOME/.claude/scripts/db-guard-hook.zsh"
RULE_DEST="$HOME/.claude/rules/dbguard-destructive-ops.md"
GLOBAL_CLAUDE="$HOME/.claude/CLAUDE.md"
BEGIN_MARKER="<!-- BEGIN db-guard-imports (managed by deploy.zsh) -->"
END_MARKER="<!-- END db-guard-imports -->"

echo "==> db-guard installer"
echo ""

# 1. Hook script
mkdir -p "$HOME/.claude/scripts"
cp "$HOOK_SRC" "$HOOK_DEST"
chmod +x "$HOOK_DEST"
echo "✓ Installed hook: $HOOK_DEST"

# 2. Rule file
mkdir -p "$HOME/.claude/rules"
cp "$RULE_SRC" "$RULE_DEST"
echo "✓ Installed rule: $RULE_DEST"

# 3. @-import block in ~/.claude/CLAUDE.md
import="@~/.claude/rules/dbguard-destructive-ops.md"
if [[ ! -f "$GLOBAL_CLAUDE" ]]; then
  mkdir -p "${GLOBAL_CLAUDE:h}"
  cat > "$GLOBAL_CLAUDE" <<EOF
# Global Rules

The following rules apply across all projects.

$BEGIN_MARKER
$import
$END_MARKER
EOF
  echo "✓ Created $GLOBAL_CLAUDE with @-import block"
elif grep -qF "$BEGIN_MARKER" "$GLOBAL_CLAUDE" && grep -qF "$END_MARKER" "$GLOBAL_CLAUDE"; then
  tmp="$(mktemp)"
  awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" -v body="$import" '
    $0 == begin { print; print body; skip=1; next }
    $0 == end   { skip=0; print; next }
    !skip       { print }
  ' "$GLOBAL_CLAUDE" > "$tmp"
  mv "$tmp" "$GLOBAL_CLAUDE"
  echo "✓ Updated $GLOBAL_CLAUDE (@-import block)"
else
  printf '\n%s\n%s\n%s\n' "$BEGIN_MARKER" "$import" "$END_MARKER" >> "$GLOBAL_CLAUDE"
  echo "✓ Appended @-import block to $GLOBAL_CLAUDE"
fi

# 4. settings.json merge
python3 "$REPO_DIR/scripts/manage-settings.py" install

# 5. Claude Code plugin registration
if command -v claude &>/dev/null; then
  claude plugin marketplace add "${REPO_DIR:h}" 2>/dev/null || true
  claude plugin install db-guard@losus-ai 2>/dev/null || true
  echo "✓ Plugin registered with Claude Code"
else
  echo "⚠ claude CLI not found — skipping plugin registration"
  echo "  Run manually: claude plugin marketplace add ${REPO_DIR:h} && claude plugin install db-guard@losus-ai"
fi

echo ""
echo "==> db-guard installed. Restart Claude Code to activate the hook and /db-drop skill."
