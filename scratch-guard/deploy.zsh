#!/usr/bin/env zsh
# scratch-guard installer — idempotent, safe to re-run.

set -euo pipefail

SCRIPT_DIR="${0:A:h}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
step()  { echo "${BLUE}==>${NC} $1" }
ok()    { echo "${GREEN}✓${NC}  $1" }
warn()  { echo "${YELLOW}!${NC}  $1" }
fail()  { echo "${RED}✗${NC}  $1"; exit 1 }

# ── 1. Install PreToolUse hook ────────────────────────────────────────────────
step "Installing PreToolUse hook..."
mkdir -p "$HOME/.claude/scripts"
cp "$SCRIPT_DIR/src/scratch-guard-hook.zsh" "$HOME/.claude/scripts/scratch-guard-hook.zsh"
chmod +x "$HOME/.claude/scripts/scratch-guard-hook.zsh"
ok "Installed ~/.claude/scripts/scratch-guard-hook.zsh"

# ── 2. Register scratch-guard as a Claude Code plugin ─────────────────────────
# The losus-ai marketplace is shared with git-guard/docs/etc. and is
# registered once; just ensure it's present and install this plugin from it.
step "Registering marketplace + enabling scratch-guard..."

if ! command -v claude >/dev/null 2>&1; then
  warn "claude CLI not found on PATH — skipping plugin registration."
  warn "Install Claude Code (https://claude.com/claude-code) and re-run deploy.zsh"
else
  if claude plugin marketplace list 2>/dev/null | grep -qw "losus-ai"; then
    ok "Marketplace 'losus-ai' already registered"
  else
    if claude plugin marketplace add "${SCRIPT_DIR:h}" >/dev/null 2>&1; then
      ok "Registered marketplace 'losus-ai' from ${SCRIPT_DIR:h}"
    else
      warn "Failed to register marketplace via claude plugin marketplace add."
      warn "Run it yourself: claude plugin marketplace add ${SCRIPT_DIR:h}"
    fi
  fi

  if claude plugin list 2>/dev/null | grep -qw "scratch-guard@losus-ai"; then
    ok "Plugin 'scratch-guard@losus-ai' already installed"
  else
    if claude plugin install "scratch-guard@losus-ai" >/dev/null 2>&1; then
      ok "Installed plugin 'scratch-guard@losus-ai'"
    else
      warn "Failed to install plugin via claude plugin install."
      warn "Run it yourself: claude plugin install scratch-guard@losus-ai"
    fi
  fi

  # install is a no-op when already installed; update pulls a bumped version.
  claude plugin marketplace update losus-ai >/dev/null 2>&1 || true
  claude plugin update scratch-guard@losus-ai >/dev/null 2>&1 || true
fi

# ── 3. Merge settings.json ────────────────────────────────────────────────────
step "Merging ~/.claude/settings.json..."
python3 "$SCRIPT_DIR/scripts/manage-settings.py" install

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo "${GREEN}Installation complete.${NC}"
echo ""
echo "Next steps:"
echo "  1. Restart Claude Code to pick up the new hook."
echo "  2. Any Bash heredoc/redirect or Write call that materializes a"
echo "     script-looking file (.sh/.py/.zsh/etc.) directly under /tmp,"
echo "     /private/tmp, or /var/folders (outside a session's own"
echo "     .../scratchpad/ subdirectory), or that writes a base64"
echo "     decode-into-exec pattern to any file, is now blocked and"
echo "     redirected to the session scratchpad."
echo "  3. Deliberate, explained exception for a Bash command: prefix with"
echo "     SCRATCH_GUARD_SANCTIONED=1."
