#!/usr/bin/env zsh
# Runs every plugin's own deploy.zsh in this repo, in one shot.
#
# Each plugin's installer is independently idempotent (safe to re-run), so
# this is just a discovery + sequencing convenience over running them by
# hand -- it does not duplicate any plugin's install logic. New plugins need
# no changes here: this discovers every top-level */deploy.zsh automatically.
#
# Usage:
#   ./deploy-all.zsh              # deploy every plugin found
#   ./deploy-all.zsh docs         # deploy only the named plugin(s)
#   ./deploy-all.zsh docs git-guard

set -euo pipefail

REPO_DIR="${0:A:h}"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
step()  { print "${BLUE}==>${NC} $1" }
ok()    { print "${GREEN}✓${NC}  $1" }
fail()  { print "${RED}✗${NC}  $1" }

only=("$@")

typeset -a scripts
for f in "$REPO_DIR"/*/deploy.zsh(N); do
  scripts+=("$f")
done

if (( ${#scripts[@]} == 0 )); then
  print "No */deploy.zsh found under $REPO_DIR"
  exit 1
fi

if (( ${#only[@]} > 0 )); then
  typeset -a filtered
  for f in "${scripts[@]}"; do
    plugin_name="${${f:h}:t}"
    for want in "${only[@]}"; do
      [[ "$plugin_name" == "$want" ]] && filtered+=("$f")
    done
  done
  scripts=("${filtered[@]}")
  if (( ${#scripts[@]} == 0 )); then
    print "No matching plugin(s) for: ${only[*]}"
    print "Available: $(for f in "$REPO_DIR"/*/deploy.zsh(N); do print -n "${${f:h}:t} "; done)"
    exit 1
  fi
fi

print "==> Deploying ${#scripts[@]} plugin(s)"
print ""

typeset -a succeeded failed
for script in "${scripts[@]}"; do
  plugin_name="${${script:h}:t}"
  step "Deploying $plugin_name..."
  if "$script"; then
    ok "$plugin_name deployed"
    succeeded+=("$plugin_name")
  else
    fail "$plugin_name failed"
    failed+=("$plugin_name")
  fi
  print ""
done

print "==> Summary"
(( ${#succeeded[@]} > 0 )) && ok "Succeeded: ${succeeded[*]}"
if (( ${#failed[@]} > 0 )); then
  fail "Failed: ${failed[*]}"
  exit 1
fi
