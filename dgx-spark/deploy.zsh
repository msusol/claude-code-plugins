#!/usr/bin/env zsh
# dgx-spark installer — idempotent, safe to re-run.
#
# What this does:
#   1. Copies src/rules/dgx-spark-*.md to ~/.claude/rules/ (installs new, updates changed)
#   2. Regenerates the dgx-spark-imports @-import block in ~/.claude/CLAUDE.md so
#      Claude Code loads these host-specific rules in every session, on this machine
#   3. Registers this repo as a Claude Code plugin marketplace and installs dgx-spark
#
# Global, not workspace-scoped: these rules describe spark-db62 itself (Docker
# contexts, AppArmor confinement, host-level gotchas) — they apply no matter which
# project you're working in on this host, so they live in ~/.claude/CLAUDE.md next
# to the docs plugin's planning-* block, not duplicated per project.
#
# Owns the dgx-spark-* prefix only; the docs plugin (planning-*), git-guard
# (git-branch-naming.md), and any other plugin manage their own files and their
# own sentinel blocks independently.

set -euo pipefail

REPO_DIR="${0:A:h}"
RULES_SRC="$REPO_DIR/src/rules"
RULES_DEST="$HOME/.claude/rules"
GLOBAL_CLAUDE="$HOME/.claude/CLAUDE.md"
BEGIN_MARKER="<!-- BEGIN dgx-spark-imports (managed by deploy.zsh) -->"
END_MARKER="<!-- END dgx-spark-imports -->"

print "==> dgx-spark installer"
print ""

# ── 1. Install rule files to ~/.claude/rules/ ─────────────────────────────────
if [[ -d "$RULES_SRC" ]]; then
  mkdir -p "$RULES_DEST"
  installed=0; updated=0
  for src in "$RULES_SRC"/dgx-spark-*.md(N); do
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
files=("$RULES_SRC"/dgx-spark-*.md(N))
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
      /<!-- BEGIN dgx-spark-imports/ { print begin; print body; skip=1; next }
      /<!-- END dgx-spark-imports -->/ { skip=0; print end; next }
      !skip { print }
    ' "$GLOBAL_CLAUDE" > "$tmp"
    mv "$tmp" "$GLOBAL_CLAUDE"
    rm -f "$body_file"
    print "✓ Updated $GLOBAL_CLAUDE (@-import block)"
  else
    printf '\n%s\n%s\n%s\n' "$BEGIN_MARKER" "$imports" "$END_MARKER" >> "$GLOBAL_CLAUDE"
    print "✓ Appended dgx-spark @-import block to $GLOBAL_CLAUDE"
  fi
else
  print "⚠ No rules found in $RULES_SRC — skipping CLAUDE.md update"
fi

# ── 3. Claude Code plugin registration ───────────────────────────────────────
if command -v claude &>/dev/null; then
  claude plugin marketplace add "${REPO_DIR:h}" 2>/dev/null || true
  claude plugin install dgx-spark@losus-ai 2>/dev/null || true
  print "✓ Plugin registered with Claude Code"
else
  print "⚠ claude CLI not found — skipping plugin registration"
  print "  Run manually: claude plugin marketplace add ${REPO_DIR:h} && claude plugin install dgx-spark@losus-ai"
fi

print ""
print "==> dgx-spark installed."
print "    Rules → $RULES_DEST"
print "    Rules → $GLOBAL_CLAUDE (via @-imports)"
