#!/usr/bin/env zsh
# docs-hub installer — idempotent, safe to re-run.
#
# This plugin is a command plus scripts (no hooks/wrappers to install), so all this
# script does is register the marketplace and install the plugin — Claude
# Code's native plugin loader handles making plugins/docs-hub/commands/
# available as /docs-hub from there.

set -euo pipefail

REPO_DIR="${0:A:h}"

print "==> docs-hub installer"
print ""

if command -v claude &>/dev/null; then
  claude plugin marketplace add "${REPO_DIR:h}" 2>/dev/null || true
  claude plugin install docs-hub@losus-ai 2>/dev/null || true
  # install is a no-op when already installed; update pulls a bumped version
  claude plugin marketplace update losus-ai 2>/dev/null || true
  claude plugin update docs-hub@losus-ai 2>/dev/null || true
  print "✓ Plugin registered with Claude Code"
else
  print "⚠ claude CLI not found — skipping plugin registration"
  print "  Run manually: claude plugin marketplace add ${REPO_DIR:h} && claude plugin install docs-hub@losus-ai"
fi

print ""
print "==> docs-hub installed."
print "    Command available as /docs-hub:hub in every session."
