#!/usr/bin/env zsh
# kaggle plugin installer — idempotent, safe to re-run.
#
# Usage: ./deploy.zsh [target-root]
#   target-root defaults to $PWD. Point it at your Kaggle workspace root (the
#   parent directory that holds many competition subdirectories) so a single
#   deploy covers every competition beneath it — not at an individual
#   competition directory.
#
# What this does:
#   1. Copies src/rules/kaggle-*.md to <target-root>/.cline/rules/ (installs new, updates changed)
#   2. Regenerates the kaggle-imports @-import block in <target-root>/CLAUDE.md so
#      Claude Code also loads the same rules from <target-root>/.cline/rules/
#   3. Installs the kaggle-guard PreToolUse hook to ~/.claude/scripts/ and registers
#      it in ~/.claude/settings.json (global — cheap, project-agnostic guard logic
#      that already scopes itself by matching Bash command content)
#   4. Registers this repo as a Claude Code plugin marketplace and installs kaggle
#
# Owns the kaggle-* prefix only; the docs plugin (planning-*) and any other
# plugin manage their own files and their own sentinel blocks independently.

set -euo pipefail

REPO_DIR="${0:A:h}"
RULES_SRC="$REPO_DIR/src/rules"
TARGET_ROOT="${1:-$PWD}"

if [[ ! -d "$TARGET_ROOT" ]]; then
  print "error: target root does not exist: $TARGET_ROOT" >&2
  exit 1
fi
TARGET_ROOT="${TARGET_ROOT:A}"

RULES_DEST="$TARGET_ROOT/.cline/rules"
TARGET_CLAUDE="$TARGET_ROOT/CLAUDE.md"
BEGIN_MARKER="<!-- BEGIN kaggle-imports (managed by deploy.zsh) -->"
END_MARKER="<!-- END kaggle-imports -->"

print "==> kaggle installer"
print "    Target root: $TARGET_ROOT"
print ""

# ── 1. Install rule files to <target-root>/.cline/rules/ ─────────────────────
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

# ── 2. Regenerate kaggle-imports block in <target-root>/CLAUDE.md ────────────
files=("$RULES_SRC"/kaggle-*.md(N))
if (( ${#files[@]} > 0 )); then
  imports=""
  for f in "${files[@]}"; do
    name="${f:t}"
    [[ -n "$imports" ]] && imports+=$'\n'
    imports+="@.cline/rules/$name"
  done

  if [[ ! -f "$TARGET_CLAUDE" ]]; then
    mkdir -p "${TARGET_CLAUDE:h}"
    cat > "$TARGET_CLAUDE" <<EOF
# Kaggle Workspace Rules

The following rules apply to every competition under this workspace.

## Kaggle Rules

$BEGIN_MARKER
$imports
$END_MARKER
EOF
    print "✓ Created $TARGET_CLAUDE with kaggle-imports block"
  else
    body_file="$(mktemp)"; printf '%s\n' "$imports" > "$body_file"
    tmp="$(mktemp)"
    if grep -qF "$BEGIN_MARKER" "$TARGET_CLAUDE" && grep -qF "$END_MARKER" "$TARGET_CLAUDE"; then
      # Replace content between existing markers.
      awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" -v bf="$body_file" '
        BEGIN { while ((getline line < bf) > 0) body = (body == "" ? line : body "\n" line) }
        $0 == begin { print begin; print body; skip=1; next }
        $0 == end   { skip=0; print; next }
        !skip       { print }
      ' "$TARGET_CLAUDE" > "$tmp"
      mv "$tmp" "$TARGET_CLAUDE"
      print "✓ Updated $TARGET_CLAUDE (kaggle-imports block)"
    else
      # Append a fresh block at the end.
      {
        cat "$TARGET_CLAUDE"
        print ""
        print "## Kaggle Rules"
        print ""
        print "$BEGIN_MARKER"
        cat "$body_file"
        print "$END_MARKER"
      } > "$tmp"
      mv "$tmp" "$TARGET_CLAUDE"
      print "✓ Appended kaggle-imports block to $TARGET_CLAUDE"
    fi
    rm -f "$body_file"
  fi
else
  print "⚠ No kaggle-* rules found — skipping CLAUDE.md update"
fi

# ── 3. Install kaggle-guard PreToolUse hook (global) ─────────────────────────
HOOK_SRC="$REPO_DIR/src/kaggle-guard-hook.zsh"
HOOK_DEST="$HOME/.claude/scripts/kaggle-guard-hook.zsh"
if [[ -f "$HOOK_SRC" ]]; then
  mkdir -p "$HOME/.claude/scripts"
  cp "$HOOK_SRC" "$HOOK_DEST"
  chmod +x "$HOOK_DEST"
  print "✓ Installed hook: $HOOK_DEST"
  python3 "$REPO_DIR/scripts/manage-settings.py" install
else
  print "⚠ Hook source not found — skipping: $HOOK_SRC"
fi

# ── 4. Claude Code plugin registration ───────────────────────────────────────
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
print "    Rules   → $TARGET_CLAUDE (Claude Code, via @-imports)"
print "    Hook    → $HOOK_DEST (blocks Claude from pushing notebooks, global)"
print "    Skill   → kaggle-project-scaffold"
print "    Commands→ /kaggle:new, /kaggle:preflight"
