#!/usr/bin/env zsh
# cost-dashboard plugin uninstaller

set -euo pipefail

print "==> cost-dashboard uninstaller"

if command -v claude &>/dev/null; then
  claude plugin uninstall cost-dashboard 2>/dev/null || true
  print "✓ Plugin unregistered"
fi

html="$HOME/.claude/cost-dashboard.html"
if [[ -f "$html" ]]; then
  print "  Generated dashboard left in place: $html (delete manually if unwanted)"
fi

print ""
print "==> cost-dashboard uninstalled."
