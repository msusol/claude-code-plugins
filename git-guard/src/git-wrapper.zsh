#!/usr/bin/env zsh
# git-guard — policy wrapper that blocks write ops unless remote is in allowlist.
# Placed in ~/.local/bin/ ahead of the real git in PATH.
# REAL_GIT is substituted by deploy.zsh to the discovered real git binary.

REAL_GIT=__REAL_GIT_PLACEHOLDER__
ALLOWLIST="${GIT_GUARD_ALLOWLIST:-$HOME/.config/git-guard/allowlist}"

_guard_blocked() {
  local remote_url="$1" subcmd="$2"
  local skill="/git-commit"
  [[ "$subcmd" == "push" ]] && skill="/git-push"
  echo "⛔  git-guard: '${remote_url:-no remote}' is not in the allowlist." >&2
  echo "   Edit $ALLOWLIST to approve this repository." >&2
  echo "   Or use the $skill skill for a guided, audited workflow." >&2
  exit 1
}

# Find the real subcommand: git takes global options before it
# (`git -C dir commit`, `git -c k=v push`, `git --git-dir=x tag`). Options that
# take a separate value are skipped with it. The same options are passed to the
# remote lookup below so the allowlist check judges the repo git will act on.
gopts=()
args=("$@")
i=1
while (( i <= $# )); do
  case "${args[i]}" in
    -C|-c|--git-dir|--work-tree|--namespace|--config-env) gopts+=("${args[i]}" "${args[i+1]-}"); (( i += 2 )) ;;
    -*) gopts+=("${args[i]}"); (( i += 1 )) ;;
    *) break ;;
  esac
done
subcmd="${args[i]:-}"

case "$subcmd" in
  commit|push|tag)
    remote_url=$("$REAL_GIT" "${gopts[@]}" remote get-url origin 2>/dev/null || true)

    no_remote_skill="/git-commit"
    [[ "$subcmd" == "push" ]] && no_remote_skill="/git-push"

    if [[ -z "$remote_url" ]]; then
      echo "⛔  git-guard: No remote 'origin' found — cannot verify repository." >&2
      echo "   Add a remote or use the $no_remote_skill skill." >&2
      exit 1
    fi

    if [[ -f "$ALLOWLIST" ]]; then
      while IFS= read -r pattern || [[ -n "$pattern" ]]; do
        [[ -z "$pattern" || "$pattern" == \#* ]] && continue
        if [[ "$remote_url" == *"$pattern"* ]]; then
          exec "$REAL_GIT" "$@"
        fi
      done < "$ALLOWLIST"
    fi

    _guard_blocked "$remote_url" "$subcmd"
    ;;
  *)
    exec "$REAL_GIT" "$@"
    ;;
esac
