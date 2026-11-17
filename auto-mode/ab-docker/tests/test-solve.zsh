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
      recap)   echo work > "$dir/out.txt"; $G add -A; $G commit -qm "feat: work"; printf 'Built it.\nAUTO-MODE: DONE\nRecap line 1.\nRecap line 2.\nRecap line 3.\nRecap line 4.\nRecap line 5.\nRecap line 6.\nRecap line 7.\n' ;;
      first)   echo work > "$dir/out.txt"; $G add -A; $G commit -qm "feat: work"; printf 'AUTO-MODE: DONE\nBuilt it.\nmore\nmore\nmore\nmore\nmore\nmore\n' ;;
      both)    echo work > "$dir/out.txt"; $G add -A; $G commit -qm "feat: work"; printf 'AUTO-MODE: DONE\nBut I need a decision: A or B?\nAUTO-MODE: BLOCKED\n' ;;
      prefix)  echo work > "$dir/out.txt"; $G add -A; $G commit -qm "feat: work"; printf 'AUTO-MODE: DONE until the tests pass.\nStill working.\n' ;;
      period)  echo work > "$dir/out.txt"; $G add -A; $G commit -qm "feat: work"; printf 'Built it.\n  AUTO-MODE: DONE.  \n' ;;
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
check "a run with commits names its patch in result.txt" "$(res s1 patch)" "$AB_RUNS_DIR/s1.out/solve.patch"
check "steps.csv has a solve row" "$(grep -c ',solve,' "$AB_RUNS_DIR/s1.reviews/steps.csv")" 1
check "brief text reached claude -p" "$(grep -c 'Build the thing' "$STUBDIR/calls")" 1
check "docs preamble added" "$(grep -c "docs/ planning rules" "$STUBDIR/calls")" 1
check "bounds passed" "$(grep -c -- '--max-budget-usd 10' "$STUBDIR/calls")" 1

# BLOCKED: exit 3, no patch, the question is in report.txt
STUBMODE=blocked zsh "$RUN" solve s2 claude-fable-5-2 "$T/src" main "$T/brief.md" >/dev/null 2>&1; rc=$?
check "blocked exit" "$rc" 3
check "blocked marker" "$(res s2 marker)" BLOCKED
check "blocked has no patch" "$([[ -e $AB_RUNS_DIR/s2.out/solve.patch ]] && echo yes || echo no)" no
check "and result.txt leaves the patch value empty, not pointing at a missing file" "$(res s2 patch)" ""
check "but keeps the patch key, so a key=value reader still finds it" "$(grep -c '^patch=$' "$AB_RUNS_DIR/s2.out/result.txt")" 1
check "no key=value line points at a file that does not exist" "$(grep -E '^patch=.' "$AB_RUNS_DIR/s2.out/result.txt" | wc -l | tr -d ' ')" 0

# commits but no marker: exit 4
STUBMODE=nomarker zsh "$RUN" solve s3 claude-fable-5-2 "$T/src" main "$T/brief.md" >/dev/null 2>&1; rc=$?
check "no-marker exit" "$rc" 4
check "no-marker marker" "$(res s3 marker)" NONE
check "a run with commits and no marker still names its patch" "$(res s3 patch)" "$AB_RUNS_DIR/s3.out/solve.patch"
check "and that file exists" "$([[ -f $AB_RUNS_DIR/s3.out/solve.patch ]] && echo yes || echo no)" yes

# DONE but uncommitted changes: exit 4
STUBMODE=dirty zsh "$RUN" solve s4 claude-fable-5-2 "$T/src" main "$T/brief.md" >/dev/null 2>&1; rc=$?
check "dirty exit" "$rc" 4
check "dirty flag" "$(res s4 dirty)" 1

# a marker mentioned inside a sentence does not count
STUBMODE=mention zsh "$RUN" solve s5 claude-fable-5-2 "$T/src" main "$T/brief.md" >/dev/null 2>&1; rc=$?
check "mention marker" "$(res s5 marker)" NONE
STUBMODE=prefix zsh "$RUN" solve s5b claude-fable-5-2 "$T/src" main "$T/brief.md" >/dev/null 2>&1; rc=$?
check "marker followed by words on the same line" "$(res s5b marker)" NONE
check "marker followed by words exits 4" "$rc" 4

# the marker is found anywhere as a line of its own: a long recap after it, or it first, or with a trailing period
STUBMODE=recap zsh "$RUN" solve s5c claude-fable-5-2 "$T/src" main "$T/brief.md" >/dev/null 2>&1; rc=$?
check "marker with a 7-line recap after it" "$(res s5c marker)" DONE
check "recap after marker exits 0" "$rc" 0
STUBMODE=first zsh "$RUN" solve s5d claude-fable-5-2 "$T/src" main "$T/brief.md" >/dev/null 2>&1; rc=$?
check "marker as the first line" "$(res s5d marker)" DONE
check "marker first exits 0" "$rc" 0
STUBMODE=period zsh "$RUN" solve s5e claude-fable-5-2 "$T/src" main "$T/brief.md" >/dev/null 2>&1; rc=$?
check "marker with a trailing period and spaces" "$(res s5e marker)" DONE

# both markers: BLOCKED wins, so a question is never lost
STUBMODE=both zsh "$RUN" solve s5f claude-fable-5-2 "$T/src" main "$T/brief.md" >/dev/null 2>&1; rc=$?
check "both markers give BLOCKED" "$(res s5f marker)" BLOCKED
check "both markers exit 3" "$rc" 3

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

# AB_AGENTS_FILE reaches the headless session too, and is logged
print '{"hard-solver":{"description":"d","prompt":"p"}}' > "$T/agents.json"
: > "$STUBDIR/calls"
STUBMODE=done AB_AGENTS_FILE="$T/agents.json" zsh "$RUN" solve s12 claude-fable-5-2 "$T/src" main "$T/brief.md" >/dev/null 2>&1
check "solve passes --agents to the headless session" "$(grep -c -- '--agents {"hard-solver"' "$STUBDIR/calls")" 1
check "solve logs the agents file" "$(grep -c 'headless;exit=0;effort=default;agents=agents.json$' "$AB_RUNS_DIR/s12.reviews/steps.csv")" 1

rm -rf "$T"
print "test-solve: $pass passed, $fail failed"
(( fail == 0 ))
