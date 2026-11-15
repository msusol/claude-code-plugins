#!/usr/bin/env zsh
# Unit tests for plugins/auto-mode/hooks/session-protocol.zsh
# Usage: zsh tests/test-session-protocol.zsh   (exit 0 = all pass)

HOOK="${0:A:h}/../plugins/auto-mode/hooks/session-protocol.zsh"
pass=0; fail=0
STATE=$(mktemp -d); export AUTO_MODE_DIR="$STATE"; unset AUTO_MODE_PROTOCOL
exp_repo=$(mktemp -d); main_repo=$(mktemp -d)
git -C "$exp_repo" init -q -b exp/ab-test 2>/dev/null || { git -C "$exp_repo" init -q; git -C "$exp_repo" checkout -q -b exp/ab-test; }
git -C "$main_repo" init -q -b main 2>/dev/null || git -C "$main_repo" init -q

run() { printf '%s' "$1" | zsh "$HOOK" 2>/dev/null; }
check() {  # desc, output, substring-or-empty
  local desc="$1" out="$2" want="$3"
  if [[ -z "$want" && -z "$out" ]] || [[ -n "$want" && "$out" == *"$want"* ]]; then
    printf 'PASS  %s\n' "$desc"; (( pass++ ))
  else
    printf 'FAIL  %s — want [%s], got [%s]\n' "$desc" "$want" "$out"; (( fail++ ))
  fi
}
in() { printf '{"session_id":"s1","cwd":"%s","hook_event_name":"SessionStart","source":"startup"}' "$1"; }

print "=== off by default"
check "main branch, no flag: adds nothing"        "$(run "$(in "$main_repo")")" ""

print "=== exp/* branch"
out=$(run "$(in "$exp_repo")")
check "adds SessionStart context"                 "$out" '"hookEventName": "SessionStart"'
check "names the DONE marker"                     "$out" "AUTO-MODE: DONE"
check "names the BLOCKED marker"                  "$out" "AUTO-MODE: BLOCKED"
check "asks for a 2-line summary"                 "$out" "2-line summary"
check "forbids push"                              "$out" "git push"
check "does not widen the task"                   "$out" "do not widen the task"

print "=== flag file"
touch "$STATE/enabled"
check "flag, main branch: adds context"           "$(run "$(in "$main_repo")")" "AUTO-MODE: DONE"
export AUTO_MODE_PROTOCOL=off
check "AUTO_MODE_PROTOCOL=off: adds nothing"      "$(run "$(in "$main_repo")")" ""
unset AUTO_MODE_PROTOCOL
echo off > "$STATE/protocol"
check "protocol file off: adds nothing"           "$(run "$(in "$exp_repo")")" ""
rm -f "$STATE/enabled" "$STATE/protocol"

print "=== fails open"
check "garbage input on an exp branch dir: none"  "$(run 'not json')" ""
check "no cwd: none"                              "$(run '{"session_id":"s1"}')" ""

printf '\n%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
