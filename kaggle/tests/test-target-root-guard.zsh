#!/usr/bin/env zsh
# Tests for kaggle/src/target-root-guard.zsh and how kaggle/deploy.zsh uses it.
# Usage: zsh kaggle/tests/test-target-root-guard.zsh
# Exit 0 = all pass, exit 1 = any failure
#
# These never run deploy.zsh: steps 3 and 4 change ~/.claude (hook, settings, plugin install).

HERE="${0:A:h}"
GUARD="$HERE/../src/target-root-guard.zsh"
DEPLOY="${KAGGLE_DEPLOY_UNDER_TEST:-$HERE/../deploy.zsh}"
pass=0
fail=0

ok()  { printf 'PASS  %s\n' "$1"; (( pass++ )) }
bad() { printf 'FAIL  %s\n' "$1"; (( fail++ )) }

source "$GUARD"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
repo="$tmp/claude-code-plugins"
mkdir -p "$repo/kaggle" "$repo/sub/deeper" "$tmp/claude-code-plugins-other" "$tmp/workspace"
ln -s "$repo/sub" "$tmp/link-into-repo"
ln -s "$tmp/workspace" "$tmp/link-to-workspace"

expect_guarded() {
  if target_is_plugin_repo "$1" "$repo"; then ok "$2"; else bad "$2 (should be guarded)"; fi
}
expect_allowed() {
  if target_is_plugin_repo "$1" "$repo"; then bad "$2 (should be allowed)"; else ok "$2"; fi
}

expect_guarded "$repo"                    "the plugin repo itself is guarded"
expect_guarded "$repo/kaggle"             "a plugin directory inside the repo is guarded"
expect_guarded "$repo/sub/deeper"         "a nested directory inside the repo is guarded"
expect_guarded "$tmp/link-into-repo"      "a symlink that resolves into the repo is guarded"
expect_guarded "$repo/"                   "the repo path with a trailing slash is guarded"
expect_allowed "$tmp/workspace"           "a separate workspace directory is allowed"
expect_allowed "$tmp/claude-code-plugins-other" "a sibling sharing the name prefix is allowed"
expect_allowed "$tmp/link-to-workspace"   "a symlink to a workspace is allowed"
expect_allowed "$tmp"                     "the repo's parent directory is allowed"

# --- how deploy.zsh uses the guard (static: deploy.zsh is never run here) ---------------
line_of() { grep -nF -- "$1" "$DEPLOY" | head -1 | cut -d: -f1 | grep . || print 0 }

sources=$(line_of 'source "$REPO_DIR/src/target-root-guard.zsh"')
decides=$(line_of 'if target_is_plugin_repo "$TARGET_ROOT"')
opens=$(line_of 'if (( ! SKIP_WORKSPACE )); then')
first_write=$(line_of 'mkdir -p "$RULES_DEST"')
closes=$(line_of 'end of the steps that write into the target root')
step3=$(line_of '── 3. Install kaggle-guard')

(( sources > 0 && sources < decides )) && ok "deploy.zsh sources the guard before using it" \
                                        || bad "deploy.zsh sources the guard before using it (source=$sources use=$decides)"
(( decides > 0 && decides < opens )) && ok "the decision is made before the skip block opens" \
                                      || bad "the decision is made before the skip block opens"
(( opens > 0 && opens < first_write )) && ok "the first write into the target root is inside the skip block" \
                                        || bad "the first write into the target root is inside the skip block (opens=$opens write=$first_write)"
(( first_write < closes && closes > 0 && closes < step3 )) && ok "the skip block closes before the global steps" \
                                                            || bad "the skip block closes before the global steps (close=$closes step3=$step3)"

# the CLAUDE.md write (step 2) must also be inside the block
claude_write=$(line_of 'cat > "$TARGET_CLAUDE" <<EOF')
(( opens < claude_write && claude_write < closes )) && ok "the CLAUDE.md write is inside the skip block" \
                                                     || bad "the CLAUDE.md write is inside the skip block"

# the global steps must stay outside the block
hook_install=$(line_of 'cp "$HOOK_SRC" "$HOOK_DEST"')
plugin_install=$(line_of 'claude plugin install kaggle@losus-ai')
(( hook_install > closes && plugin_install > closes )) && ok "hook install and plugin registration stay outside the skip block" \
                                                        || bad "hook install and plugin registration stay outside the skip block"

print ""
printf '%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
