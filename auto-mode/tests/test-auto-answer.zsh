#!/usr/bin/env zsh
# Unit tests for plugins/auto-mode/hooks/auto-answer.zsh
# Usage: zsh tests/test-auto-answer.zsh   (exit 0 = all pass)

HOOK="${0:A:h}/../plugins/auto-mode/hooks/auto-answer.zsh"
pass=0; fail=0
STATE=$(mktemp -d); export AUTO_MODE_DIR="$STATE"; unset AUTO_MODE_ASK AUTO_MODE_ASK_MODE
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
# one single-select question, recommended option second; one multiSelect with two recommended; one with none
QI='{"questions":[
  {"question":"Accept ADR 0001?","header":"ADR","multiSelect":false,"options":[{"label":"Keep proposed","description":"x"},{"label":"Accept (Recommended)","description":"y"}]},
  {"question":"Which checks?","header":"Checks","multiSelect":true,"options":[{"label":"lint (Recommended)","description":""},{"label":"docs","description":""},{"label":"unit (recommended)","description":""}]},
  {"question":"Pick one","header":"P","multiSelect":false,"options":[{"label":"First","description":""},{"label":"Second","description":""}]}
]}'
in() { printf '{"session_id":"s1","cwd":"%s","tool_name":"%s","tool_input":%s}' "$1" "$2" "$3"; }
ans() { print -r -- "$1" | jq -r "$2" 2>/dev/null; }

print "=== off by default"
check "main branch, no flag: no-op"                  "$(run "$(in "$main_repo" AskUserQuestion "$QI")")" ""
check "other tool on an exp branch: no-op"           "$(run "$(in "$exp_repo" Bash '{"command":"ls"}')")" ""

print "=== exp/* branch: recommended"
out=$(run "$(in "$exp_repo" AskUserQuestion "$QI")")
check "allows the call"                              "$(ans "$out" '.hookSpecificOutput.permissionDecision')" "allow"
check "single question: the (Recommended) label"     "$(ans "$out" '.hookSpecificOutput.updatedInput.answers["Accept ADR 0001?"]')" "Accept (Recommended)"
check "multiSelect: every recommended, case-insens." "$(ans "$out" '.hookSpecificOutput.updatedInput.answers["Which checks?"]')" "lint (Recommended), unit (recommended)"
check "no recommended: the first option"            "$(ans "$out" '.hookSpecificOutput.updatedInput.answers["Pick one"]')" "First"
check "original questions are kept"                  "$(ans "$out" '.hookSpecificOutput.updatedInput.questions | length')" "3"
check "says it is not a human decision"              "$out" "not human decisions"
check "writes the audit log"                         "$(tail -1 "$STATE/ask-log.jsonl" 2>/dev/null)" '"policy":"recommended"'

print "=== policy"
export AUTO_MODE_ASK=first
out=$(run "$(in "$exp_repo" AskUserQuestion "$QI")")
check "first: picks the first option"                "$(ans "$out" '.hookSpecificOutput.updatedInput.answers["Accept ADR 0001?"]')" "Keep proposed"
export AUTO_MODE_ASK=off
check "off: no-op"                                   "$(run "$(in "$exp_repo" AskUserQuestion "$QI")")" ""
unset AUTO_MODE_ASK

print "=== flag file alone is opt-in"
touch "$STATE/enabled"
check "flag, main branch, no ask policy: no-op"      "$(run "$(in "$main_repo" AskUserQuestion "$QI")")" ""
echo recommended > "$STATE/ask"
out=$(run "$(in "$main_repo" AskUserQuestion "$QI")")
check "flag plus ask file: answers"                  "$(ans "$out" '.hookSpecificOutput.permissionDecision')" "allow"
rm -f "$STATE/enabled" "$STATE/ask"

print "=== deny mode"
export AUTO_MODE_ASK_MODE=deny
out=$(run "$(in "$exp_repo" AskUserQuestion "$QI")")
check "denies the call"                              "$(ans "$out" '.hookSpecificOutput.permissionDecision')" "deny"
check "reason carries the answers"                   "$(ans "$out" '.hookSpecificOutput.permissionDecisionReason')" "Accept ADR 0001? -> Accept (Recommended)"
unset AUTO_MODE_ASK_MODE

print "=== fails open"
check "empty questions: no-op"                       "$(run "$(in "$exp_repo" AskUserQuestion '{"questions":[]}')")" ""
check "garbage input: no-op"                         "$(run 'not json')" ""
check "no tool_input: no-op"                         "$(run '{"tool_name":"AskUserQuestion","cwd":"/tmp"}')" ""

printf '\n%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
