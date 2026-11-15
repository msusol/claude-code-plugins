#!/usr/bin/env zsh
# auto-mode PreToolUse hook for AskUserQuestion — when auto-mode is on and no human is there to answer,
# pick the option marked "(Recommended)" (else the first) for every question, instead of waiting for a person.
#
# Why: the Stop hook only nudges Claude to continue. A model that opens the interactive question form
# (AskUserQuestion) stalls an unattended run until someone answers. Sonnet 5.5 never asked in the leave-engine
# A/B runs; Fable 5.2 asked three owner-decision questions and waited.
#
# Active when auto-mode is on (flag file ${AUTO_MODE_DIR:-~/.config/auto-mode}/enabled, or the session's cwd is on an
# exp/* branch) AND the ask policy is not "off":
#   AUTO_MODE_ASK (or the file $AUTO_MODE_DIR/ask): recommended | first | off
#   default: recommended on an exp/* branch, off when only the flag file turned auto-mode on (opt in explicitly there)
# Mode of delivery, AUTO_MODE_ASK_MODE:
#   answers (default)  pre-fill the tool's `answers`, so the form never opens
#   deny               refuse the call and tell Claude the answers in the message (no human, proceed on these)
#
# This answers questions; it does not approve anything a person has not been asked. Auto-answers are NOT human
# decisions: they are logged to $AUTO_MODE_DIR/ask-log.jsonl and the message tells Claude to say so in its commit.
# It grants no permissions: git-guard, db-guard, permissions.deny/ask still apply.
# Fails open: no jq, bad input, anything unexpected -> exit 0 (the normal question form appears).

command -v jq &>/dev/null || exit 0

input=$(cat)
[[ "$(print -r -- "$input" | jq -r '.tool_name // ""' 2>/dev/null)" == "AskUserQuestion" ]] || exit 0

STATE_DIR="${AUTO_MODE_DIR:-$HOME/.config/auto-mode}"
cwd=$(print -r -- "$input" | jq -r '.cwd // ""' 2>/dev/null)
session=$(print -r -- "$input" | jq -r '.session_id // "default"' 2>/dev/null)

enabled=0 on_exp=0
[[ -f "$STATE_DIR/enabled" ]] && enabled=1
if [[ -n "$cwd" && -d "$cwd" ]]; then
  branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
  [[ "$branch" == exp/* ]] && { enabled=1; on_exp=1 }
fi
(( enabled )) || exit 0

policy="${AUTO_MODE_ASK:-}"
[[ -z "$policy" && -f "$STATE_DIR/ask" ]] && policy=$(<"$STATE_DIR/ask")
if [[ -z "$policy" ]]; then (( on_exp )) && policy=recommended || policy=off; fi
[[ "$policy" == recommended || "$policy" == first ]] || exit 0

tool_input=$(print -r -- "$input" | jq -c '.tool_input // empty' 2>/dev/null)
[[ -n "$tool_input" ]] || exit 0

# One answer per question: the option labelled "(Recommended)" (all of them for multiSelect), else the first option.
answers=$(print -r -- "$tool_input" | jq -c --arg policy "$policy" '
  (.questions // [])
  | map(
      (.options // [] | map(.label)) as $labels
      | ($labels | map(select(test("\\(Recommended\\)"; "i")))) as $rec
      | { key: .question,
          value: (if $policy == "recommended" and ($rec | length) > 0
                  then (if (.multiSelect // false) then ($rec | join(", ")) else $rec[0] end)
                  else ($labels[0] // "") end) }
    )
  | from_entries' 2>/dev/null)
[[ -n "$answers" && "$answers" != "{}" && "$answers" != "null" ]] || exit 0

note="auto-mode answered AskUserQuestion with the ${policy} option (no human is available). These are not human decisions; say so in your commit message."
lines=$(print -r -- "$answers" | jq -r 'to_entries | map("- " + .key + " -> " + .value) | join("\n")')

mkdir -p "$STATE_DIR" 2>/dev/null && \
  jq -nc --arg ts "$(date -u +%FT%TZ)" --arg s "$session" --arg c "$cwd" --arg p "$policy" --argjson a "$answers" \
    '{ts: $ts, session: $s, cwd: $c, policy: $p, answers: $a}' >> "$STATE_DIR/ask-log.jsonl" 2>/dev/null

if [[ "${AUTO_MODE_ASK_MODE:-answers}" == "deny" ]]; then
  reason="$note Treat the answers as:
$lines
Proceed on that basis and do not ask these questions again."
  jq -n --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
else
  jq -n --argjson input "$tool_input" --argjson ans "$answers" --arg n "$note" --arg l "$lines" '{
    systemMessage: $n,
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "allow",
      permissionDecisionReason: ($n + "\n" + $l),
      updatedInput: ($input + {answers: $ans}),
      additionalContext: $n
    }
  }'
fi
