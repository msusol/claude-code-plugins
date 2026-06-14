#!/usr/bin/env zsh
# git-guard installer — idempotent, safe to re-run.

set -euo pipefail

SCRIPT_DIR="${0:A:h}"

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
step()  { echo "${BLUE}==>${NC} $1" }
ok()    { echo "${GREEN}✓${NC}  $1" }
warn()  { echo "${YELLOW}!${NC}  $1" }
fail()  { echo "${RED}✗${NC}  $1"; exit 1 }

# ── 1. Locate the real git (must not pick up our wrapper) ─────────────────────
step "Locating real git binary..."
REAL_GIT=""
for candidate in /usr/bin/git /usr/local/bin/git /opt/homebrew/bin/git; do
  if [[ -x "$candidate" ]]; then
    REAL_GIT="$candidate"
    break
  fi
done
[[ -n "$REAL_GIT" ]] || fail "Cannot find git at any known path (/usr/bin, /usr/local/bin, /opt/homebrew/bin)"
ok "Real git: $REAL_GIT"

# ── 2. Verify ~/.local/bin is ahead of REAL_GIT in PATH ──────────────────────
step "Checking PATH..."
LOCAL_BIN="$HOME/.local/bin"
if ! echo "$PATH" | tr ':' '\n' | grep -qxF "$LOCAL_BIN"; then
  warn "~/.local/bin is not in your PATH."
  warn "Add this to your ~/.zshrc and restart your shell:"
  warn "  export PATH=\"\$HOME/.local/bin:\$PATH\""
  warn "The wrapper will be installed but won't shadow git until PATH is updated."
else
  # Confirm it appears before REAL_GIT
  path_order=$(echo "$PATH" | tr ':' '\n' | grep -nxF -e "$LOCAL_BIN" -e "$(dirname $REAL_GIT)" | sort -t: -k1 -n | head -1 | cut -d: -f2)
  if [[ "$path_order" == "$LOCAL_BIN" ]]; then
    ok "~/.local/bin is ahead of $(dirname $REAL_GIT) in PATH"
  else
    warn "~/.local/bin appears AFTER $(dirname $REAL_GIT) in PATH — wrapper won't shadow git."
    warn "Move ~/.local/bin earlier in PATH in your ~/.zshrc."
  fi
fi

# ── 3. Install git wrapper ────────────────────────────────────────────────────
step "Installing git wrapper to $LOCAL_BIN/git..."
mkdir -p "$LOCAL_BIN"
sed "s|__REAL_GIT_PLACEHOLDER__|$REAL_GIT|" "$SCRIPT_DIR/src/git-wrapper.zsh" > "$LOCAL_BIN/git"
chmod +x "$LOCAL_BIN/git"
ok "Installed $LOCAL_BIN/git (real git: $REAL_GIT)"

# ── 4. Install PreToolUse hook ────────────────────────────────────────────────
step "Installing PreToolUse hook..."
mkdir -p "$HOME/.claude/scripts"
cp "$SCRIPT_DIR/src/git-guard-hook.zsh" "$HOME/.claude/scripts/git-guard-hook.zsh"
chmod +x "$HOME/.claude/scripts/git-guard-hook.zsh"
ok "Installed ~/.claude/scripts/git-guard-hook.zsh"

# ── 5. Create allowlist (skip if already exists) ──────────────────────────────
step "Setting up allowlist..."
mkdir -p "$HOME/.config/git-guard"
if [[ -f "$HOME/.config/git-guard/allowlist" ]]; then
  warn "Allowlist already exists — not overwritten: ~/.config/git-guard/allowlist"
else
  cp "$SCRIPT_DIR/src/allowlist.template" "$HOME/.config/git-guard/allowlist"
  ok "Created ~/.config/git-guard/allowlist"
  warn "Edit it to add your approved remote URL patterns before committing."
fi

# ── 6. Register git-guard as a Claude Code plugin marketplace + install ──────
# The git-guard repo doubles as a single-plugin marketplace (see
# .claude-plugin/marketplace.json at the repo root). We register it with
# the Claude Code CLI so the operator gets:
#   - /commit resolved without any manual /plugin enable step
#   - claude plugin update git-guard for future versioned upgrades
#   - per-session disable via claude plugin disable git-guard if needed
#     (useful as an enterprise circuit-breaker)
step "Registering git-guard plugin marketplace + enabling commit plugin..."

# Best-effort cleanup of two earlier install shapes so operators upgrading
# from older releases end up in a single canonical state:
#   1) Standalone SKILL.md inside the official marketplace dir.
#   2) User-skill dir (briefly used while debugging plugin auto-enable).
LEGACY_PLUGIN_DIR="$HOME/.claude/plugins/marketplaces/claude-plugins-official/plugins/git-guard"
if [[ -d "$LEGACY_PLUGIN_DIR" ]]; then
  rm -rf "$LEGACY_PLUGIN_DIR"
  ok "Removed legacy plugin-marketplace skill at $LEGACY_PLUGIN_DIR"
fi
LEGACY_USER_SKILL_DIR="$HOME/.claude/skills/commit"
if [[ -d "$LEGACY_USER_SKILL_DIR" ]] && grep -q "git-guard" "$LEGACY_USER_SKILL_DIR/SKILL.md" 2>/dev/null; then
  rm -rf "$LEGACY_USER_SKILL_DIR"
  ok "Removed legacy user-skill copy at $LEGACY_USER_SKILL_DIR"
fi

if ! command -v claude >/dev/null 2>&1; then
  warn "claude CLI not found on PATH — skipping plugin registration."
  warn "Install Claude Code (https://claude.com/claude-code) and re-run deploy.zsh"
  warn "to wire up /commit."
else
  # Register the marketplace. Idempotent: 'add' on an already-registered
  # source is a no-op error we swallow.
  if claude plugin marketplace list 2>/dev/null | grep -qw "git-guard"; then
    ok "Marketplace 'git-guard' already registered"
  else
    if claude plugin marketplace add "$SCRIPT_DIR" >/dev/null 2>&1; then
      ok "Registered marketplace 'git-guard' from $SCRIPT_DIR"
    else
      warn "Failed to register marketplace via claude plugin marketplace add."
      warn "Run it yourself: claude plugin marketplace add $SCRIPT_DIR"
    fi
  fi

  # Install (= enable) the plugin from that marketplace. Idempotent.
  if claude plugin list 2>/dev/null | grep -qw "git-guard"; then
    ok "Plugin 'git-guard' already installed"
  else
    if claude plugin install "git-guard@git-guard" >/dev/null 2>&1; then
      ok "Installed plugin 'git-guard@git-guard'"
    else
      warn "Failed to install plugin via claude plugin install."
      warn "Run it yourself: claude plugin install git-guard@git-guard"
    fi
  fi
fi

# ── 7. Merge settings.json ────────────────────────────────────────────────────
step "Merging ~/.claude/settings.json..."
python3 "$SCRIPT_DIR/scripts/manage-settings.py" install

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo "${GREEN}Installation complete.${NC}"
echo ""
echo "Next steps:"
echo "  1. Edit ~/.config/git-guard/allowlist — add your approved remote URL patterns"
echo "  2. Restart Claude Code to pick up the new hook and skill"
echo "  3. Use /commit (or say 'commit my changes') for the safe commit workflow"
