#!/usr/bin/env bash
# link-clinerules.sh — symlink ~/.clinerules/* into <project-root>/.clinerules/
# Also regenerates @-imports in ~/.claude/CLAUDE.md to match current files.
#
# Usage:
#   link-clinerules.sh [project-root]   default: current directory
#   link-clinerules.sh --force          overwrite existing symlinks

set -euo pipefail

FORCE=0
PROJECT_ROOT="$PWD"
GLOBAL_DIR="$HOME/.clinerules"

for arg in "$@"; do
  case "$arg" in
    --force|-f)  FORCE=1 ;;
    --source=*)  GLOBAL_DIR="$(cd "${arg#--source=}" && pwd)" ;;
    --source)    shift; GLOBAL_DIR="$(cd "$1" && pwd)" ;;
    *)           PROJECT_ROOT="$(cd "$arg" && pwd)" ;;
  esac
done
LOCAL_DIR="$PROJECT_ROOT/.clinerules"
GLOBAL_CLAUDE="$HOME/.claude/CLAUDE.md"

if [[ ! -d "$GLOBAL_DIR" ]]; then
  echo "error: $GLOBAL_DIR does not exist" >&2
  exit 1
fi

shopt -s nullglob
files=("$GLOBAL_DIR"/*)

if [[ ${#files[@]} -eq 0 ]]; then
  echo "no files found in $GLOBAL_DIR — nothing to link"
  exit 0
fi

# ── 1. Symlink into project .clinerules/ ──────────────────────────────────────
mkdir -p "$LOCAL_DIR"

for src in "${files[@]}"; do
  [[ -f "$src" ]] || continue
  name="$(basename "$src")"
  dest="$LOCAL_DIR/$name"

  if [[ -L "$dest" ]]; then
    if [[ $FORCE -eq 1 ]]; then
      ln -sf "$src" "$dest"
      echo "updated  $dest"
    else
      echo "skipped  $dest (already linked; use --force to overwrite)"
    fi
  elif [[ -e "$dest" ]]; then
    echo "skipped  $dest (real file exists; remove manually to replace)"
  else
    ln -s "$src" "$dest"
    echo "linked   $dest"
  fi
done

# ── 2. Update @-imports block in ~/.claude/CLAUDE.md ─────────────────────────
# The block is delimited by sentinel markers so user edits outside it are preserved.
BEGIN_MARKER="<!-- BEGIN clinerules-imports (managed by link-clinerules.sh) -->"
END_MARKER="<!-- END clinerules-imports -->"

# Build imports body (no trailing newline).
imports=""
for src in "${files[@]}"; do
  [[ -f "$src" ]] || continue
  [[ -n "$imports" ]] && imports+=$'\n'
  imports+="@~/.clinerules/$(basename "$src")"
done

if [[ ! -f "$GLOBAL_CLAUDE" ]]; then
  # First-time creation.
  cat > "$GLOBAL_CLAUDE" <<EOF
# Global Rules

The following rules apply across all projects.

## Cline Project Rules

$BEGIN_MARKER
$imports
$END_MARKER
EOF
  echo "created  $GLOBAL_CLAUDE"
else
  # Pass imports via a temp file (BSD awk on macOS rejects multi-line -v strings).
  body_file="$(mktemp)"
  printf '%s\n' "$imports" > "$body_file"
  tmp="$(mktemp)"

  if grep -qF "$BEGIN_MARKER" "$GLOBAL_CLAUDE" && grep -qF "$END_MARKER" "$GLOBAL_CLAUDE"; then
    # Replace only the managed block; preserve everything else.
    awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" -v bf="$body_file" '
      BEGIN { while ((getline line < bf) > 0) body = (body == "" ? line : body "\n" line) }
      $0 == begin { print; print body; skip=1; next }
      $0 == end   { skip=0; print; next }
      !skip       { print }
    ' "$GLOBAL_CLAUDE" > "$tmp"
    mv "$tmp" "$GLOBAL_CLAUDE"
    echo "updated  $GLOBAL_CLAUDE (managed block)"
  else
    # One-time migration: wrap existing contiguous @~/.clinerules/*.md block with
    # sentinels, then replace its body. If no such block exists, append one.
    # Add a `## Cline Project Rules` header above the block unless one already exists.
    if grep -qF "## Cline Project Rules" "$GLOBAL_CLAUDE"; then
      header_line=""
    else
      header_line="## Cline Project Rules"
    fi
    awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" -v bf="$body_file" -v header="$header_line" '
      BEGIN { while ((getline line < bf) > 0) body = (body == "" ? line : body "\n" line) }
      /^@~\/\.clinerules\// && !seen {
        if (header != "") { print header; print "" }
        print begin; print body; print end
        seen=1; in_block=1; next
      }
      /^@~\/\.clinerules\// && in_block { next }
      { in_block=0; print }
      END {
        if (!seen) {
          print ""
          if (header != "") { print header; print "" }
          print begin; print body; print end
        }
      }
    ' "$GLOBAL_CLAUDE" > "$tmp"
    mv "$tmp" "$GLOBAL_CLAUDE"
    echo "migrated $GLOBAL_CLAUDE (wrapped imports with sentinels)"
  fi

  rm -f "$body_file"
fi