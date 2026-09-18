#!/usr/bin/env zsh
# kaggle plugin uninstaller
#
# Usage: ./uninstall.zsh [target-root]
#   target-root defaults to $PWD — pass the same workspace root that was used
#   with ./deploy.zsh.

set -euo pipefail

REPO_DIR="${0:A:h}"
RULES_SRC="$REPO_DIR/src/rules"
TARGET_ROOT="${1:-$PWD}"

if [[ ! -d "$TARGET_ROOT" ]]; then
  print "error: target root does not exist: $TARGET_ROOT" >&2
  exit 1
fi
TARGET_ROOT="${TARGET_ROOT:A}"

RULES_DEST="$TARGET_ROOT/.claude/rules"
TARGET_CLAUDE="$TARGET_ROOT/CLAUDE.md"
BEGIN_MARKER="<!-- BEGIN kaggle-imports (managed by deploy.zsh) -->"
END_MARKER="<!-- END kaggle-imports -->"

print "==> kaggle uninstaller"
print "    Target root: $TARGET_ROOT"
print ""

# Remove kaggle-* rules from <target-root>/.claude/rules/
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

# Remove the managed kaggle-imports block from <target-root>/CLAUDE.md
if [[ -f "$TARGET_CLAUDE" ]] && grep -qF "$BEGIN_MARKER" "$TARGET_CLAUDE"; then
  tmp="$(mktemp)"
  awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
    /^## / {
      if (hdr != "") { printf "%s%s", buf, hdr; buf = ""; hdr = "" }
      hdr = buf $0 "\n"; buf = ""; next
    }
    /^[[:space:]]*$/ {
      if (hdr != "") { hdr = hdr "\n"; next }
      buf = buf "\n"; next
    }
    $0 == begin { hdr = ""; buf = ""; skip = 1; next }
    $0 == end   { skip = 0; next }
    skip        { next }
    {
      printf "%s%s", hdr, buf
      hdr = ""; buf = ""
      print
    }
    END {
      if (hdr != "") printf "%s", hdr
      printf "%s", buf
    }
  ' "$TARGET_CLAUDE" > "$tmp"
  mv "$tmp" "$TARGET_CLAUDE"
  print "✓ Removed kaggle-imports block from $TARGET_CLAUDE"
else
  print "  No managed block found in $TARGET_CLAUDE — skipping"
fi

# Remove kaggle-guard hook and deregister from settings.json (global)
HOOK_DEST="$HOME/.claude/scripts/kaggle-guard-hook.zsh"
if [[ -f "$HOOK_DEST" ]]; then
  rm "$HOOK_DEST"
  print "✓ Removed hook: $HOOK_DEST"
else
  print "  Hook not found — skipping: $HOOK_DEST"
fi
python3 "$REPO_DIR/scripts/manage-settings.py" uninstall

if command -v claude &>/dev/null; then
  claude plugin uninstall kaggle 2>/dev/null || true
  print "✓ Plugin unregistered"
fi

print ""
print "==> kaggle uninstalled."
