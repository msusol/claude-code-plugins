#!/usr/bin/env zsh
# PreToolUse hook — intercepts git commit/push/tag, and non-conforming
# branch-creation names, in Bash tool calls.
# Exit 2 blocks the tool and surfaces the message to Claude.
#
# Bypass: a command that begins with `GIT_GUARD_SANCTIONED=1 ` is treated
# as originating from the git-commit or git-push skill (the sanctioned,
# audited path), or as a deliberate, explained override of the branch-naming
# check. Both skills prepend that env-var sentinel to every git write so
# this hook stays out of the way during the confirmed workflow.
# The sentinel is intentionally visible in the command string the operator
# sees — any bypass shows up in the Bash command rendered for confirmation.

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

if echo "$cmd" | grep -qE 'git[[:space:]]+push\b'; then
  echo "git-guard: git write operation intercepted by PreToolUse hook." >&2
  echo "Do NOT attempt this git command directly." >&2
  echo "Use the /git-push skill — it verifies the remote allowlist and requires explicit confirmation for this specific push." >&2
  exit 2
fi

if echo "$cmd" | grep -qE 'git[[:space:]]+(commit|tag)\b'; then
  echo "git-guard: git write operation intercepted by PreToolUse hook." >&2
  echo "Do NOT attempt this git command directly." >&2
  echo "Use the /git-commit skill — it verifies the remote allowlist, collects attribution, and requires explicit confirmation before executing." >&2
  exit 2
fi

# --- Branch naming convention (GitFlow Lite) ---
# Extract a candidate branch name from a creation command. Each pattern
# below matches exactly one token after the flag/keyword, so a start-point
# argument (e.g. `checkout -b <name> <start-point>`) or a rename's second
# argument is never mistaken for the name.
branch_name=""
match=$(echo "$cmd" | grep -oE '(checkout[[:space:]]+-[bB]|switch[[:space:]]+-[cC])[[:space:]]+[^&|;[:space:]]+' | head -1)
if [[ -n "$match" ]]; then
  branch_name="${match##* }"
else
  match=$(echo "$cmd" | grep -oE 'branch[[:space:]]+[^&|;[:space:]-][^&|;[:space:]]*' | head -1)
  if [[ -n "$match" ]]; then
    branch_name="${match##* }"
  fi
fi

if [[ -n "$branch_name" && "$branch_name" != "main" && "$branch_name" != "develop" ]]; then
  if ! echo "$branch_name" | grep -qE '^(feature|bugfix|chore)/[A-Z][A-Z0-9]+-[0-9]+-[a-z0-9]+(-[a-z0-9]+)*$' \
     && ! echo "$branch_name" | grep -qE '^(release|hotfix)/[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "git-guard: branch name '$branch_name' doesn't match the GitFlow (Lite) naming convention." >&2
    echo "  feature/<TICKET>-<slug>      e.g. feature/PROJ-1234-bulk-export" >&2
    echo "  bugfix/<TICKET>-<slug>       e.g. bugfix/PROJ-1301-null-pointer-on-save" >&2
    echo "  chore/<TICKET>-<slug>        e.g. chore/PROJ-1310-bump-node-20" >&2
    echo "  release/<major.minor.patch>  e.g. release/2.4.0" >&2
    echo "  hotfix/<major.minor.patch>   e.g. hotfix/2.3.1" >&2
    echo "See the git-branch-naming rule for the full GitFlow (Lite) convention." >&2
    echo "Deliberate, explained exception: prefix with GIT_GUARD_SANCTIONED=1." >&2
    exit 2
  fi
fi

exit 0