#!/usr/bin/env zsh
# Unit tests for src/git-guard-hook.zsh
# Usage: zsh tests/test-git-guard-hook.zsh
# Exit 0 = all pass, exit 1 = any failure

HOOK="${0:A:h}/../src/git-guard-hook.zsh"
pass=0
fail=0

t() {
  local desc="$1" json="$2" want="$3"
  shift 3
  # Remaining args are passed as env KEY=VALUE overrides
  if (( $# )); then
    printf '%s' "$json" | env "$@" zsh "$HOOK" >/dev/null 2>&1
  else
    printf '%s' "$json" | zsh "$HOOK" >/dev/null 2>&1
  fi
  local got=$?
  if (( got == want )); then
    printf 'PASS  %s\n' "$desc"
    (( pass++ ))
  else
    printf 'FAIL  %s — want exit %d, got %d\n' "$desc" "$want" "$got"
    (( fail++ ))
  fi
}

# Build a JSON payload for a command string (no embedded double quotes allowed)
cmd() { printf '{"tool_input":{"command":"%s"}}' "$1"; }

# Build a PATH that hides jq so the hook falls through to its grep/sed fallback.
# Only works when jq lives in a directory dedicated to it (e.g. /opt/local/bin via
# MacPorts). When jq is in a shared system dir like /usr/bin, removing that dir
# would also lose grep/sed/zsh, so the fallback tests are skipped in that case.
_make_nojq_path() {
  local jq_bin jq_dir tmpdir
  jq_bin=$(command -v jq 2>/dev/null) || { echo "$PATH"; echo ""; return; }
  jq_dir="${jq_bin:h}"

  # Skip if jq is in a shared system directory.
  if [[ "$jq_dir" == /usr/bin || "$jq_dir" == /bin ]]; then
    echo "$PATH"
    echo ""
    return
  fi

  tmpdir=$(mktemp -d)
  # Symlink every binary in jq's dir EXCEPT jq, then swap the dir in PATH.
  for f in "$jq_dir"/*(.); do
    [[ "${f:t}" == jq ]] && continue
    ln -sf "$f" "$tmpdir/${f:t}" 2>/dev/null || true
  done

  echo "$PATH" | tr ':' '\n' | sed "s|^${jq_dir}\$|${tmpdir}|" | tr '\n' ':' | sed 's/:$//'
  echo "$tmpdir"  # second line = tmpdir to clean up
}

print "=== blocked: bare git writes"
t "git commit bare"          "$(cmd 'git commit -m test')"      2
t "git push bare"            "$(cmd 'git push')"                2
t "git push with args"       "$(cmd 'git push origin main')"    2
t "git tag"                  "$(cmd 'git tag v1.0')"            2

print "=== allowed: sentinel bypasses hook"
t "sentinel + commit"        "$(cmd 'GIT_GUARD_SANCTIONED=1 git commit -m test')"  0
t "sentinel + push"          "$(cmd 'GIT_GUARD_SANCTIONED=1 git push')"            0
t "sentinel + tag"           "$(cmd 'GIT_GUARD_SANCTIONED=1 git tag v1.0')"        0
t "sentinel with heredoc"    "$(cmd 'GIT_GUARD_SANCTIONED=1 git commit -m "$(cat <<EOF\nfeat: x\nEOF\n)"')" 0

print "=== allowed: sentinel with leading whitespace"
t "one leading space"        "$(cmd ' GIT_GUARD_SANCTIONED=1 git commit -m t')"   0
t "two leading spaces"       "$(cmd '  GIT_GUARD_SANCTIONED=1 git commit -m t')"  0

print "=== allowed: read-only and non-write commands"
t "git status"               "$(cmd 'git status')"              0
t "git add"                  "$(cmd 'git add file.py')"         0
t "git diff"                 "$(cmd 'git diff')"                0
t "git log"                  "$(cmd 'git log --oneline')"       0
t "git branch show-current"  "$(cmd 'git branch --show-current')" 0
t "git remote get-url"       "$(cmd 'git remote get-url origin')" 0
t "non-git bash"             "$(cmd 'ls -la')"                  0
t "python invocation"        "$(cmd 'python3 run.py')"          0

print "=== boundary: malformed / edge inputs"
t "empty command"            '{"tool_input":{"command":""}}'    0
t "missing command key"      '{"tool_input":{}}'                0
t "missing tool_input"       '{}'                               0
t "empty JSON object"        '{}'                               0

print "=== boundary: sentinel without required trailing space"
# Sentinel regex requires at least one space after =1; without it the commit
# check still fires and the call is blocked.
t "sentinel no space"        "$(cmd 'GIT_GUARD_SANCTIONED=1git commit -m x')"     2

print "=== fallback: grep/sed extraction when jq is unavailable"
nojq_info=("${(f)$(_make_nojq_path)}")
nojq_path="${nojq_info[1]}"
nojq_tmpdir="${nojq_info[2]}"

if [[ -n "$nojq_tmpdir" && "$nojq_path" != "$PATH" ]]; then
  t "commit blocked (no jq)"    "$(cmd 'git commit -m test')"                         2  "PATH=$nojq_path"
  t "sentinel passes (no jq)"   "$(cmd 'GIT_GUARD_SANCTIONED=1 git commit -m test')"  0  "PATH=$nojq_path"
  t "git add allowed (no jq)"   "$(cmd 'git add file.py')"                            0  "PATH=$nojq_path"
  t "git status allowed (no jq)" "$(cmd 'git status')"                                0  "PATH=$nojq_path"
  t "git push blocked (no jq)"  "$(cmd 'git push origin main')"                       2  "PATH=$nojq_path"
else
  printf 'SKIP  fallback tests — could not isolate jq from PATH\n'
fi
[[ -n "$nojq_tmpdir" ]] && rm -rf "$nojq_tmpdir"

print ""
printf '%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
