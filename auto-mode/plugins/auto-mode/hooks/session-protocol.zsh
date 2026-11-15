#!/usr/bin/env zsh
# auto-mode SessionStart hook — tell Claude the stop protocol from turn 1, so a prompt does not have to.
#
# The Stop hook only speaks after Claude's first turn ends, and its continuation message is "carry on with your next
# steps". Without the protocol up front, a model that finished the asked-for work without the marker is sent on to its
# own next steps (after a planning phase, that means implementing). This adds one short piece of context at session start:
# finish with `AUTO-MODE: DONE` and a 2-line summary, or `AUTO-MODE: BLOCKED` when only the owner can decide.
#
# Active when auto-mode is on (flag file ${AUTO_MODE_DIR:-~/.config/auto-mode}/enabled, or the session's cwd is on an
# exp/* branch), unless AUTO_MODE_PROTOCOL=off (or the file $AUTO_MODE_DIR/protocol contains "off").
# It adds context only. It grants no permissions and does not stop anything: git-guard, db-guard and every approval
# prompt still apply. Fails open: no jq or bad input -> exit 0 and nothing is added.

command -v jq &>/dev/null || exit 0

input=$(cat)
STATE_DIR="${AUTO_MODE_DIR:-$HOME/.config/auto-mode}"
cwd=$(print -r -- "$input" | jq -r '.cwd // ""' 2>/dev/null)

enabled=0
[[ -f "$STATE_DIR/enabled" ]] && enabled=1
if (( ! enabled )) && [[ -n "$cwd" && -d "$cwd" ]]; then
  branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
  [[ "$branch" == exp/* ]] && enabled=1
fi
(( enabled )) || exit 0

mode="${AUTO_MODE_PROTOCOL:-}"
[[ -z "$mode" && -f "$STATE_DIR/protocol" ]] && mode=$(<"$STATE_DIR/protocol")
[[ "$mode" == off ]] && exit 0

msg="auto-mode is on for this session, so nobody answers questions step by step: do not ask for confirmation before each step.
Do what you were asked, up to the stopping point that the request or the project rules set (for example a rule that says to stop after writing the documents and report). Reaching that point is finishing: do not carry on past it, and do not widen the task to look for more work.
When you have finished, reply with the single line 'AUTO-MODE: DONE' followed by a 2-line summary.
If you need a decision only the owner can make, or you are blocked, reply with 'AUTO-MODE: BLOCKED' and say exactly what you need.
Do not git push, run destructive or irreversible commands, or bypass any guard or permission prompt."

jq -n --arg m "$msg" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $m}}'
