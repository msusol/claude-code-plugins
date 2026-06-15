#!/usr/bin/env zsh
# clinerules installer — idempotent, safe to re-run.
#
# What this does:
#   1. Copies link-clinerules.sh to ~/.claude/scripts/link-clinerules.sh
#   2. Copies src/rules/clinerules-*.md to ~/.clinerules/ (installs new, updates changed,
#      removes legacy ##-prefixed files)
#   3. Registers this repo as a Claude Code plugin marketplace and installs clinerules
#
# Prerequisites:
#   - Claude Code CLI (claude) installed

set -euo pipefail

REPO_DIR="${0:A:h}"
SCRIPT_SRC="$REPO_DIR/src/link-clinerules.sh"
SCRIPT_DEST="$HOME/.claude/scripts/link-clinerules.sh"
RULES_SRC="$REPO_DIR/src/rules"
RULES_DEST="$HOME/.clinerules"

print "==> clinerules installer"
print ""

# 1. Install link-clinerules.sh globally
mkdir -p "$HOME/.claude/scripts"
cp "$SCRIPT_SRC" "$SCRIPT_DEST"
chmod +x "$SCRIPT_DEST"
print "✓ Installed script: $SCRIPT_DEST"

# 2. Install rule files to ~/.clinerules/
if [[ -d "$RULES_SRC" ]]; then
  mkdir -p "$RULES_DEST"
  installed=0; updated=0
  for src in "$RULES_SRC"/*.md(N); do
    name="${src:t}"
    dest="$RULES_DEST/$name"
    if [[ ! -f "$dest" ]]; then
      cp "$src" "$dest"
      (( installed++ )) || true
    elif ! diff -q "$src" "$dest" &>/dev/null; then
      cp "$src" "$dest"
      (( updated++ )) || true
    fi
  done
  print "✓ Rules: $installed installed, $updated updated → $RULES_DEST"

  # Remove legacy ##-prefixed files that have been renamed to plugin-namespaced ones.
  removed=0
  for legacy in "$RULES_DEST"/[0-9][0-9]-*.md(N); do
    name="${legacy:t}"
    rm "$legacy"
    print "✓ Removed legacy rule: $name"
    (( removed++ )) || true
  done
  if (( removed > 0 )); then
    print "✓ Removed $removed legacy ##-prefixed rules"
  fi
else
  print "⚠ No src/rules/ found — skipping rule installation"
  print "  Run ./collect.zsh to populate src/rules/ from ~/.clinerules/"
fi

# 3. Claude Code plugin registration
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
