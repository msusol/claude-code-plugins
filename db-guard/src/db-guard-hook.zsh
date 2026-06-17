#!/usr/bin/env zsh
# PreToolUse hook — intercepts destructive SQL in Bash tool calls.
# Exit 2 blocks the tool and surfaces the message to Claude.
#
# Bypass: a command that begins with `DB_GUARD_SANCTIONED=1 ` is treated
# as originating from the db-guard investigation-first workflow (the sanctioned,
# confirmed path). The sentinel is intentionally visible in the command string
# shown to the user before any write — that visibility is the audit signal.
#
# This hook intercepts patterns that are visible in the Bash command string
# (e.g. psql -c "DROP TABLE ..."). SQL executed from inside Python scripts
# is not caught here — ~/.cline/rules/dbguard-destructive-ops.md is the
# enforcement layer for those cases.

input=$(cat)

if command -v jq &>/dev/null; then
  cmd=$(echo "$input" | jq -r '.tool_input.command // ""')
else
  cmd=$(echo "$input" | grep -o '"command":"[^"]*"' | sed 's/"command":"//;s/"$//')
fi

# Sanctioned-path bypass — investigation-first workflow completed, user confirmed.
if echo "$cmd" | grep -qE '^[[:space:]]*DB_GUARD_SANCTIONED=1[[:space:]]+'; then
  exit 0
fi

# Intercept destructive SQL patterns.
# Matches: DROP TABLE, DROP DATABASE, DROP SCHEMA, TRUNCATE, ALTER TABLE … DROP COLUMN
if echo "$cmd" | grep -qiE \
  '(DROP[[:space:]]+TABLE|DROP[[:space:]]+DATABASE|DROP[[:space:]]+SCHEMA|TRUNCATE[[:space:]]+(TABLE[[:space:]]+)?[a-zA-Z_]|ALTER[[:space:]]+TABLE[^;|]+DROP[[:space:]]+COLUMN)'; then
  echo "db-guard: destructive SQL intercepted by PreToolUse hook." >&2
  echo "" >&2
  echo "Do NOT run DROP TABLE, TRUNCATE, DROP DATABASE, DROP SCHEMA, or DROP COLUMN directly." >&2
  echo "Follow the db-guard investigation-first workflow (~/.cline/rules/dbguard-destructive-ops.md):" >&2
  echo "" >&2
  echo "  1. Count and sample the target table" >&2
  echo "  2. Audit schema, foreign keys, views, and indexes that depend on it" >&2
  echo "  3. State explicitly what is irreversibly lost" >&2
  echo "  4. Present findings to the user and wait for explicit confirmation" >&2
  echo "  5. Prepend DB_GUARD_SANCTIONED=1 to the command once confirmed" >&2
  exit 2
fi

exit 0
