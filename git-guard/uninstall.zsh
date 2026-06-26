#!/usr/bin/env zsh
# git-guard uninstaller — removes all installed files and settings entries.
# The allowlist (~/.config/git-guard/allowlist) is intentionally preserved.

set -euo pipefail

SCRIPT_DIR="${0:A:h}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo "${GREEN}✓${NC}  $1" }
warn() { echo "${YELLOW}!${NC}  $1" }
skip() { echo "    $1 (not found, skipping)" }

echo "Uninstalling git-guard..."
echo ""

# ── Shell wrapper ──────────────────────────────────────────────────────────────
if [[ -f "$HOME/.local/bin/git" ]]; then
  # Only remove if it's our wrapper (check for the guard comment)
  if grep -q "git-guard" "$HOME/.local/bin/git" 2>/dev/null; then
    rm "$HOME/.local/bin/git"
    ok "Removed ~/.local/bin/git"
  else
    warn "~/.local/bin/git exists but doesn't look like our wrapper — not removed"
  fi
else
  skip "~/.local/bin/git"
fi

# ── Hook script ───────────────────────────────────────────────────────────────
if [[ -f "$HOME/.claude/scripts/git-guard-hook.zsh" ]]; then
  rm "$HOME/.claude/scripts/git-guard-hook.zsh"
  ok "Removed ~/.claude/scripts/git-guard-hook.zsh"
else
  skip "~/.claude/scripts/git-guard-hook.zsh"
fi

# ── Plugin + marketplace ──────────────────────────────────────────────────────
# Mirror the install order in reverse: uninstall the plugin first, then
# remove the marketplace registration. Both are idempotent — silent
# success when nothing is registered.
if command -v claude >/dev/null 2>&1; then
  if claude plugin list 2>/dev/null | grep -qw "git-guard"; then
    claude plugin uninstall git-guard >/dev/null 2>&1 \
      && ok "Uninstalled plugin 'git-guard'" \
      || warn "claude plugin uninstall git-guard failed — try by hand"
  else
    skip "claude plugin 'git-guard'"
  fi
  # The 'msusol' marketplace is shared by every plugin in this repo, so we do
  # NOT remove it when uninstalling a single plugin (that would drop the others
  # too). Remove it by hand only when removing the whole collection:
  #   claude plugin marketplace remove msusol
  skip "shared marketplace 'msusol' (left registered for other plugins)"
else
  warn "claude CLI not found on PATH — skipping plugin + marketplace removal."
fi

# ── Legacy install locations ──────────────────────────────────────────────────
# Earlier git-guard releases dropped the skill at one of these paths.
# Clean both so an upgrade-then-uninstall doesn't leave orphans.
for legacy in \
  "$HOME/.claude/plugins/marketplaces/claude-plugins-official/plugins/git-guard" \
  "$HOME/.claude/skills/commit"; do
  if [[ -d "$legacy" ]]; then
    # Only delete a user-skill copy that's clearly ours.
    if [[ "$legacy" == "$HOME/.claude/skills/commit" ]]; then
      if ! grep -q "git-guard" "$legacy/SKILL.md" 2>/dev/null; then
        warn "$legacy exists but doesn't look like our skill — not removed"
        continue
      fi
    fi
    rm -rf "$legacy"
    ok "Removed legacy $legacy"
  fi
done

# ── settings.json entries ─────────────────────────────────────────────────────
if [[ -f "$HOME/.claude/settings.json" ]]; then
  python3 "$SCRIPT_DIR/scripts/manage-settings.py" uninstall
else
  skip "~/.claude/settings.json"
fi

echo ""
echo "Done. Allowlist preserved at ~/.config/git-guard/allowlist"
echo "Restart Claude Code to apply changes."
