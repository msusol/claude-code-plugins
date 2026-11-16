#!/usr/bin/env zsh
# Tests for `run-ab.zsh solve`, with a stubbed `docker` (no containers, no API). The stub plays the container: it makes the
# baseline commit in the mounted folder, then (per $STUBMODE) commits work and prints a report ending in a marker.
# Usage: zsh tests/test-solve.zsh (exit 0 = all pass)

HERE="${0:A:h}/.."
RUN="$HERE/run-ab.zsh"
pass=0; fail=0
T=$(mktemp -d)
export AB_RUNS_DIR="$T/runs" ANTHROPIC_API_KEY=sk-test AB_EXPERIMENTS_DIR="$T/exp" STUBDIR="$T/stub"
mkdir -p "$T/bin" "$STUBDIR" "$T/src"
printf '#!/bin/sh\nexec "%s" "$@"\n' "$(command -p -v git)" > "$T/bin/git"; chmod +x "$T/bin/git"
export PATH="$T/bin:$PATH"

git -C "$T/src" init -q -b main; echo plan > "$T/src/PLAN.md"; git -C "$T/src" add -A
git -C "$T/src" -c user.name=t -c user.email=t@t commit -qm seed
echo "Build the thing. End with AUTO-MODE: DONE." > "$T/brief.md"

cat > "$T/bin/docker" <<'STUB'
#!/bin/bash
case "$1" in
  image) exit 0 ;;
  ps) exit 0 ;;
  rm) exit 0 ;;
  run)
    dir=""; for a in "$@"; do [[ "$a" == *:/work ]] && dir="${a%:/work}"; done
    echo "$*" >> "$STUBDIR/calls"
    G="git -C $dir -c user.name=t -c user.email=t@t"
    $G init -q -b main; $G add -A; $G commit -qm baseline; $G checkout -q -b exp/stub
    case "$STUBMODE" in
      done)    mkdir -p "$dir/docs/plans"; echo "- [x] t" > "$dir/docs/plans/TODO.md"; echo work > "$dir/out.txt"; $G add -A; $G commit -qm "feat: work"; printf 'Built it.\nAUTO-MODE: DONE\n' ;;
      blocked) printf 'I need a decision: A or B?\nAUTO-MODE: BLOCKED\n' ;;
      nomarker) echo work > "$dir/out.txt"; $G add -A; $G commit -qm "feat: work"; printf 'Built it.\n' ;;
      dirty)   echo work > "$dir/out.txt"; $G add -A; $G commit -qm "feat: work"; echo more > "$dir/extra.txt"; printf 'AUTO-MODE: DONE\n' ;;
      mention) echo work > "$dir/out.txt"; $G add -A; $G commit -qm "feat: work"; printf 'Do not end with AUTO-MODE: DONE until tests pass.\nStill working.\nmore\nmore\nmore\nmore\n' ;;
    esac
    exit 0 ;;
esac
STUB
chmod +x "$T/bin/docker"

check() { if [[ "$2" == "$3" ]]; then (( pass++ )); else (( fail++ )); print "FAIL: $1 (got '$2', want '$3')"; fi }
res() { grep "^$2=" "$AB_RUNS_DIR/$1.out/result.txt" | cut -d= -f2-; }

# DONE with a commit and a clean tree: exit 0, a patch that applies to the source ref
STUBMODE=done zsh "$RUN" solve s1 claude-fable-5-2 "$T/src" main "$T/brief.md" >/dev/null 2>&1; rc=$?
check "done exit" "$rc" 0
check "done marker" "$(res s1 marker)" DONE
check "done commits" "$(res s1 commits)" 1
check "done dirty" "$(res s1 dirty)" 0
check "docs files listed" "$(res s1 docs_files)" docs/plans/TODO.md
git clone -q "$T/src" "$T/apply" && git -C "$T/apply" -c user.name=t -c user.email=t@t am -q --3way "$AB_RUNS_DIR/s1.out/solve.patch" 2>/dev/null
check "patch applies to the source" "$(cat "$T/apply/out.txt" 2>/dev/null)" work
check "steps.csv has a solve row" "$(grep -c ',solve,' "$AB_RUNS_DIR/s1.reviews/steps.csv")" 1
check "brief text reached claude -p" "$(grep -c 'Build the thing' "$STUBDIR/calls")" 1
check "docs preamble added" "$(grep -c "docs/ planning rules" "$STUBDIR/calls")" 1
check "bounds passed" "$(grep -c -- '--max-budget-usd 10' "$STUBDIR/calls")" 1

# BLOCKED: exit 3, no patch, the question is in report.txt
STUBMODE=blocked zsh "$RUN" solve s2 claude-fable-5-2 "$T/src" main "$T/brief.md" >/dev/null 2>&1; rc=$?
check "blocked exit" "$rc" 3
check "blocked marker" "$(res s2 marker)" BLOCKED
check "blocked has no patch" "$([[ -e $AB_RUNS_DIR/s2.out/solve.patch ]] && echo yes || echo no)" no

# commits but no marker: exit 4
STUBMODE=nomarker zsh "$RUN" solve s3 claude-fable-5-2 "$T/src" main "$T/brief.md" >/dev/null 2>&1; rc=$?
check "no-marker exit" "$rc" 4
check "no-marker marker" "$(res s3 marker)" NONE

# DONE but uncommitted changes: exit 4
STUBMODE=dirty zsh "$RUN" solve s4 claude-fable-5-2 "$T/src" main "$T/brief.md" >/dev/null 2>&1; rc=$?
check "dirty exit" "$rc" 4
check "dirty flag" "$(res s4 dirty)" 1

# a marker mentioned inside the text, not at the end, does not count
STUBMODE=mention zsh "$RUN" solve s5 claude-fable-5-2 "$T/src" main "$T/brief.md" >/dev/null 2>&1; rc=$?
check "mention marker" "$(res s5 marker)" NONE

# guards
zsh "$RUN" solve s1 claude-fable-5-2 "$T/src" main "$T/brief.md" >/dev/null 2>&1; check "reused name refused" "$?" 1
: > "$T/empty.md"; zsh "$RUN" solve s6 claude-fable-5-2 "$T/src" main "$T/empty.md" >/dev/null 2>&1; check "empty brief refused" "$?" 1
AB_LOGIN=1 zsh "$RUN" solve s7 claude-fable-5-2 "$T/src" main "$T/brief.md" >/dev/null 2>&1; check "login refused" "$?" 1
zsh "$RUN" solve s8 claude-fable-5-2 "$T/src" nope "$T/brief.md" >/dev/null 2>&1; check "bad ref refused" "$?" 1

# AB_SEED_CHECK: a failing check stops the run before export; a passing one lets it through
printf 'exit 1\n' > "$T/bad-check.zsh"; printf 'exit 0\n' > "$T/ok-check.zsh"
STUBMODE=done AB_SEED_CHECK="$T/bad-check.zsh" zsh "$RUN" solve s9 claude-fable-5-2 "$T/src" main "$T/brief.md" >/dev/null 2>&1; check "failing seed check refused" "$?" 1
check "nothing exported on leak" "$([[ -e $AB_RUNS_DIR/s9 ]] && echo yes || echo no)" no
STUBMODE=done AB_SEED_CHECK="$T/ok-check.zsh" zsh "$RUN" solve s10 claude-fable-5-2 "$T/src" main "$T/brief.md" >/dev/null 2>&1; check "passing seed check runs" "$?" 0
STUBMODE=done AB_SEED_CHECK="$T/missing.zsh" zsh "$RUN" solve s11 claude-fable-5-2 "$T/src" main "$T/brief.md" >/dev/null 2>&1; check "missing check script refused" "$?" 1

rm -rf "$T"
print "test-solve: $pass passed, $fail failed"
(( fail == 0 ))
