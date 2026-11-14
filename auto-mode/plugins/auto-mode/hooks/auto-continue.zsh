#!/usr/bin/env zsh
# auto-mode Stop hook — when Claude finishes a turn, tell it to carry on with
# its own recommended next steps, up to a capped number of continuations.
#
# Enabled when EITHER
#   - the flag file  ${AUTO_MODE_DIR:-~/.config/auto-mode}/enabled  exists, OR
#   - the session's cwd is on an `exp/*` git branch (A/B experiments, spikes).
#
# Stops continuing when
#   - Claude's last message contains `AUTO-MODE: DONE` or `AUTO-MODE: BLOCKED`, OR
#   - the cap is reached (env AUTO_MODE_MAX, or the `max` file, default 8), OR
#   - the user starts a new turn (the counter resets whenever stop_hook_active is false).
#
# This hook only nudges Claude to continue. It grants no permissions: git-guard,
# db-guard, permissions.deny/ask and every approval prompt still apply, and the
# continuation message tells Claude not to push or take irreversible actions.
#
# Fails open: no jq, bad input, or unwritable state dir -> exit 0 (Claude stops normally).

command -v jq &>/dev/null || exit 0

input=$(cat)
STATE_DIR="${AUTO_MODE_DIR:-$HOME/.config/auto-mode}"

cwd=$(print -r -- "$input" | jq -r '.cwd // ""' 2>/dev/null)
session=$(print -r -- "$input" | jq -r '.session_id // "default"' 2>/dev/null)
active=$(print -r -- "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)
session="${session//[^A-Za-z0-9_-]/}"
[[ -z "$session" ]] && session=default

enabled=0
[[ -f "$STATE_DIR/enabled" ]] && enabled=1
if (( ! enabled )) && [[ -n "$cwd" && -d "$cwd" ]]; then
  branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
  [[ "$branch" == exp/* ]] && enabled=1
fi
(( enabled )) || exit 0

max="${AUTO_MODE_MAX:-}"
[[ -z "$max" && -f "$STATE_DIR/max" ]] && max=$(<"$STATE_DIR/max")
[[ "$max" == <-> ]] || max=8

mkdir -p "$STATE_DIR/counters" 2>/dev/null || exit 0
counter="$STATE_DIR/counters/$session"

# A fresh turn (the user typed something) resets the budget.
[[ "$active" == "true" ]] || rm -f "$counter"
count=0
[[ -f "$counter" ]] && count=$(<"$counter")
[[ "$count" == <-> ]] || count=0

# Did Claude say it is finished or stuck?
last=$(print -r -- "$input" | jq -r '.last_assistant_message // ""' 2>/dev/null)
if [[ -z "$last" ]]; then
  tpath=$(print -r -- "$input" | jq -r '.transcript_path // ""' 2>/dev/null)
  if [[ -n "$tpath" && -f "$tpath" ]]; then
    last=$(tail -n 60 "$tpath" | jq -rs '
      [ .[] | select(.type == "assistant") ] | last
      | (.message.content // "")
      | if type == "array" then map(select(.type == "text") | .text) | join("\n") else . end
    ' 2>/dev/null)
  fi
fi
if [[ "$last" == *"AUTO-MODE: DONE"* || "$last" == *"AUTO-MODE: BLOCKED"* ]]; then
  rm -f "$counter"
  exit 0
fi

if (( count >= max )); then
  rm -f "$counter"
  jq -n --arg m "auto-mode: stopped after $max automatic continuations (cap reached)." '{systemMessage: $m}'
  exit 0
fi

print -r -- $(( count + 1 )) > "$counter"

reason="auto-mode is on (continuation $(( count + 1 )) of $max). Carry on with the next steps you recommended or would suggest, without asking me first. Keep going until the work is complete.
Do NOT: git push; run destructive or irreversible commands (rm -rf, DROP/TRUNCATE, force-push, resetting history); bypass or work around git-guard, db-guard or any permission prompt; or spend money / call external services you were not already using.
If you are finished, reply with the single line 'AUTO-MODE: DONE' plus a short summary. If you need a decision only I can make, or something is blocked, reply with 'AUTO-MODE: BLOCKED' and say what you need."
jq -n --arg r "$reason" '{decision: "block", reason: $r}'
exit 0
