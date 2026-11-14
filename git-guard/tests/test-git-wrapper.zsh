#!/usr/bin/env zsh
# Tests for src/git-wrapper.zsh (the PATH shim that checks the remote allowlist)
# Usage: zsh tests/test-git-wrapper.zsh   (exit 0 = all pass)

SRC="${0:A:h}/../src/git-wrapper.zsh"
REAL=$(command -v -p git)
pass=0; fail=0

work=$(mktemp -d)
sed "s|__REAL_GIT_PLACEHOLDER__|$REAL|" "$SRC" > "$work/git"; chmod +x "$work/git"
repo="$work/repo"; other="$work/other"
for r in "$repo" "$other"; do
  "$REAL" init -q "$r"
  "$REAL" -C "$r" remote add origin "https://example.com/approved/$r:t"
done
"$REAL" -C "$other" remote set-url origin "https://example.com/blocked/other"
echo "example.com/approved" > "$work/allow"
export GIT_GUARD_ALLOWLIST="$work/allow" GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

t() {  # desc, want-exit, args...   (runs the wrapper from $work, i.e. outside both repos)
  local desc="$1" want="$2"; shift 2
  (cd "$work" && "$work/git" "$@") >/dev/null 2>&1
  local got=$?
  if (( got == want )); then printf 'PASS  %s\n' "$desc"; (( pass++ ))
  else printf 'FAIL  %s — want exit %d, got %d\n' "$desc" "$want" "$got"; (( fail++ )); fi
}
tin() {  # like t, but runs inside $1
  local dir="$1" desc="$2" want="$3"; shift 3
  (cd "$dir" && "$work/git" "$@") >/dev/null 2>&1
  local got=$?
  if (( got == want )); then printf 'PASS  %s\n' "$desc"; (( pass++ ))
  else printf 'FAIL  %s — want exit %d, got %d\n' "$desc" "$want" "$got"; (( fail++ )); fi
}

print "=== allowlisted repo"
tin "$repo"  "commit allowed"                  0 commit --allow-empty -m a
t           "-C approved: commit allowed"      0 -C "$repo" commit --allow-empty -m b
t           "-C approved + -c: commit allowed" 0 -C "$repo" -c core.abbrev=8 commit --allow-empty -m c

print "=== repo outside the allowlist"
tin "$other" "commit blocked"                  1 commit --allow-empty -m a
t           "-C blocked: commit blocked"       1 -C "$other" commit --allow-empty -m b
t           "-C blocked: push blocked"         1 -C "$other" push
t           "-C blocked: tag blocked"          1 -C "$other" tag v1
t           "-c k=v then -C blocked: commit"   1 -c core.abbrev=8 -C "$other" commit --allow-empty -m c
t           "--git-dir= blocked: commit"       1 --git-dir="$other/.git" commit --allow-empty -m d
t           "--git-dir sp blocked: commit"     1 --git-dir "$other/.git" commit --allow-empty -m e
t           "--no-pager blocked: commit"       1 --no-pager -C "$other" commit --allow-empty -m f

print "=== the allowlist follows -C, not the cwd"
tin "$repo"  "cwd approved, -C blocked: blocked" 1 -C "$other" commit --allow-empty -m g
tin "$other" "cwd blocked, -C approved: allowed" 0 -C "$repo" commit --allow-empty -m h

print "=== read-only and other commands pass through"
t "-C blocked: status"        0 -C "$other" status
t "-C blocked: rev-parse"     0 -C "$other" rev-parse --git-dir
t "version"                   0 --version
t "no args (prints usage)"    1

rm -rf "$work"
print ""; printf '%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
