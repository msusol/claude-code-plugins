#!/usr/bin/env zsh
# PreToolUse hook — intercepts git commit/push/tag in Bash tool calls.
# Exit 2 blocks the tool and surfaces the message to Claude.
#
# Bypass: a command that begins with `GIT_GUARD_SANCTIONED=1 ` is treated
# as originating from the /commit skill (the sanctioned, audited path).
# The skill prepends that env-var sentinel to every git write so this
# hook stays out of the way during the confirmed workflow. The sentinel
# is intentionally visible in the command string the operator sees —
# any bypass shows up in the Bash command rendered for confirmation.

input=$(cat)

if command -v jq &>/dev/null; then
  cmd=$(echo "$input" | jq -r '.tool_input.command // ""')
else
  cmd=$(echo "$input" | grep -o '"command":"[^"]*"' | sed 's/"command":"//;s/"$//')
fi

# Sanctioned-path bypass — let the skill through.
if echo "$cmd" | grep -qE '^[[:space:]]*GIT_GUARD_SANCTIONED=1[[:space:]]+'; then
  exit 0
fi

if echo "$cmd" | grep -qE 'git[[:space:]]+(commit|push|tag)\b'; then
  echo "git-guard: git write operation intercepted by PreToolUse hook." >&2
  echo "Do NOT attempt this git command directly." >&2
  echo "Use the /commit skill — it verifies the remote allowlist, collects attribution, and requires explicit confirmation before executing." >&2
  exit 2
fi

exit 0