#!/usr/bin/env zsh
# plan-bash installer — idempotent, safe to re-run.
#
# This plugin is skills-only (no hooks/wrappers to install), so all this
# script does is register the marketplace and install the plugin — Claude
# Code's native plugin loader handles making plugins/plan-bash/skills/
# available as /plan-bash from there.

set -euo pipefail

REPO_DIR="${0:A:h}"

print "==> plan-bash installer"
print ""

if command -v claude &>/dev/null; then
  claude plugin marketplace add "${REPO_DIR:h}" 2>/dev/null || true
  claude plugin install plan-bash@losus-ai 2>/dev/null || true
  # install is a no-op when already installed; update pulls a bumped version
  claude plugin marketplace update losus-ai 2>/dev/null || true
  claude plugin update plan-bash@losus-ai 2>/dev/null || true
  print "✓ Plugin registered with Claude Code"
else
  print "⚠ claude CLI not found — skipping plugin registration"
  print "  Run manually: claude plugin marketplace add ${REPO_DIR:h} && claude plugin install plan-bash@losus-ai"
fi

print ""
print "==> plan-bash installed."
print "    Skill available as /plan-bash in every session."
