#!/usr/bin/env zsh
# clinerules uninstaller

set -euo pipefail

REPO_DIR="${0:A:h}"
RULES_SRC="$REPO_DIR/src/rules"
RULES_DEST="$HOME/.cline/rules"

print "==> clinerules uninstaller"
print ""

# Remove rule files deployed by this plugin from ~/.cline/rules/
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
if [[ -f "$GLOBAL_CLAUDE" ]] && grep -qE "<!-- BEGIN clinerules-imports" "$GLOBAL_CLAUDE"; then
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
    /<!-- BEGIN clinerules-imports/ { hdr = ""; buf = ""; skip = 1; next }
    /<!-- END clinerules-imports -->/ { skip = 0; next }
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
  print "✓ Removed @-import block from $GLOBAL_CLAUDE"
else
  print "  No managed block found in $GLOBAL_CLAUDE — skipping"
fi

if command -v claude &>/dev/null; then
  claude plugin uninstall clinerules 2>/dev/null || true
  print "✓ Plugin unregistered"
fi

print ""
print "==> clinerules uninstalled."