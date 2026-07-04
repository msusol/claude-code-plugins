#!/usr/bin/env zsh
# migrate-legacy-clinerules.zsh — one-time cleanup for a Claude Code plugin
# installed under the old "clinerules" id, before the rename to "docs".
#
# Note what this script is NOT for: deploy.zsh and uninstall.zsh already detect and
# rewrite the ~/.claude/CLAUDE.md sentinel block in place (old "clinerules-imports"
# -> current "docs-imports") every time they run, automatically, no separate step
# needed. That part of the migration is already handled.
#
# What this script DOES handle is the part deploy.zsh doesn't touch: Claude Code's
# own plugin-registration state, which does not auto-follow a marketplace.json
# rename:
#   1. the old `clinerules@msusol` plugin registration
#   2. an orphaned standalone `clinerules` directory-marketplace entry, if present
#      (separate from the consolidated `msusol` marketplace — a leftover from
#      early per-plugin marketplace registration, before everything moved under
#      one `msusol` marketplace)
#   3. the stale plugin cache directory left behind at
#      ~/.claude/plugins/cache/clinerules/
#
# Usage:
#   ./migrate-legacy-clinerules.zsh            perform cleanup
#   ./migrate-legacy-clinerules.zsh --dry-run   show what would happen, without changes
#
# Safe to run even if there's nothing to migrate — reports nothing found either way.
# After running, install docs@msusol and refresh the CLAUDE.md sentinel:
#   ./deploy.zsh

set -euo pipefail

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRY_RUN=1 ;;
    *) print "unknown argument: $arg" >&2; exit 1 ;;
  esac
done

print "==> docs legacy-clinerules migration"
[[ $DRY_RUN -eq 1 ]] && print "(dry run — no changes made)"
print ""

if ! command -v claude &>/dev/null; then
  print "⚠ claude CLI not found — nothing to migrate"
  exit 0
fi

SETTINGS="$HOME/.claude/settings.json"
MARKETPLACES="$HOME/.claude/plugins/known_marketplaces.json"

# ── 1. Uninstall the old clinerules@msusol plugin registration, if present ───
has_old_plugin=0
if [[ -f "$SETTINGS" ]]; then
  has_old_plugin=$(python3 -c "
import json
try:
    with open('$SETTINGS') as f:
        s = json.load(f)
    print(1 if s.get('enabledPlugins', {}).get('clinerules@msusol') else 0)
except Exception:
    print(0)
")
fi
if [[ "$has_old_plugin" == "1" ]]; then
  if [[ $DRY_RUN -eq 1 ]]; then
    print "would uninstall: clinerules@msusol"
  else
    claude plugin uninstall clinerules@msusol 2>/dev/null || true
    print "✓ Uninstalled clinerules@msusol"
  fi
else
  print "  clinerules@msusol not installed — nothing to do"
fi

# ── 2. Remove an orphaned standalone "clinerules" marketplace entry, if present ─
has_orphan_marketplace=0
if [[ -f "$MARKETPLACES" ]]; then
  has_orphan_marketplace=$(python3 -c "
import json
try:
    with open('$MARKETPLACES') as f:
        m = json.load(f)
    print(1 if 'clinerules' in m else 0)
except Exception:
    print(0)
")
fi
if [[ "$has_orphan_marketplace" == "1" ]]; then
  if [[ $DRY_RUN -eq 1 ]]; then
    print "would remove marketplace: clinerules"
  else
    claude plugin marketplace remove clinerules 2>/dev/null || true
    print "✓ Removed orphaned 'clinerules' marketplace entry"
  fi
else
  print "  No orphaned 'clinerules' marketplace entry — nothing to do"
fi

# ── 3. Purge the stale plugin cache tree, if present ──────────────────────────
CACHE_DIR="$HOME/.claude/plugins/cache/clinerules"
if [[ -d "$CACHE_DIR" ]]; then
  if [[ $DRY_RUN -eq 1 ]]; then
    print "would remove: $CACHE_DIR"
  else
    rm -rf "$CACHE_DIR"
    print "✓ Removed stale cache: $CACHE_DIR"
  fi
else
  print "  No stale cache at $CACHE_DIR — nothing to do"
fi

print ""
print "==> docs legacy-clinerules migration complete."
print "    Next: install docs@msusol and refresh the CLAUDE.md sentinel:"
print "      ./deploy.zsh"
