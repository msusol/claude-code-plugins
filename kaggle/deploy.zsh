#!/usr/bin/env zsh
# kaggle plugin installer — idempotent, safe to re-run.
#
# What this does:
#   1. Copies src/rules/kaggle-*.md to ~/.cline/rules/ (installs new, updates changed)
#   2. Regenerates the kaggle-imports @-import block in ~/.claude/CLAUDE.md so Claude
#      Code also loads the same rules from ~/.cline/rules/
#   3. Registers this repo as a Claude Code plugin marketplace and installs kaggle
#
# Owns the kaggle-* prefix only; the clinerules plugin (planning-*) and any other
# plugin manage their own files and their own sentinel blocks independently.

set -euo pipefail

REPO_DIR="${0:A:h}"
RULES_SRC="$REPO_DIR/src/rules"
RULES_DEST="$HOME/.cline/rules"
GLOBAL_CLAUDE="$HOME/.claude/CLAUDE.md"
BEGIN_MARKER="<!-- BEGIN kaggle-imports (managed by deploy.zsh) -->"
END_MARKER="<!-- END kaggle-imports -->"

print "==> kaggle installer"
print ""

# ── 1. Install rule files to ~/.cline/rules/ ─────────────────────────────────
if [[ -d "$RULES_SRC" ]]; then
  mkdir -p "$RULES_DEST"
  installed=0; updated=0
  for src in "$RULES_SRC"/kaggle-*.md(N); do
    name="${src:t}"
    dest="$RULES_DEST/$name"
    if [[ ! -f "$dest" ]]; then
      cp "$src" "$dest"; (( installed++ )) || true
    elif ! diff -q "$src" "$dest" &>/dev/null; then
      cp "$src" "$dest"; (( updated++ )) || true
    fi
  done
  print "✓ Rules: $installed installed, $updated updated → $RULES_DEST"
else
  print "⚠ No src/rules/ found — skipping rule installation"
fi

# ── 2. Regenerate kaggle-imports block in ~/.claude/CLAUDE.md ─────────────────
files=("$RULES_SRC"/kaggle-*.md(N))
if (( ${#files[@]} > 0 )); then
  imports=""
  for f in "${files[@]}"; do
    name="${f:t}"
    [[ -n "$imports" ]] && imports+=$'\n'
    imports+="@~/.cline/rules/$name"
  done

  if [[ ! -f "$GLOBAL_CLAUDE" ]]; then
    mkdir -p "${GLOBAL_CLAUDE:h}"
    cat > "$GLOBAL_CLAUDE" <<EOF
# Global Rules

The following rules apply across all projects.

## Kaggle Rules

$BEGIN_MARKER
$imports
$END_MARKER
EOF
    print "✓ Created $GLOBAL_CLAUDE with kaggle-imports block"
  else
    body_file="$(mktemp)"; printf '%s\n' "$imports" > "$body_file"
    tmp="$(mktemp)"
    if grep -qF "$BEGIN_MARKER" "$GLOBAL_CLAUDE" && grep -qF "$END_MARKER" "$GLOBAL_CLAUDE"; then
      # Replace content between existing markers.
      awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" -v bf="$body_file" '
        BEGIN { while ((getline line < bf) > 0) body = (body == "" ? line : body "\n" line) }
        $0 == begin { print begin; print body; skip=1; next }
        $0 == end   { skip=0; print; next }
        !skip       { print }
      ' "$GLOBAL_CLAUDE" > "$tmp"
      mv "$tmp" "$GLOBAL_CLAUDE"
      print "✓ Updated $GLOBAL_CLAUDE (kaggle-imports block)"
    else
      # Append a fresh block at the end.
      {
        cat "$GLOBAL_CLAUDE"
        print ""
        print "## Kaggle Rules"
        print ""
        print "$BEGIN_MARKER"
        cat "$body_file"
        print "$END_MARKER"
      } > "$tmp"
      mv "$tmp" "$GLOBAL_CLAUDE"
      print "✓ Appended kaggle-imports block to $GLOBAL_CLAUDE"
    fi
    rm -f "$body_file"
  fi
else
  print "⚠ No kaggle-* rules found — skipping CLAUDE.md update"
fi

# ── 3. Claude Code plugin registration ───────────────────────────────────────
if command -v claude &>/dev/null; then
  claude plugin marketplace add "${REPO_DIR:h}" 2>/dev/null || true
  claude plugin install kaggle@msusol 2>/dev/null || true
  print "✓ Plugin registered with Claude Code"
else
  print "⚠ claude CLI not found — skipping plugin registration"
  print "  Run manually: claude plugin marketplace add ${REPO_DIR:h} && claude plugin install kaggle@msusol"
fi

print ""
print "==> kaggle installed."
print "    Rules   → $RULES_DEST (Cline, native)"
print "    Rules   → $GLOBAL_CLAUDE (Claude Code, via @-imports)"
print "    Skill   → kaggle-project-scaffold"
print "    Commands→ /kaggle:new, /kaggle:preflight"
