#!/usr/bin/env zsh
# db-guard uninstaller

set -euo pipefail

REPO_DIR="${0:A:h}"
HOOK_DEST="$HOME/.claude/scripts/db-guard-hook.zsh"
RULE_DEST="$HOME/.cline/rules/dbguard-destructive-ops.md"
GLOBAL_CLAUDE="$HOME/.claude/CLAUDE.md"

echo "==> db-guard uninstaller"
echo ""

# Remove hook script
if [[ -f "$HOOK_DEST" ]]; then
  rm "$HOOK_DEST"
  echo "✓ Removed hook: $HOOK_DEST"
else
  echo "  Hook not found — skipping"
fi

# Remove rule file
if [[ -f "$RULE_DEST" ]]; then
  rm "$RULE_DEST"
  echo "✓ Removed rule: $RULE_DEST"
else
  echo "  Rule not found — skipping"
fi

# Remove @-import block from ~/.claude/CLAUDE.md
if [[ -f "$GLOBAL_CLAUDE" ]] && grep -qF "<!-- BEGIN db-guard-imports" "$GLOBAL_CLAUDE"; then
  tmp="$(mktemp)"
  awk '
    /^## / {
      if (hdr != "") { printf "%s%s", buf, hdr; buf = ""; hdr = "" }
      hdr = buf $0 "\n"; buf = ""; next
    }
    /^[[:space:]]*$/ {
      if (hdr != "") { hdr = hdr "\n"; next }
      buf = buf "\n"; next
    }
    /<!-- BEGIN db-guard-imports/ { hdr = ""; buf = ""; skip = 1; next }
    /<!-- END db-guard-imports -->/ { skip = 0; next }
    skip { next }
    {
      printf "%s%s", hdr, buf
      hdr = ""; buf = ""
      print
    }
    END {
      if (hdr != "") printf "%s", hdr
      printf "%s", buf
    }
  ' "$GLOBAL_CLAUDE" > "$tmp"
  mv "$tmp" "$GLOBAL_CLAUDE"
  echo "✓ Removed @-import block from $GLOBAL_CLAUDE"
else
  echo "  No managed block found in $GLOBAL_CLAUDE — skipping"
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
