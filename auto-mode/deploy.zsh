#!/usr/bin/env zsh
# auto-mode installer — idempotent, safe to re-run.
#
# Plugin-only (hook + skill ship inside the plugin), so this registers the
# marketplace and installs/updates the plugin. Restart Claude Code afterwards.

set -euo pipefail

REPO_DIR="${0:A:h}"

print "==> auto-mode installer"
print ""

command -v jq &>/dev/null || print "⚠ jq not found — the Stop hook needs it and will do nothing without it"

if command -v claude &>/dev/null; then
  claude plugin marketplace add "${REPO_DIR:h}" 2>/dev/null || true
  claude plugin install auto-mode@losus-ai 2>/dev/null || true
  claude plugin marketplace update losus-ai 2>/dev/null || true
  claude plugin update auto-mode@losus-ai 2>/dev/null || true
  print "✓ Plugin registered with Claude Code"
else
  print "⚠ claude CLI not found — skipping plugin registration"
  print "  Run manually: claude plugin marketplace add ${REPO_DIR:h} && claude plugin install auto-mode@losus-ai"
fi

print ""
print "==> auto-mode installed. Restart Claude Code."
print "    /auto-mode on|off|status|max N — or just work on an exp/* branch."
