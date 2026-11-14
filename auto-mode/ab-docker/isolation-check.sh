#!/usr/bin/env bash
# Run inside the container (run-ab.zsh check): prove what the experiment can and cannot see.
pass=0; fail=0
ok()  { printf 'PASS  %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL  %s\n' "$1"; fail=$((fail + 1)); }
check() { local desc="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$desc"; else bad "$desc"; fi; }
refuse() { local desc="$1"; shift; if "$@" >/dev/null 2>&1; then bad "$desc"; else ok "$desc"; fi; }

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

echo
printf '%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
