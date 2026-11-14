#!/usr/bin/env zsh
# Unit tests for plugins/auto-mode/hooks/auto-continue.zsh
# Usage: zsh tests/test-auto-continue.zsh   (exit 0 = all pass)

HOOK="${0:A:h}/../plugins/auto-mode/hooks/auto-continue.zsh"
pass=0; fail=0
STATE=$(mktemp -d); export AUTO_MODE_DIR="$STATE"; unset AUTO_MODE_MAX
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
in() { printf '{"session_id":"s1","cwd":"%s","stop_hook_active":%s,"last_assistant_message":"%s"}' "$1" "$2" "$3"; }

print "=== off by default"
check "main branch, no flag: no-op"        "$(run "$(in "$main_repo" false 'did stuff')")" ""

print "=== on via flag file"
touch "$STATE/enabled"
check "flag: blocks and continues"         "$(run "$(in "$main_repo" false 'did stuff')")" '"decision": "block"'
check "reason forbids push"                "$(run "$(in "$main_repo" true 'did stuff')")"  'git push'
check "DONE stops"                         "$(run "$(in "$main_repo" true 'AUTO-MODE: DONE all good')")" ""
check "BLOCKED stops"                      "$(run "$(in "$main_repo" true 'AUTO-MODE: BLOCKED need key')")" ""
rm -f "$STATE/enabled"

print "=== on via exp/* branch"
check "exp branch: blocks and continues"   "$(run "$(in "$exp_repo" false 'did stuff')")" '"decision": "block"'

print "=== cap"
rm -rf "$STATE/counters"; echo 2 > "$STATE/max"
check "continuation 1"                     "$(run "$(in "$exp_repo" false 'x')")" 'continuation 1 of 2'
check "continuation 2"                     "$(run "$(in "$exp_repo" true 'x')")"  'continuation 2 of 2'
check "cap reached: stops with message"    "$(run "$(in "$exp_repo" true 'x')")"  'cap reached'
check "after cap: counter cleared, next"   "$(run "$(in "$exp_repo" true 'x')")"  'continuation 1 of 2'
check "new user turn resets the counter"   "$(run "$(in "$exp_repo" true 'x')")"  'continuation 2 of 2'
check "stop_hook_active=false resets"      "$(run "$(in "$exp_repo" false 'x')")" 'continuation 1 of 2'
check "AUTO_MODE_MAX env overrides file"   "$(AUTO_MODE_MAX=9 run "$(in "$exp_repo" true 'x')")" 'of 9'
echo abc > "$STATE/max"
check "bad max falls back to 8"            "$(run "$(in "$exp_repo" false 'x')")" 'of 8'

print "=== transcript fallback for the last message"
rm -rf "$STATE/counters"; rm -f "$STATE/max"
tr=$(mktemp)
printf '%s\n' '{"type":"user","message":{"content":"hi"}}' '{"type":"assistant","message":{"content":[{"type":"text","text":"All done. AUTO-MODE: DONE"}]}}' > "$tr"
check "DONE read from transcript"          "$(run "{\"session_id\":\"s2\",\"cwd\":\"$exp_repo\",\"stop_hook_active\":true,\"transcript_path\":\"$tr\"}")" ""
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"Next I would add tests."}]}}' > "$tr"
check "no marker in transcript: continues" "$(run "{\"session_id\":\"s2\",\"cwd\":\"$exp_repo\",\"stop_hook_active\":false,\"transcript_path\":\"$tr\"}")" '"decision": "block"'

print "=== fails open"
check "garbage input: no-op"               "$(run 'not json')" ""
check "empty input: no-op"                 "$(run '')" ""

rm -rf "$STATE" "$exp_repo" "$main_repo" "$tr"
print ""; printf '%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
