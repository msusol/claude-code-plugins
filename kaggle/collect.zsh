#!/usr/bin/env zsh
# collect.zsh — sync kaggle-*.md files from ~/.cline/rules/ back into src/rules/.
#
# Only collects this plugin's own prefix (kaggle-*), so foreign files from other
# plugins are never touched.
#
# Usage:
#   ./collect.zsh            copy from ~/.cline/rules/ (default)
#   ./collect.zsh --dry-run  show what would change without writing

set -euo pipefail

REPO_DIR="${0:A:h}"
SRC_DIR="$HOME/.cline/rules"
DEST_DIR="$REPO_DIR/src/rules"
DRY_RUN=0

for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRY_RUN=1 ;;
    *) print "unknown argument: $arg" >&2; exit 1 ;;
  esac
done

if [[ ! -d "$SRC_DIR" ]]; then
  print "error: $SRC_DIR does not exist — run ./deploy.zsh first" >&2
  exit 1
fi
if [[ -z "$(ls "$SRC_DIR"/kaggle-*.md(N) 2>/dev/null)" ]]; then
  print "error: no kaggle-*.md files found in $SRC_DIR — run ./deploy.zsh first" >&2
  exit 1
fi

[[ $DRY_RUN -eq 1 ]] && print "(dry run — no files written)"
mkdir -p "$DEST_DIR"
added=0; updated=0; unchanged=0; removed=0

for src in "$SRC_DIR"/kaggle-*.md(N); do
  name="${src:t}"; dest="$DEST_DIR/$name"
  if [[ ! -f "$dest" ]]; then
    print "added    $name"; (( added++ )) || true
    [[ $DRY_RUN -eq 0 ]] && cp "$src" "$dest"
  elif ! diff -q "$src" "$dest" &>/dev/null; then
    print "updated  $name"; (( updated++ )) || true
    [[ $DRY_RUN -eq 0 ]] && cp "$src" "$dest"
  else
    print "unchanged $name"; (( unchanged++ )) || true
  fi
done

for dest in "$DEST_DIR"/kaggle-*.md(N); do
  name="${dest:t}"
  if [[ ! -f "$SRC_DIR/$name" ]]; then
    print "removed? $name  (in repo but not in ~/.cline/rules/ — delete manually if intentional)"
    (( removed++ )) || true
  fi
done

print ""
print "$added added, $updated updated, $unchanged unchanged${removed:+, $removed stale}"
[[ $DRY_RUN -eq 0 ]] && print "Files written to $DEST_DIR"
