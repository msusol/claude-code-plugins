#!/usr/bin/env zsh
# kaggle plugin uninstaller

set -euo pipefail

REPO_DIR="${0:A:h}"
RULES_SRC="$REPO_DIR/src/rules"
RULES_DEST="$HOME/.cline/rules"
GLOBAL_CLAUDE="$HOME/.claude/CLAUDE.md"
BEGIN_MARKER="<!-- BEGIN kaggle-imports (managed by deploy.zsh) -->"
END_MARKER="<!-- END kaggle-imports -->"

print "==> kaggle uninstaller"
print ""

# Remove kaggle-* rules from ~/.cline/rules/
if [[ -d "$RULES_DEST" && -d "$RULES_SRC" ]]; then
  removed=0
  for src in "$RULES_SRC"/kaggle-*.md(N); do
    name="${src:t}"; dest="$RULES_DEST/$name"
    if [[ -f "$dest" ]]; then
      rm "$dest"; print "✓ Removed: $dest"; (( removed++ )) || true
    fi
  done
  (( removed == 0 )) && print "  No plugin rules found in $RULES_DEST"
else
  print "  $RULES_DEST not found — skipping"
fi

# Remove the managed kaggle-imports block from ~/.claude/CLAUDE.md
if [[ -f "$GLOBAL_CLAUDE" ]] && grep -qF "$BEGIN_MARKER" "$GLOBAL_CLAUDE"; then
  tmp="$(mktemp)"
  awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
    $0 == begin { skip=1; next }
    $0 == end   { skip=0; next }
    !skip       { print }
  ' "$GLOBAL_CLAUDE" > "$tmp"
  mv "$tmp" "$GLOBAL_CLAUDE"
  print "✓ Removed kaggle-imports block from $GLOBAL_CLAUDE"
else
  print "  No managed block found in $GLOBAL_CLAUDE — skipping"
fi

if command -v claude &>/dev/null; then
  claude plugin uninstall kaggle 2>/dev/null || true
  print "✓ Plugin unregistered"
fi

print ""
print "==> kaggle uninstalled."
