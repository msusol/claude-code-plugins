#!/usr/bin/env zsh
# collect.zsh — copy ~/.cline/rules/*.md into src/rules/ so changes can be committed.
#
# Usage:
#   ./collect.zsh          copy from ~/.cline/rules/ (default)
#   ./collect.zsh --dry-run  show what would change without writing

set -euo pipefail

REPO_DIR="${0:A:h}"
SRC_DIR="$HOME/.cline/rules"
DEST_DIR="$REPO_DIR/src/rules"
IGNORE_FILE="$REPO_DIR/.collectignore"
DRY_RUN=0

for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRY_RUN=1 ;;
    *) print "unknown argument: $arg" >&2; exit 1 ;;
  esac
done

if [[ ! -d "$SRC_DIR" ]]; then
  print "error: $SRC_DIR does not exist" >&2
  print "  Run ./deploy.zsh first to create it, or run: mkdir -p $SRC_DIR" >&2
  exit 1
fi

# Guard: warn if source is empty to prevent overwriting src/rules/ with nothing.
if [[ -z "$(ls "$SRC_DIR"/*.md(N) 2>/dev/null)" ]]; then
  print "error: $SRC_DIR contains no .md files — aborting to avoid wiping src/rules/" >&2
  exit 1
fi

[[ $DRY_RUN -eq 1 ]] && print "(dry run — no files written)"

# Build exclusion set from .collectignore (comments and blank lines ignored)
typeset -A ignored
if [[ -f "$IGNORE_FILE" ]]; then
  while IFS= read -r line; do
    line="${line%%#*}"   # strip inline comments
    line="${line// /}"   # strip spaces
    [[ -n "$line" ]] && ignored[$line]=1
  done < "$IGNORE_FILE"
fi

mkdir -p "$DEST_DIR"

added=0; updated=0; unchanged=0; removed=0; skipped=0

# Copy new and changed files from ~/.cline/rules/ → src/rules/
for src in "$SRC_DIR"/*.md(N); do
  name="${src:t}"
  if [[ -n "${ignored[$name]:-}" ]]; then
    print "ignored  $name  (.collectignore)"
    (( skipped++ )) || true
    continue
  fi
  dest="$DEST_DIR/$name"
  if [[ ! -f "$dest" ]]; then
    print "added    $name"
    (( added++ )) || true
    if [[ $DRY_RUN -eq 0 ]]; then cp "$src" "$dest"; fi
  elif ! diff -q "$src" "$dest" &>/dev/null; then
    print "updated  $name"
    (( updated++ )) || true
    if [[ $DRY_RUN -eq 0 ]]; then cp "$src" "$dest"; fi
  else
    print "unchanged $name"
    (( unchanged++ )) || true
  fi
done

# Flag files in src/rules/ that no longer exist in ~/.cline/rules/
for dest in "$DEST_DIR"/*.md(N); do
  name="${dest:t}"
  if [[ ! -f "$SRC_DIR/$name" ]]; then
    print "removed? $name  (in repo but not in ~/.cline/rules/ — delete manually if intentional)"
    (( removed++ )) || true
  fi
done

print ""
print "$added added, $updated updated, $unchanged unchanged${skipped:+, $skipped ignored}${removed:+, $removed stale}"
if [[ $DRY_RUN -eq 0 ]]; then print "Files written to $DEST_DIR"; fi
