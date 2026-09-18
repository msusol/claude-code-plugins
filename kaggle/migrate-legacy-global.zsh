#!/usr/bin/env zsh
# migrate-legacy-global.zsh — one-time cleanup for a kaggle install predating
# workspace-scoping.
#
# Before the workspace-scoped rewrite, deploy.zsh wrote kaggle-*.md rules to the
# GLOBAL ~/.claude/rules/ and a kaggle-imports block to the GLOBAL ~/.claude/CLAUDE.md
# (same pattern the docs plugin still uses today). That global install is not
# automatically retired by switching to the new workspace-scoped deploy.zsh — the two
# live at different paths, so running the new uninstall.zsh against $HOME does not
# find the old ~/.claude/CLAUDE.md block (the new script looks for <target-root>/CLAUDE.md
# directly, not nested under .claude/).
#
# This script removes ONLY that legacy global footprint:
#   1. kaggle-*.md files in ~/.claude/rules/ (matching this plugin's src/rules/ names)
#   2. the kaggle-imports sentinel block in ~/.claude/CLAUDE.md
#
# It does NOT touch the kaggle-guard hook or its ~/.claude/settings.json registration —
# those are still global by design (see README "Why") and are unaffected by workspace
# scoping either way.
#
# Usage:
#   ./migrate-legacy-global.zsh            remove the legacy global footprint
#   ./migrate-legacy-global.zsh --dry-run   show what would be removed, without writing
#
# Safe to run even if there is no legacy global install — it just reports nothing found.
# Run this once, then (if you haven't already) deploy fresh to your actual workspace root:
#   ./deploy.zsh <workspace-root>

set -euo pipefail

REPO_DIR="${0:A:h}"
RULES_SRC="$REPO_DIR/src/rules"
RULES_DEST="$HOME/.claude/rules"
GLOBAL_CLAUDE="$HOME/.claude/CLAUDE.md"
BEGIN_MARKER="<!-- BEGIN kaggle-imports (managed by deploy.zsh) -->"
END_MARKER="<!-- END kaggle-imports -->"
DRY_RUN=0

for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRY_RUN=1 ;;
    *) print "unknown argument: $arg" >&2; exit 1 ;;
  esac
done

print "==> kaggle legacy-global migration"
[[ $DRY_RUN -eq 1 ]] && print "(dry run — no files written)"
print ""

# ── 1. Remove kaggle-*.md rule files from the global ~/.claude/rules/ ─────────
if [[ -d "$RULES_DEST" && -d "$RULES_SRC" ]]; then
  removed=0
  for src in "$RULES_SRC"/kaggle-*.md(N); do
    name="${src:t}"; dest="$RULES_DEST/$name"
    if [[ -f "$dest" ]]; then
      if [[ $DRY_RUN -eq 1 ]]; then
        print "would remove: $dest"
      else
        rm "$dest"
        print "✓ Removed: $dest"
      fi
      (( removed++ )) || true
    fi
  done
  if (( removed == 0 )); then
    print "  No legacy global kaggle rules found in $RULES_DEST — nothing to do"
  elif [[ $DRY_RUN -eq 1 ]]; then
    print "✓ Would remove $removed legacy rule(s) from $RULES_DEST"
  else
    print "✓ Removed $removed legacy rule(s) from $RULES_DEST"
  fi
else
  print "  $RULES_DEST not found — skipping"
fi

# ── 2. Strip the kaggle-imports block from the global ~/.claude/CLAUDE.md ────
if [[ -f "$GLOBAL_CLAUDE" ]] && grep -qF "$BEGIN_MARKER" "$GLOBAL_CLAUDE"; then
  if [[ $DRY_RUN -eq 1 ]]; then
    print "would remove kaggle-imports block from $GLOBAL_CLAUDE"
  else
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
    ' "$GLOBAL_CLAUDE" > "$tmp"
    mv "$tmp" "$GLOBAL_CLAUDE"
    print "✓ Removed kaggle-imports block from $GLOBAL_CLAUDE"
  fi
else
  print "  No legacy kaggle-imports block found in $GLOBAL_CLAUDE — nothing to do"
fi

print ""
print "==> kaggle legacy-global migration complete."
print "    The kaggle-guard hook and its ~/.claude/settings.json registration are"
print "    untouched — they stay global by design."
print "    Next: deploy to your real workspace root if you haven't already:"
print "      ./deploy.zsh <workspace-root>"
