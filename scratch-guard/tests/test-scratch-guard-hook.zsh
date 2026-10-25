#!/usr/bin/env zsh
# Unit tests for scratch-guard-hook.zsh. Run directly: zsh tests/test-scratch-guard-hook.zsh

set -uo pipefail

SCRIPT_DIR="${0:A:h}"
HOOK="$SCRIPT_DIR/../src/scratch-guard-hook.zsh"

pass=0
fail=0

_json_bash() {
  python3 -c "import json,sys; print(json.dumps({'tool_name':'Bash','tool_input':{'command':sys.argv[1]}}))" "$1"
}

_json_write() {
  python3 -c "import json,sys; print(json.dumps({'tool_name':'Write','tool_input':{'file_path':sys.argv[1],'content':sys.argv[2]}}))" "$1" "$2"
}

_assert() {
  local desc="$1" expected_exit="$2" input="$3"
  local actual_exit
  print -r -- "$input" | "$HOOK" >/dev/null 2>&1
  actual_exit=$?
  if [[ "$actual_exit" == "$expected_exit" ]]; then
    echo "  ok   - $desc"
    (( pass++ ))
  else
    echo "  FAIL - $desc (expected exit $expected_exit, got $actual_exit)"
    (( fail++ ))
  fi
}

echo "scratch-guard-hook.zsh tests"

_assert "top-level /tmp .sh heredoc is blocked" 2 \
  "$(_json_bash 'cat > /tmp/test.sh << "EOF"
echo hi
EOF')"

_assert "scratchpad .sh heredoc is allowed" 0 \
  "$(_json_bash 'cat > /private/tmp/claude-502/sess/scratchpad/test.sh << "EOF"
echo hi
EOF')"

_assert "top-level /tmp .txt (dm-pbcopy style) is allowed" 0 \
  "$(_json_bash 'cat > /tmp/dm-foo.txt << "EOF"
hello
EOF')"

_assert "SCRATCH_GUARD_SANCTIONED=1 bypass is allowed" 0 \
  "$(_json_bash 'SCRATCH_GUARD_SANCTIONED=1 cat > /tmp/test.sh << "EOF"
echo hi
EOF')"

_assert "base64 decode-into-exec written to /tmp is blocked" 2 \
  "$(_json_bash 'python3 -c "import base64; exec(base64.b64decode(X).decode())" > /tmp/payload.txt')"

_assert "unrelated bash command is allowed" 0 "$(_json_bash 'ls -la')"

_assert "Write tool to /tmp/foo.sh is blocked" 2 "$(_json_write '/tmp/foo.sh' 'echo hi')"

_assert "Write tool to scratchpad .py is allowed" 0 \
  "$(_json_write '/private/tmp/claude-502/sess/scratchpad/test.py' 'print(1)')"

_assert "Write tool to a real repo path .sh is allowed" 0 \
  "$(_json_write '/Users/example/repo/scripts/foo.sh' 'echo hi')"

echo ""
echo "Passed: $pass  Failed: $fail"
[[ "$fail" -eq 0 ]]
