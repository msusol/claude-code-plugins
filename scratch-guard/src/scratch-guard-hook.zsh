#!/usr/bin/env zsh
# PreToolUse hook — blocks scratch/test scripts from being materialized as
# standalone files in a shared system temp directory (/tmp, /private/tmp,
# /var/folders) outside a Claude Code session's own scratchpad subdirectory.
#
# Why: a scratch test script left at a top-level /tmp path sits outside any
# session sandbox, visible to other users and to endpoint-security tooling
# independently of the agent that wrote it. The risk compounds when the
# script's own content looks obfuscated (a base64-decode-into-exec pattern),
# a textbook malware signature even when the intent is benign (e.g. working
# around nested shell-quoting when building a remote --command string).
#
# This hook does NOT block /tmp entirely — plain, non-executable drafts
# (e.g. the dm-pbcopy workflow's /tmp/<name>.txt files) are a sanctioned,
# everyday use of top-level /tmp and are left alone. It only blocks:
#   1. A script-looking file (.sh/.zsh/.bash/.py/.pl/.rb/.command) written
#      directly under a temp dir, outside .../scratchpad/.
#   2. Any file, anywhere, whose content embeds a base64 decode-into-exec
#      pattern (base64 -d/--decode/b64decode feeding exec/eval/sh -c/
#      bash -c/python3 -c) — the specific shape that reads as obfuscation.
#
# Exit 2 blocks the tool and surfaces the message to Claude.
#
# Bypass: a Bash command that begins with `SCRATCH_GUARD_SANCTIONED=1 ` is
# treated as a deliberate, explained override (mirrors git-guard's sentinel).
# The sentinel is intentionally visible in the command the operator
# confirms — any bypass shows up in the rendered Bash command.

input=$(cat)

if command -v jq &>/dev/null; then
  tool_name=$(print -r -- "$input" | jq -r '.tool_name // ""')
  cmd=$(print -r -- "$input" | jq -r '.tool_input.command // ""')
  write_path=$(print -r -- "$input" | jq -r '.tool_input.file_path // ""')
  write_content=$(print -r -- "$input" | jq -r '.tool_input.content // ""')
else
  tool_name=$(print -r -- "$input" | grep -o '"tool_name":"[^"]*"' | sed 's/"tool_name":"//;s/"$//')
  cmd=$(print -r -- "$input" | grep -o '"command":"[^"]*"' | sed 's/"command":"//;s/"$//')
  write_path=$(print -r -- "$input" | grep -o '"file_path":"[^"]*"' | sed 's/"file_path":"//;s/"$//')
  write_content=""
fi

# Sanctioned-path bypass — Bash only (Write has no shell prefix to carry one).
if [[ "$tool_name" == "Bash" ]] && print -r -- "$cmd" | grep -qE '^[[:space:]]*SCRATCH_GUARD_SANCTIONED=1[[:space:]]+'; then
  exit 0
fi

TEMP_DIR_RE='(^|[[:space:]"'"'"'])(/tmp/|/private/tmp/|/var/folders/)'
SCRATCHPAD_RE='/scratchpad/'
EXEC_EXT_RE='\.(sh|zsh|bash|py|pl|rb|command)([[:space:]"'"'"'<]|$)'
B64_DECODE_RE='base64[^|&;]*(-d\b|--decode\b|b64decode)'
EXEC_SINK_RE='(\bexec\(|\beval\b|\bsh[[:space:]]+-c\b|\bbash[[:space:]]+-c\b|\bzsh[[:space:]]+-c\b|\bpython3?[[:space:]]+-c\b)'

_block() {
  local reason="$1" path="$2"
  echo "scratch-guard: blocked writing a scratch/test file outside the session scratchpad." >&2
  echo "  Path: ${path:-<unknown>}" >&2
  echo "  Reason: $reason" >&2
  echo "Use this session's own scratchpad directory instead (see the Environment" >&2
  echo "block for its exact path — a .../scratchpad/ subdirectory under /tmp or" >&2
  echo "/private/tmp). It is session-isolated and not independently visible to" >&2
  echo "endpoint security the way a bare /tmp/<file> is." >&2
  echo "Deliberate, explained exception (Bash only): prefix with SCRATCH_GUARD_SANCTIONED=1." >&2
  exit 2
}

case "$tool_name" in
  Bash)
    # Find a destination path this command writes to: `> path`, `>> path`,
    # or `tee path`. Only the first match is checked — good enough for the
    # single-destination scratch-script shape this hook targets.
    dest=$(print -r -- "$cmd" | grep -oE '(>>?|tee[[:space:]]+(-a[[:space:]]+)?)[[:space:]]*[^[:space:]|&;<]+' | tail -1 | sed -E 's/^(>>?|tee[[:space:]]+(-a[[:space:]]+)?)[[:space:]]*//')

    if [[ -n "$dest" ]] && print -r -- "$dest" | grep -qE "$TEMP_DIR_RE" && ! print -r -- "$dest" | grep -qE "$SCRATCHPAD_RE"; then
      if print -r -- "$dest" | grep -qE "$EXEC_EXT_RE"; then
        _block "script-looking file written directly to a temp dir, not the session scratchpad" "$dest"
      fi
      if print -r -- "$cmd" | grep -qiE "$B64_DECODE_RE" && print -r -- "$cmd" | grep -qiE "$EXEC_SINK_RE"; then
        _block "base64 decode-into-exec pattern materialized as a file outside the session scratchpad" "$dest"
      fi
    fi
    ;;
  Write)
    if [[ -n "$write_path" ]] && print -r -- "$write_path" | grep -qE "$TEMP_DIR_RE" && ! print -r -- "$write_path" | grep -qE "$SCRATCHPAD_RE"; then
      if print -r -- "$write_path" | grep -qE "$EXEC_EXT_RE"; then
        _block "script-looking file written directly to a temp dir, not the session scratchpad" "$write_path"
      fi
      if [[ -n "$write_content" ]] && print -r -- "$write_content" | grep -qiE "$B64_DECODE_RE" && print -r -- "$write_content" | grep -qiE "$EXEC_SINK_RE"; then
        _block "base64 decode-into-exec pattern materialized as a file outside the session scratchpad" "$write_path"
      fi
    fi
    ;;
esac

exit 0
