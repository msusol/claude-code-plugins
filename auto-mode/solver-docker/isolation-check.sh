#!/usr/bin/env bash
# Run inside the container (run-ab.zsh check): prove what the experiment can and cannot see.
pass=0; fail=0
# The older AB_* names still work as aliases of SOLVER_*; the host passes both.
docs="${SOLVER_DOCS:-${AB_DOCS:-0}}"; check_only="${SOLVER_CHECK_ONLY:-${AB_CHECK_ONLY:-}}"
ok()  { printf 'PASS  %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL  %s\n' "$1"; fail=$((fail + 1)); }
check() { local desc="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$desc"; else bad "$desc"; fi; }
refuse() { local desc="$1"; shift; if "$@" >/dev/null 2>&1; then bad "$desc"; else ok "$desc"; fi; }

# The docs/ harness must be present in the docs image (SOLVER_DOCS=1) and absent from the plain one, so a baseline
# arm cannot be running with planning rules by accident. SOLVER_PLUGINS_DIR is only overridden by the tests.
docs_checks() {
  local rules="$HOME/.claude/rules" md="$HOME/.claude/CLAUDE.md" src="${SOLVER_PLUGINS_DIR:-${AB_PLUGINS_DIR:-/opt/claude-code-plugins}}/docs"
  echo "=== docs/ harness (SOLVER_DOCS=$docs)"
  if [[ "$docs" == 1 ]]; then
    check  "docs rules installed in ~/.claude/rules"        bash -c "ls '$rules'/planning-docs-plans.md"
    check  "docs rules @-imported from ~/.claude/CLAUDE.md" bash -c "grep -q 'BEGIN docs-imports' '$md' && grep -q 'planning-docs-plans.md' '$md'"
    check  "docs source present in the image"               test -d "$src"
  else
    refuse "no planning rules in ~/.claude/rules"           bash -c "ls '$rules'/planning-*.md"
    refuse "no docs-imports block in ~/.claude/CLAUDE.md"   bash -c "grep -q 'BEGIN docs-imports' '$md'"
    refuse "docs source removed from the image"             test -e "$src"
  fi
}
if [[ "$check_only" == docs ]]; then
  docs_checks; echo; printf '%d passed, %d failed\n' "$pass" "$fail"; [[ "$fail" -eq 0 ]]; exit
fi

echo "=== filesystem"
check  "running as an unprivileged user"             test "$(id -u)" -ne 0
check  "home holds only this container's user"       test "$(ls /home)" = "claude"
refuse "no host project folders (/home/msusol)"      test -e /home/msusol
refuse "no Docker socket mounted"                    test -S /var/run/docker.sock
refuse "no Claude history from the host"             test -d "$HOME/.claude/projects"
refuse "no SSH keys"                                 test -e "$HOME/.ssh"
check  "/work is a fresh repo with one commit"       test "$(git -C /work rev-list --count --all)" = "1"
check  "/work remote is the scratch remote"          bash -c 'git -C /work remote get-url origin | grep -q example.invalid'
check  "/work is on an exp/* branch"                 bash -c 'git -C /work branch --show-current | grep -q "^exp/"'

echo "=== network"
refuse "example.com unreachable"                     curl -s -o /dev/null --max-time 5 https://example.com
refuse "github.com unreachable"                      curl -s -o /dev/null --max-time 5 https://github.com
check  "api.anthropic.com reachable"                 curl -s -o /dev/null --max-time 10 https://api.anthropic.com
refuse "cannot change the firewall (no capability)"  iptables -F

echo "=== tooling"
check  "git-guard installed"                         bash -c 'claude plugin list 2>/dev/null | grep -q git-guard'
check  "auto-mode installed"                         bash -c 'claude plugin list 2>/dev/null | grep -q auto-mode'
check  "WebFetch and WebSearch denied"               jq -e '(.permissions.deny // []) | (index("WebFetch") != null) and (index("WebSearch") != null)' "$HOME/.claude/settings.json"

docs_checks
if [[ "$docs" == 1 ]]; then
  check "docs plugin installed" bash -c 'claude plugin list 2>/dev/null | grep -qw docs'
fi

echo
printf '%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
