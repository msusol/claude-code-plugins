#!/usr/bin/env zsh
# Tests that scripts/manage-settings.py keeps existing non-ASCII text in ~/.claude/settings.json
# instead of rewriting it as \uXXXX escapes. Uses a throwaway HOME; the real settings file is never touched.
# Run directly: zsh tests/test-manage-settings.zsh

set -uo pipefail

SCRIPT_DIR="${0:A:h}"
MANAGE="$SCRIPT_DIR/../scripts/manage-settings.py"

pass=0
fail=0

_ok()   { echo "  ok   - $1"; pass=$(( pass + 1 )); }
_fail() { echo "  FAIL - $1"; fail=$(( fail + 1 )); }

FAKE_HOME="$(mktemp -d)"
trap 'rm -r "$FAKE_HOME"' EXIT
mkdir -p "$FAKE_HOME/.claude"
SETTINGS="$FAKE_HOME/.claude/settings.json"

# A settings file with non-ASCII text (em dash, multiplication sign) and keys the installer does not own.
python3 -I - "$SETTINGS" <<'PY'
import json, sys
settings = {
    "model": "example",
    "permissions": {"allow": ["Bash(ls:*)"], "note": "dash — and times ×"},
}
with open(sys.argv[1], "w", encoding="utf-8") as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
PY

_run() { HOME="$FAKE_HOME" python3 "$MANAGE" "$1" >/dev/null 2>&1; }

# True when the file holds the literal characters and no \u escapes.
_keeps_chars() {
  grep -q '—' "$SETTINGS" && grep -q '×' "$SETTINGS" && ! grep -q '\\u' "$SETTINGS"
}

# True when keys the installer does not own are unchanged.
_unrelated_intact() {
  python3 -I - "$SETTINGS" <<'PY'
import json, sys
s = json.load(open(sys.argv[1], encoding="utf-8"))
ok = (
    s.get("model") == "example"
    and s["permissions"]["allow"] == ["Bash(ls:*)"]
    and s["permissions"]["note"] == "dash — and times ×"
)
sys.exit(0 if ok else 1)
PY
}

echo "manage-settings.py tests (${${SCRIPT_DIR:h}:t})"

_run install
_keeps_chars && _ok "install keeps non-ASCII characters" || _fail "install keeps non-ASCII characters"
_unrelated_intact && _ok "install leaves unrelated keys unchanged" || _fail "install leaves unrelated keys unchanged"

cp "$SETTINGS" "$FAKE_HOME/after-first-install.json"
_run install
cmp -s "$SETTINGS" "$FAKE_HOME/after-first-install.json" \
  && _ok "second install is byte-identical" || _fail "second install is byte-identical"

_run uninstall
_keeps_chars && _ok "uninstall keeps non-ASCII characters" || _fail "uninstall keeps non-ASCII characters"
_unrelated_intact && _ok "uninstall leaves unrelated keys unchanged" || _fail "uninstall leaves unrelated keys unchanged"

echo
echo "Passed: $pass  Failed: $fail"
(( fail == 0 ))
