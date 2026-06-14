#!/usr/bin/env zsh
# git-guard — policy wrapper that blocks write ops unless remote is in allowlist.
# Placed in ~/.local/bin/ ahead of the real git in PATH.
# REAL_GIT is substituted by deploy.zsh to the discovered real git binary.

REAL_GIT=__REAL_GIT_PLACEHOLDER__
ALLOWLIST="${GIT_GUARD_ALLOWLIST:-$HOME/.config/git-guard/allowlist}"

_guard_blocked() {
  local remote_url="$1"
  echo "⛔  git-guard: '${remote_url:-no remote}' is not in the allowlist." >&2
  echo "   Edit $ALLOWLIST to approve this repository." >&2
  echo "   Or use the /commit skill for a guided, audited commit workflow." >&2
  exit 1
}

case "${1:-}" in
  commit|push|tag)
    remote_url=$("$REAL_GIT" remote get-url origin 2>/dev/null || true)

    if [[ -z "$remote_url" ]]; then
      echo "⛔  git-guard: No remote 'origin' found — cannot verify repository." >&2
      echo "   Add a remote or use the /commit skill." >&2
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

    _guard_blocked "$remote_url"
    ;;
  *)
    exec "$REAL_GIT" "$@"
    ;;
esac
