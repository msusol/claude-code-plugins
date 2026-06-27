#!/usr/bin/env zsh
# PreToolUse hook — intercepts kaggle kernels push in Bash tool calls.
# Exit 2 blocks the tool and surfaces the message to Claude.
#
# Bypass: prepend `KAGGLE_GUARD_SANCTIONED=1 ` to allow a one-time push.
# The sentinel is intentionally visible in the command string shown to the
# operator — any bypass shows up in the Bash command rendered for confirmation.

input=$(cat)

if command -v jq &>/dev/null; then
  cmd=$(echo "$input" | jq -r '.tool_input.command // ""')
else
  cmd=$(echo "$input" | grep -o '"command":"[^"]*"' | sed 's/"command":"//;s/"$//')
fi

# Sanctioned-path bypass
if echo "$cmd" | grep -qE '^[[:space:]]*KAGGLE_GUARD_SANCTIONED=1[[:space:]]+'; then
  exit 0
fi

# Intercept: kaggle kernels push, kaggle kernel push, kaggle k push
if echo "$cmd" | grep -qE 'kaggle[[:space:]]+(kernels?|k)[[:space:]]+push\b'; then
  echo "kaggle-guard: kaggle notebook push intercepted by PreToolUse hook." >&2
  echo "Do NOT push notebooks directly — run the push yourself in the terminal:" >&2
  echo "  ! zsh scripts/push_notebook.sh <slug>" >&2
  echo "  or: ! kaggle kernels push -p <stage-dir>" >&2
  exit 2
fi

exit 0
