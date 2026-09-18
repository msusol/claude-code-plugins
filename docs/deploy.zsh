#!/usr/bin/env zsh
# docs installer — idempotent, safe to re-run.
#
# What this does:
#   1. Copies src/rules/*.md to ~/.claude/rules/ (installs new, updates changed)
#   2. Regenerates the @-import block in ~/.claude/CLAUDE.md so Claude Code
#      loads those same rules in every session, in every project
#   3. Registers this repo as a Claude Code plugin marketplace and installs docs
#
# Prerequisites:
#   - Claude Code CLI (claude) installed
#
# Claude Code-native only — this plugin does not support Cline. Rules live in
# ~/.claude/rules/ (Claude Code's own rules directory) and are pulled into every
# session via @-imports in ~/.claude/CLAUDE.md.

set -euo pipefail

REPO_DIR="${0:A:h}"
RULES_SRC="$REPO_DIR/src/rules"
RULES_DEST="$HOME/.claude/rules"
GLOBAL_CLAUDE="$HOME/.claude/CLAUDE.md"
BEGIN_MARKER="<!-- BEGIN docs-imports (managed by deploy.zsh) -->"
END_MARKER="<!-- END docs-imports -->"

print "==> docs installer"
print ""

# ── 1. Install rule files to ~/.claude/rules/ ─────────────────────────────────
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
else
  print "⚠ No src/rules/ found — skipping rule installation"
  print "  Run ./collect.zsh to populate src/rules/ from ~/.claude/rules/"
fi

# ── 2. Regenerate @-import block in ~/.claude/CLAUDE.md ──────────────────────
# Builds @-imports for files owned by this plugin only (src/rules/).
# Other plugins in this repo (e.g. git-guard) manage their own sentinel block
# independently — see git-guard/deploy.zsh's git-guard-imports block.
files=("$RULES_SRC"/*.md(N))
if (( ${#files[@]} > 0 )); then
  imports=""
  for f in "${files[@]}"; do
    name="${f:t}"
    [[ -n "$imports" ]] && imports+=$'\n'
    imports+="@~/.claude/rules/$name"
  done

  if [[ ! -f "$GLOBAL_CLAUDE" ]]; then
    mkdir -p "${GLOBAL_CLAUDE:h}"
    cat > "$GLOBAL_CLAUDE" <<EOF
# Global Rules

The following rules apply across all projects.

$BEGIN_MARKER
$imports
$END_MARKER
EOF
    print "✓ Created $GLOBAL_CLAUDE with @-import block"
  elif grep -qF "$BEGIN_MARKER" "$GLOBAL_CLAUDE"; then
    body_file="$(mktemp)"
    printf '%s\n' "$imports" > "$body_file"
    tmp="$(mktemp)"
    awk \
      -v begin="$BEGIN_MARKER" \
      -v end="$END_MARKER" \
      -v bf="$body_file" '
      BEGIN { while ((getline line < bf) > 0) body = (body == "" ? line : body "\n" line) }
      /<!-- BEGIN docs-imports/ { print begin; print body; skip=1; next }
      /<!-- END docs-imports -->/ { skip=0; print end; next }
      !skip { print }
    ' "$GLOBAL_CLAUDE" > "$tmp"
    mv "$tmp" "$GLOBAL_CLAUDE"
    rm -f "$body_file"
    print "✓ Updated $GLOBAL_CLAUDE (@-import block)"
  else
    printf '\n%s\n%s\n%s\n' "$BEGIN_MARKER" "$imports" "$END_MARKER" >> "$GLOBAL_CLAUDE"
    print "✓ Appended docs @-import block to $GLOBAL_CLAUDE"
  fi
else
  print "⚠ No rules found in $RULES_SRC — skipping CLAUDE.md update"
fi

# ── 3. Claude Code plugin registration ───────────────────────────────────────
if command -v claude &>/dev/null; then
  claude plugin marketplace add "${REPO_DIR:h}" 2>/dev/null || true
  claude plugin install docs@losus-ai 2>/dev/null || true
  print "✓ Plugin registered with Claude Code"
else
  print "⚠ claude CLI not found — skipping plugin registration"
  print "  Run manually: claude plugin marketplace add ${REPO_DIR:h} && claude plugin install docs@losus-ai"
fi

print ""
print "==> docs installed."
print "    Rules → $RULES_DEST"
print "    Rules → $GLOBAL_CLAUDE (via @-imports)"
