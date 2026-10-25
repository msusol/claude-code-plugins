#!/usr/bin/env zsh
# jira-tickets installer — idempotent, safe to re-run.
#
# This plugin is skills-only (no hooks/wrappers to install), so all this
# script does is register the marketplace and install the plugin — Claude
# Code's native plugin loader handles making plugins/jira-tickets/skills/
# available as /jira-describe from there.

set -euo pipefail

REPO_DIR="${0:A:h}"

print "==> jira-tickets installer"
print ""

if command -v claude &>/dev/null; then
  claude plugin marketplace add "${REPO_DIR:h}" 2>/dev/null || true
  claude plugin install jira-tickets@losus-ai 2>/dev/null || true
  # install is a no-op when already installed; update pulls a bumped version
  claude plugin marketplace update losus-ai 2>/dev/null || true
  claude plugin update jira-tickets@losus-ai 2>/dev/null || true
  print "✓ Plugin registered with Claude Code"
else
  print "⚠ claude CLI not found — skipping plugin registration"
  print "  Run manually: claude plugin marketplace add ${REPO_DIR:h} && claude plugin install jira-tickets@losus-ai"
fi

print ""
print "==> jira-tickets installed."
print "    Skill available as /jira-describe in every session."
