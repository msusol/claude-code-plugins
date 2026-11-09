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

# The push rule must sit under ask, not deny, and an older install's deny entry must move.
_push_rule() {
  python3 -I - "$SETTINGS" "$1" <<'PY'
import json, sys
p = json.load(open(sys.argv[1], encoding="utf-8"))["permissions"]
rule = "Bash(git push*)"
want_ask = sys.argv[2] == "ask"
sys.exit(0 if (rule in p.get("ask", [])) == want_ask and rule not in p.get("deny", []) else 1)
PY
}
_push_rule ask && _ok "install puts the push rule under ask, not deny" || _fail "install puts the push rule under ask, not deny"

python3 -I - "$SETTINGS" <<'PY'
import json, sys
s = json.load(open(sys.argv[1], encoding="utf-8"))
s["permissions"]["ask"].remove("Bash(git push*)")
s["permissions"]["deny"].append("Bash(git push*)")
json.dump(s, open(sys.argv[1], "w", encoding="utf-8"), indent=2, ensure_ascii=False)
PY
_run install
_push_rule ask && _ok "install moves an old deny push rule to ask" || _fail "install moves an old deny push rule to ask"

_run uninstall
_push_rule none && _ok "uninstall removes the push rule" || _fail "uninstall removes the push rule"
_keeps_chars && _ok "uninstall keeps non-ASCII characters" || _fail "uninstall keeps non-ASCII characters"
_unrelated_intact && _ok "uninstall leaves unrelated keys unchanged" || _fail "uninstall leaves unrelated keys unchanged"

echo
echo "Passed: $pass  Failed: $fail"
(( fail == 0 ))
