#!/usr/bin/env zsh
# docs uninstaller

set -euo pipefail

REPO_DIR="${0:A:h}"
RULES_SRC="$REPO_DIR/src/rules"
RULES_DEST="$HOME/.claude/rules"

print "==> docs uninstaller"
print ""

# Remove rule files deployed by this plugin from ~/.claude/rules/
if [[ -d "$RULES_DEST" && -d "$RULES_SRC" ]]; then
  removed=0
  for src in "$RULES_SRC"/*.md(N); do
    name="${src:t}"
    dest="$RULES_DEST/$name"
    if [[ -f "$dest" ]]; then
      rm "$dest"
      print "✓ Removed: $dest"
      (( removed++ )) || true
    fi
  done
  if (( removed == 0 )); then
    print "  No plugin rules found in $RULES_DEST — nothing to remove"
  else
    print "✓ Removed $removed rule(s) from $RULES_DEST"
  fi
else
  print "  $RULES_DEST not found — skipping"
fi

# Remove the managed @-import block from ~/.claude/CLAUDE.md
GLOBAL_CLAUDE="$HOME/.claude/CLAUDE.md"
if [[ -f "$GLOBAL_CLAUDE" ]] && grep -qF "BEGIN docs-imports" "$GLOBAL_CLAUDE"; then
  tmp="$(mktemp)"
  awk '
    /<!-- BEGIN docs-imports/ { skip=1; next }
    /<!-- END docs-imports -->/ { skip=0; next }
    !skip { print }
  ' "$GLOBAL_CLAUDE" > "$tmp"
  mv "$tmp" "$GLOBAL_CLAUDE"
  print "✓ Removed @-import block from $GLOBAL_CLAUDE"
else
  print "  No managed block found in $GLOBAL_CLAUDE — skipping"
fi

if command -v claude &>/dev/null; then
  claude plugin uninstall docs 2>/dev/null || true
  print "✓ Plugin unregistered"
fi

print ""
print "==> docs uninstalled."
