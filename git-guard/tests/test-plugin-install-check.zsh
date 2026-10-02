#!/usr/bin/env zsh
# Tests for git-guard/src/plugin-install-check.zsh and how git-guard/deploy.zsh uses it.
# Usage: zsh git-guard/tests/test-plugin-install-check.zsh
# Exit 0 = all pass, exit 1 = any failure
#
# The end-to-end part runs the real deploy.zsh, but against a throwaway HOME with a fake `claude`
# on PATH, so nothing in your real ~/.claude, ~/.local or ~/.config is touched and no plugin is
# really installed or removed.

HERE="${0:A:h}"
HELPER="$HERE/../src/plugin-install-check.zsh"
DEPLOY="${GIT_GUARD_DEPLOY_UNDER_TEST:-$HERE/../deploy.zsh}"
pass=0
fail=0

ok()  { printf 'PASS  %s\n' "$1"; (( pass++ )) }
bad() { printf 'FAIL  %s\n' "$1"; (( fail++ )) }

source "$HELPER"

# state_is DESCRIPTION EXPECTED INPUT
state_is() {
  local got
  got="$(print -r -- "$3" | plugin_install_state git-guard losus-ai)"
  if [[ "$got" == "$2" ]]; then ok "$1"; else bad "$1 (want '$2', got '$got')"; fi
}

LIST_BASE=$'Installed plugins:\n\n  ❯ db-guard@losus-ai\n    Version: 1.0.0\n    Status: ✔ enabled\n\n  ❯ docs@losus-ai\n    Version: 1.0.0\n'

state_is "git-guard@losus-ai alone is present" present \
  "$LIST_BASE"$'\n  ❯ git-guard@losus-ai\n    Version: 1.2.0\n'
state_is "git-guard@msusol alone is NOT present (the bug)" "other:msusol" \
  "$LIST_BASE"$'\n  ❯ git-guard@msusol\n    Version: 1.0.0\n'
state_is "both copies are reported" "present,other:msusol" \
  "$LIST_BASE"$'\n  ❯ git-guard@losus-ai\n  ❯ git-guard@msusol\n'
state_is "several other marketplaces are listed once each, sorted by first sight" "other:msusol,legacy" \
  "$LIST_BASE"$'\n  ❯ git-guard@msusol\n  ❯ git-guard@legacy\n  ❯ git-guard@msusol\n'
state_is "no git-guard at all is absent" absent "$LIST_BASE"
state_is "empty output is absent" absent ""
state_is "git-guard-extras@losus-ai is not git-guard" absent \
  "$LIST_BASE"$'\n  ❯ git-guard-extras@losus-ai\n'
state_is "xgit-guard@losus-ai is not git-guard" absent \
  "$LIST_BASE"$'\n  ❯ xgit-guard@losus-ai\n'
state_is "the bare word git-guard without a marketplace is not a match" absent \
  "$LIST_BASE"$'\nInstalled git-guard earlier\n'

# --- end to end: run the real deploy.zsh in a sandbox ---------------------------------
root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT

# A fake claude: logs every call; `plugin list` prints $FAKE_LIST; `marketplace list` says losus-ai exists.
mkdir -p "$root/bin"
cat > "$root/bin/claude" <<'EOF'
#!/usr/bin/env zsh
print -r -- "$*" >> "$FAKE_CLAUDE_LOG"
case "$1 $2" in
  "plugin marketplace") [[ "$3" == "list" ]] && print "losus-ai" ;;
  "plugin list") cat "$FAKE_LIST" ;;
esac
exit 0
EOF
chmod +x "$root/bin/claude"

# run_deploy NAME LISTFILE-CONTENT  -> sets $deploy_out and $deploy_log
run_deploy() {
  local name="$1" list_content="$2"
  local home="$root/$name-home"
  mkdir -p "$home"
  print -r -- "$list_content" > "$root/$name.list"
  : > "$root/$name.log"
  deploy_out="$(HOME="$home" PATH="$root/bin:$PATH" FAKE_LIST="$root/$name.list" FAKE_CLAUDE_LOG="$root/$name.log" \
                zsh "$DEPLOY" 2>&1)"
  deploy_status=$?
  deploy_log="$(cat "$root/$name.log")"
}

installed_called() { print -r -- "$deploy_log" | grep -qF "plugin install git-guard@losus-ai" }

run_deploy stale "$LIST_BASE"$'\n  ❯ git-guard@msusol\n    Version: 1.0.0\n'
(( deploy_status == 0 )) && ok "deploy.zsh exits 0 with only a stale git-guard@msusol" \
                          || bad "deploy.zsh exits 0 with only a stale git-guard@msusol (status $deploy_status)"
print -r -- "$deploy_out" | grep -q "git-guard is installed from: msusol" \
  && ok "deploy.zsh says git-guard comes from msusol, not losus-ai" || bad "deploy.zsh says git-guard comes from msusol, not losus-ai"
print -r -- "$deploy_out" | grep -qF "claude plugin uninstall git-guard@msusol" \
  && ok "deploy.zsh prints the uninstall command for the stale copy" || bad "deploy.zsh prints the uninstall command for the stale copy"
installed_called && bad "deploy.zsh must not install over a stale copy unasked" \
                 || ok "deploy.zsh leaves a stale copy alone (no install call)"

run_deploy current "$LIST_BASE"$'\n  ❯ git-guard@losus-ai\n    Version: 1.2.0\n'
print -r -- "$deploy_out" | grep -qF "Plugin 'git-guard@losus-ai' already installed" \
  && ok "deploy.zsh reports git-guard@losus-ai already installed" || bad "deploy.zsh reports git-guard@losus-ai already installed"
installed_called && bad "deploy.zsh must not reinstall a current copy" || ok "deploy.zsh does not reinstall a current copy"

run_deploy both "$LIST_BASE"$'\n  ❯ git-guard@losus-ai\n  ❯ git-guard@msusol\n'
print -r -- "$deploy_out" | grep -q "ALSO installed from: msusol" \
  && ok "deploy.zsh warns about the duplicate copy" || bad "deploy.zsh warns about the duplicate copy"
installed_called && bad "deploy.zsh must not install when losus-ai is present" || ok "deploy.zsh does not install when losus-ai is present"

run_deploy fresh "$LIST_BASE"
installed_called && ok "deploy.zsh installs git-guard@losus-ai when git-guard is absent" \
                 || bad "deploy.zsh installs git-guard@losus-ai when git-guard is absent"

# --- static: the name-only check is gone -------------------------------------------------
grep -qF 'grep -qw "git-guard"' "$DEPLOY" && bad "deploy.zsh no longer matches the bare name git-guard" \
                                          || ok "deploy.zsh no longer matches the bare name git-guard"
grep -qF 'source "$SCRIPT_DIR/src/plugin-install-check.zsh"' "$DEPLOY" \
  && ok "deploy.zsh sources the install check" || bad "deploy.zsh sources the install check"

print ""
printf '%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
