#!/usr/bin/env zsh
# cost-dashboard plugin installer — idempotent, safe to re-run.
#
# Usage: ./deploy.zsh
#
# What this does:
#   Registers this repo as the `losus-ai` Claude Code plugin marketplace and
#   installs cost-dashboard@losus-ai. The plugin is self-contained (a command
#   plus a stdlib-only Python script), so there are no rules, hooks, or
#   settings.json edits to install.

set -euo pipefail

REPO_DIR="${0:A:h}"

print "==> cost-dashboard installer"

if command -v claude &>/dev/null; then
  claude plugin marketplace add "${REPO_DIR:h}" 2>/dev/null || true
  claude plugin install cost-dashboard@losus-ai 2>/dev/null || true
  # install is a no-op when already installed; update pulls a bumped version
  claude plugin marketplace update losus-ai 2>/dev/null || true
  claude plugin update cost-dashboard@losus-ai 2>/dev/null || true
  print "✓ Plugin registered with Claude Code"
else
  print "⚠ claude CLI not found — skipping plugin registration"
  print "  Run manually: claude plugin marketplace add ${REPO_DIR:h} && claude plugin install cost-dashboard@losus-ai"
fi

print ""
print "==> cost-dashboard installed."
print "    Command → /cost-dashboard:dashboard"
print "    Output  → ~/.claude/cost-dashboard.html"
