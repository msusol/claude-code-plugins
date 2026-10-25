#!/usr/bin/env zsh
# bug-bash installer — idempotent, safe to re-run.
#
# This plugin is skills-only (no hooks/wrappers to install), so all this
# script does is register the marketplace and install the plugin — Claude
# Code's native plugin loader handles making plugins/bug-bash/skills/
# available as /bug-bash from there.

set -euo pipefail

REPO_DIR="${0:A:h}"

print "==> bug-bash installer"
print ""

if command -v claude &>/dev/null; then
  claude plugin marketplace add "${REPO_DIR:h}" 2>/dev/null || true
  claude plugin install bug-bash@losus-ai 2>/dev/null || true
  print "✓ Plugin registered with Claude Code"
else
  print "⚠ claude CLI not found — skipping plugin registration"
  print "  Run manually: claude plugin marketplace add ${REPO_DIR:h} && claude plugin install bug-bash@losus-ai"
fi

print ""
print "==> bug-bash installed."
print "    Skill available as /bug-bash in every session."
