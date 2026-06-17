#!/usr/bin/env zsh
# clinerules installer — idempotent, safe to re-run.
#
# What this does:
#   1. Copies src/rules/*.md to ~/.cline/rules/ (installs new, updates changed,
#      removes legacy ##-prefixed files)
#   2. Regenerates the @-import block in ~/.claude/CLAUDE.md so Claude Code
#      also loads the same rules from ~/.cline/rules/
#   3. Registers this repo as a Claude Code plugin marketplace and installs clinerules
#
# Prerequisites:
#   - Claude Code CLI (claude) installed
#
# Single-source strategy: rules live in ~/.cline/rules/ and are consumed by
# both Cline (natively) and Claude Code (via @-imports in ~/.claude/CLAUDE.md).

set -euo pipefail

REPO_DIR="${0:A:h}"
RULES_SRC="$REPO_DIR/src/rules"
RULES_DEST="$HOME/.cline/rules"
GLOBAL_CLAUDE="$HOME/.claude/CLAUDE.md"
BEGIN_MARKER="<!-- BEGIN clinerules-imports (managed by deploy.zsh) -->"
END_MARKER="<!-- END clinerules-imports -->"

print "==> clinerules installer"
print ""

# ── 1. Install rule files to ~/.cline/rules/ ─────────────────────────────────
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

  # Remove legacy files: ##-prefixed names and old clinerules-* prefix.
  removed=0
  for legacy in "$RULES_DEST"/[0-9][0-9]-*.md(N) "$RULES_DEST"/clinerules-*.md(N); do
    name="${legacy:t}"
    rm "$legacy"
    print "✓ Removed legacy rule: $name"
    (( removed++ )) || true
  done
  (( removed > 0 )) && print "✓ Removed $removed legacy rules"
else
  print "⚠ No src/rules/ found — skipping rule installation"
  print "  Run ./collect.zsh to populate src/rules/ from ~/.cline/rules/"
fi

# ── 2. Regenerate @-import block in ~/.claude/CLAUDE.md ──────────────────────
# Builds @-imports for files owned by this plugin only (src/rules/).
# Other plugins manage their own sentinel blocks independently.
files=("$RULES_SRC"/*.md(N))
if (( ${#files[@]} > 0 )); then
  imports=""
  for f in "${files[@]}"; do
    name="${f:t}"
    [[ -n "$imports" ]] && imports+=$'\n'
    imports+="@~/.cline/rules/$name"
  done

  if [[ ! -f "$GLOBAL_CLAUDE" ]]; then
    # First-time creation.
    mkdir -p "${GLOBAL_CLAUDE:h}"
    cat > "$GLOBAL_CLAUDE" <<EOF
# Global Rules

The following rules apply across all projects.

## Cline Project Rules

$BEGIN_MARKER
$imports
$END_MARKER
EOF
    print "✓ Created $GLOBAL_CLAUDE with @-import block"
  else
    body_file="$(mktemp)"
    printf '%s\n' "$imports" > "$body_file"
    tmp="$(mktemp)"

    if grep -qE "<!-- BEGIN clinerules-imports" "$GLOBAL_CLAUDE" && grep -qF "$END_MARKER" "$GLOBAL_CLAUDE"; then
      # Sentinels present (any variant — old "link-clinerules.sh" or current "deploy.zsh").
      # Replace everything between the markers and rewrite the begin marker to the current form.
      awk \
        -v begin="$BEGIN_MARKER" \
        -v end="$END_MARKER" \
        -v bf="$body_file" '
        BEGIN { while ((getline line < bf) > 0) body = (body == "" ? line : body "\n" line) }
        /<!-- BEGIN clinerules-imports/ { print begin; print body; skip=1; next }
        $0 == end   { skip=0; print; next }
        !skip       { print }
      ' "$GLOBAL_CLAUDE" > "$tmp"
      mv "$tmp" "$GLOBAL_CLAUDE"
      print "✓ Updated $GLOBAL_CLAUDE (@-import block)"
    else
      # No sentinels found: wrap any existing bare @~/.clinerules/ or @~/.cline/rules/
      # lines with sentinels and replace their content. If none found, append the block.
      if grep -qE "## Cline Project Rules" "$GLOBAL_CLAUDE"; then
        header_line=""
      else
        header_line="## Cline Project Rules"
      fi
      awk \
        -v begin="$BEGIN_MARKER" \
        -v end="$END_MARKER" \
        -v bf="$body_file" \
        -v header="$header_line" '
        BEGIN { while ((getline line < bf) > 0) body = (body == "" ? line : body "\n" line) }
        /^@~\/(\.clinerules|\.cline\/rules)\// && !seen {
          if (header != "") { print header; print "" }
          print begin; print body; print end
          seen=1; in_block=1; next
        }
        /^@~\/(\.clinerules|\.cline\/rules)\// && in_block { next }
        { in_block=0; last_blank = ($0 == ""); print }
        END {
          if (!seen) {
            if (!last_blank) print ""
            if (header != "") { print header; print "" }
            print begin; print body; print end
          }
        }
      ' "$GLOBAL_CLAUDE" > "$tmp"
      mv "$tmp" "$GLOBAL_CLAUDE"
      print "✓ Migrated $GLOBAL_CLAUDE (wrapped @-imports with sentinels)"
    fi

    rm -f "$body_file"
  fi
else
  print "⚠ No rules found in $RULES_DEST — skipping CLAUDE.md update"
fi

# ── 3. Claude Code plugin registration ───────────────────────────────────────
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
print "    Rules → $RULES_DEST (Cline, native)"
print "    Rules → $GLOBAL_CLAUDE (Claude Code, via @-imports)"
print "    Use /install-clinerules to re-deploy at any time."
