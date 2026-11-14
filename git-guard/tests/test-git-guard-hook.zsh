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

print "=== allowed: sentinel after leading cd prefixes"
t "cd then sentinel push"    "$(cmd 'cd /tmp/repo && GIT_GUARD_SANCTIONED=1 git push')"              0
t "two cds then commit"      "$(cmd 'cd /tmp/a && cd sub && GIT_GUARD_SANCTIONED=1 git commit -m x')" 0
t "cd then sentinel -C push" "$(cmd 'cd /tmp/repo && GIT_GUARD_SANCTIONED=1 git -C . push')"          0

print "=== blocked: sentinel not at the start (only cd may precede it)"
t "cd then bare push"        "$(cmd 'cd /tmp/repo && git push')"                                     2
t "echo then sentinel push"  "$(cmd 'echo hi && GIT_GUARD_SANCTIONED=1 git push')"                   2
t "cd, echo, sentinel push"  "$(cmd 'cd /tmp/repo && echo x && GIT_GUARD_SANCTIONED=1 git push')"    2
t "semicolon then sentinel"  "$(cmd 'cd /tmp/repo; GIT_GUARD_SANCTIONED=1 git push')"                2

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

print "=== blocked: branch names that don't match GitFlow (Lite)"
t "checkout -b no ticket"    "$(cmd 'git checkout -b my-quick-branch')"                       2
t "switch -c underscore"     "$(cmd 'git switch -c bad_name')"                                2
t "branch bare word"         "$(cmd 'git branch weirdname')"                                  2
t "release without patch"    "$(cmd 'git checkout -b release/2.4')"                           2
t "feature missing slug"     "$(cmd 'git checkout -b feature/PROJ-1234')"                       2

print "=== allowed: branch names that match GitFlow (Lite)"
t "feature ticket+slug"      "$(cmd 'git checkout -b feature/PROJ-1234-bulk-export')"                          0
t "feature with start-point" "$(cmd 'git checkout -b feature/PROJ-1234-bulk-export develop')"                  0
t "bugfix via switch"        "$(cmd 'git switch -c bugfix/PROJ-1301-null-pointer-on-save')"                     0
t "chore via branch"         "$(cmd 'git branch chore/PROJ-1310-bump-node-20')"                                 0
t "release semver"           "$(cmd 'git checkout -b release/2.4.0')"                                          0
t "hotfix semver"            "$(cmd 'git checkout -b hotfix/2.3.1')"                                            0
t "checkout existing develop" "$(cmd 'git checkout develop')"                                                   0
t "checkout -b main"         "$(cmd 'git checkout -b main')"                                                    0
t "branch -d not name check" "$(cmd 'git branch -d old-feature')"                                                0
t "branch --show-current"    "$(cmd 'git branch --show-current')"                                                0
t "branch -a not name check" "$(cmd 'git branch -a')"                                                            0
t "branch no args (list)"    "$(cmd 'git branch')"                                                               0
t "sentinel bypasses branch check" "$(cmd 'GIT_GUARD_SANCTIONED=1 git checkout -b my-quick-branch')"            0

# Same as cmd(), plus the hook's cwd (the session's working directory)
cmdc() { printf '{"cwd":"%s","tool_input":{"command":"%s"}}' "$1" "$2"; }

print "=== blocked: global options before the subcommand (git -C dir commit, etc.)"
t "-C dir commit"            "$(cmd 'git -C /tmp/other commit -m x')"           2
t "-C dir push"              "$(cmd 'git -C /tmp/other push')"                  2
t "-C dir tag"               "$(cmd 'git -C /tmp/other tag v1')"                2
t "-c k=v commit"            "$(cmd 'git -c user.name=x commit -m x')"          2
t "two -c then push"         "$(cmd 'git -c a=b -c c=d push origin main')"      2
t "--git-dir= commit"        "$(cmd 'git --git-dir=/tmp/o/.git commit -m x')"   2
t "--git-dir sp commit"      "$(cmd 'git --git-dir /tmp/o/.git commit -m x')"   2
t "--work-tree tag"          "$(cmd 'git --work-tree=/tmp/o tag v1')"           2
t "--no-pager commit"        "$(cmd 'git --no-pager commit -m x')"              2
t "-p commit"                "$(cmd 'git -p commit -m x')"                      2
t "-C then -c then commit"   "$(cmd 'git -C /tmp/o -c k=v commit -m x')"        2
t "add && -C commit"         "$(cmd 'git add -A && git -C /tmp/o commit -m x')" 2

print "=== allowed: global options with read-only subcommands, or the sentinel"
t "-C dir status"            "$(cmd 'git -C /tmp/other status')"                0
t "-C dir log"               "$(cmd 'git -C /tmp/other log --oneline')"         0
t "-C dir add"               "$(cmd 'git -C /tmp/other add file.py')"           0
t "-c k=v diff"              "$(cmd 'git -c color.ui=never diff')"              0
t "sentinel -C commit"       "$(cmd 'GIT_GUARD_SANCTIONED=1 git -C /tmp/o commit -m x')" 0
t "log --grep=commit"        "$(cmd 'git log --grep=commit')"                   0

print "=== aliases: definitions are blocked, existing aliases are resolved"
alias_repo=$(mktemp -d); git -C "$alias_repo" init -q
git -C "$alias_repo" config alias.ci commit
git -C "$alias_repo" config alias.pu push
git -C "$alias_repo" config alias.tg tag
git -C "$alias_repo" config alias.lg 'log --oneline'
git -C "$alias_repo" config alias.sh '!git commit -am'
git -C "$alias_repo" config alias.sx '!echo hi'
git -C "$alias_repo" config alias.cx '-c core.abbrev=8 commit'
t "inline -c alias.x=commit"     "$(cmd 'git -c alias.ci=commit ci -m x')"                  2
t "inline -c Alias (case)"       "$(cmd 'git -c Alias.ci=commit ci -m x')"                  2
t "inline -c alias, push"        "$(cmd 'git -c alias.p=push p')"                           2
t "--config-env alias"           "$(cmd 'git --config-env=alias.ci=VAR ci -m x')"           2
t "git config alias write"       "$(cmd 'git config alias.ci commit')"                      2
t "git config --global alias"    "$(cmd 'git config --global alias.ci commit')"             2
t "env GIT_CONFIG_KEY alias"     "$(cmd 'GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=alias.ci GIT_CONFIG_VALUE_0=commit git ci')" 2
t "env GIT_CONFIG_PARAMETERS"    "$(cmd 'GIT_CONFIG_PARAMETERS=alias.ci=commit git ci -m x')" 2
t "sentinel + inline alias"      "$(cmd 'GIT_GUARD_SANCTIONED=1 git -c alias.ci=commit ci -m x')" 0
t "config --get alias is a read" "$(cmd 'git config --get alias.ci')"                       0
t "config --list is a read"      "$(cmd 'git config --list')"                               0
t "config user.name untouched"   "$(cmd 'git config user.name')"                            0
t "alias ci -> commit"           "$(cmdc "$alias_repo" 'git ci -m x')"                      2
t "alias pu -> push"             "$(cmdc "$alias_repo" 'git pu')"                           2
t "alias tg -> tag"              "$(cmdc "$alias_repo" 'git tg v1')"                        2
t "alias cx (-c opt) -> commit"  "$(cmdc "$alias_repo" 'git cx -m x')"                      2
t "shell alias sh -> commit"     "$(cmdc "$alias_repo" 'git sh x')"                         2
t "alias with global opts"       "$(cmdc "$alias_repo" 'git -c a=b ci -m x')"               2
t "alias lg (log) allowed"       "$(cmdc "$alias_repo" 'git lg')"                           0
t "harmless shell alias sx"      "$(cmdc "$alias_repo" 'git sx')"                           0
t "alias name as plain text"     "$(cmdc "$alias_repo" 'echo ci pu')"                       0
t "alias: no cwd, no aliases"    "$(cmd 'git ci -m x')"                                     0
exp_alias=$(mktemp -d); git -C "$exp_alias" init -q -b exp/x 2>/dev/null || { git -C "$exp_alias" init -q; git -C "$exp_alias" checkout -q -b exp/x; }
git -C "$exp_alias" config alias.ci commit; git -C "$exp_alias" config alias.tg tag; git -C "$exp_alias" config alias.pu push
t "exp: alias ci -> commit ok"   "$(cmdc "$exp_alias" 'git ci -m x')"                       0
t "exp: alias tg still blocked"  "$(cmdc "$exp_alias" 'git tg v1')"                         2
t "exp: alias pu still blocked"  "$(cmdc "$exp_alias" 'git pu')"                            2
rm -rf "$alias_repo" "$exp_alias"

print "=== exp/* branches: plain git commit allowed, everything else still guarded"
exp_repo=$(mktemp -d); main_repo=$(mktemp -d)
git -C "$exp_repo" init -q -b exp/sonnet-vs-fable 2>/dev/null || { git -C "$exp_repo" init -q && git -C "$exp_repo" checkout -q -b exp/sonnet-vs-fable; }
git -C "$main_repo" init -q -b main 2>/dev/null || git -C "$main_repo" init -q
t "exp: commit allowed"          "$(cmdc "$exp_repo" 'git commit -m wip')"                    0
t "exp: add && commit allowed"   "$(cmdc "$exp_repo" 'git add -A && git commit -m wip')"      0
t "exp: push still blocked"      "$(cmdc "$exp_repo" 'git push')"                            2
t "exp: commit && push blocked"  "$(cmdc "$exp_repo" 'git commit -m wip && git push')"       2
t "exp: tag still blocked"       "$(cmdc "$exp_repo" 'git tag v1')"                          2
t "exp: cd elsewhere blocked"    "$(cmdc "$exp_repo" 'cd /tmp/other && git commit -m wip')"  2
t "exp: --git-dir blocked"       "$(cmdc "$exp_repo" 'git --git-dir=/tmp/o/.git commit -m w')" 2
t "exp: git -C blocked"          "$(cmdc "$exp_repo" 'git -C /tmp/other commit -m wip')"     2
t "exp: -c k=v commit allowed"   "$(cmdc "$exp_repo" 'git -c user.name=x commit -m wip')"     0
t "exp: commit -C HEAD allowed"  "$(cmdc "$exp_repo" 'git commit -C HEAD')"                  0
t "main: commit blocked"         "$(cmdc "$main_repo" 'git commit -m wip')"                  2
t "no cwd: commit blocked"       "$(cmd 'git commit -m wip')"                                2
t "bad cwd: commit blocked"      "$(cmdc /nonexistent/dir 'git commit -m wip')"              2
t "exp: branch name allowed"     "$(cmd 'git checkout -b exp/sonnet-vs-fable')"              0
t "exp: bad slug blocked"        "$(cmd 'git checkout -b exp/Bad_Name')"                     2
t "exp: worktree add -b name"    "$(cmd 'git branch exp/fable-run')"                         0
rm -rf "$exp_repo" "$main_repo"

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
