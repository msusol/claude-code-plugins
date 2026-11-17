#!/usr/bin/env zsh
# Tests for the SOLVER_* environment names and their AB_* aliases (ADR 0001), with a stubbed `docker` (no containers, no API).
# Runs solver.zsh solve; the stub records the docker arguments and the environment it was given.
# Usage: zsh solver-docker/tests/test-env-names.zsh (exit 0 = all pass)

HERE="${0:A:h}/.."
SOLVE="$HERE/solver.zsh"
pass=0; fail=0
T=$(mktemp -d)
mkdir -p "$T/bin" "$T/stub" "$T/src"
printf '#!/bin/sh\nexec "%s" "$@"\n' "$(command -p -v git)" > "$T/bin/git"; chmod +x "$T/bin/git"
export PATH="$T/bin:$PATH" ANTHROPIC_API_KEY=sk-test STUBDIR="$T/stub"
unset AB_RUNS_DIR AB_EXPERIMENTS_DIR AB_EFFORT AB_SOLVE_BUDGET_USD AB_SOLVE_TIMEOUT AB_AGENTS_FILE AB_ALLOW_DOMAINS AB_IMAGE AB_DOCS \
      SOLVER_RUNS_DIR SOLVER_EXPERIMENTS_DIR SOLVER_EFFORT SOLVER_SOLVE_BUDGET_USD SOLVER_SOLVE_TIMEOUT SOLVER_AGENTS_FILE SOLVER_ALLOW_DOMAINS SOLVER_IMAGE SOLVER_DOCS

git -C "$T/src" init -q -b main; echo plan > "$T/src/PLAN.md"; git -C "$T/src" add -A
git -C "$T/src" -c user.name=t -c user.email=t@t commit -qm seed
echo "Build the thing. End with AUTO-MODE: DONE." > "$T/brief.md"
echo '{"a": {"description": "d", "prompt": "p", "model": "m"}}' > "$T/agents.json"

cat > "$T/bin/docker" <<'STUB'
#!/bin/bash
case "$1" in
  image|ps|rm) exit 0 ;;
  run)
    dir=""; for a in "$@"; do [[ "$a" == *:/work ]] && dir="${a%:/work}"; done
    echo "$*" >> "$STUBDIR/calls"
    G="git -C $dir -c user.name=t -c user.email=t@t"
    $G init -q -b main; $G add -A; $G commit -qm baseline; $G checkout -q -b exp/stub
    echo work > "$dir/out.txt"; $G add -A; $G commit -qm "feat: work"; printf 'Built it.\nAUTO-MODE: DONE\n'
    exit 0 ;;
esac
STUB
chmod +x "$T/bin/docker"

check() { if [[ "$2" == "$3" ]]; then (( pass++ )); else (( fail++ )); print "FAIL: $1 (got '$2', want '$3')"; fi }
run() {  # name, then VAR=value pairs for the environment
  local name="$1"; shift; : > "$STUBDIR/calls"
  env "$@" zsh "$SOLVE" solve "$name" claude-fable-5-2 "$T/src" main "$T/brief.md" >/dev/null 2>"$T/err-$name"; print $?
}

# The new names alone work: the runs folder, the bounds, the effort and the agents file all take effect
rc=$(run n1 SOLVER_RUNS_DIR="$T/r-new" SOLVER_EXPERIMENTS_DIR="$T/exp" SOLVER_SOLVE_BUDGET_USD=7 SOLVER_EFFORT=high SOLVER_AGENTS_FILE="$T/agents.json")
check "SOLVER_* alone: solve succeeds" "$rc" 0
check "SOLVER_RUNS_DIR is the runs folder" "$([[ -f $T/r-new/n1.out/result.txt ]] && echo yes || echo no)" yes
check "SOLVER_SOLVE_BUDGET_USD reaches the session" "$(grep -c -- '--max-budget-usd 7' $STUBDIR/calls)" 1
check "SOLVER_EFFORT reaches the session" "$(grep -c -- '--effort high' $STUBDIR/calls)" 1
check "SOLVER_AGENTS_FILE reaches the session" "$(grep -c -- '--agents {"a"' $STUBDIR/calls)" 1
check "the step log names the agents file" "$(grep -c 'effort=high;agents=agents.json$' $T/r-new/n1.reviews/steps.csv)" 1

# The old names alone still work, with the same results
rc=$(run n2 AB_RUNS_DIR="$T/r-old" AB_EXPERIMENTS_DIR="$T/exp" AB_SOLVE_BUDGET_USD=6 AB_EFFORT=low AB_AGENTS_FILE="$T/agents.json")
check "AB_* alone: solve succeeds" "$rc" 0
check "AB_RUNS_DIR is the runs folder" "$([[ -f $T/r-old/n2.out/result.txt ]] && echo yes || echo no)" yes
check "AB_SOLVE_BUDGET_USD reaches the session" "$(grep -c -- '--max-budget-usd 6' $STUBDIR/calls)" 1
check "AB_EFFORT reaches the session" "$(grep -c -- '--effort low' $STUBDIR/calls)" 1
check "AB_AGENTS_FILE reaches the session" "$(grep -c -- '--agents {"a"' $STUBDIR/calls)" 1
check "no conflict note when only one name is set" "$(grep -c 'both set' $T/err-n2)" 0

# Both set and different: SOLVER_* wins, and a note says so
rc=$(run n3 SOLVER_RUNS_DIR="$T/r-new" AB_RUNS_DIR="$T/r-other" SOLVER_EXPERIMENTS_DIR="$T/exp" SOLVER_SOLVE_BUDGET_USD=3 AB_SOLVE_BUDGET_USD=9)
check "both set: solve succeeds" "$rc" 0
check "SOLVER_RUNS_DIR wins" "$([[ -f $T/r-new/n3.out/result.txt && ! -e $T/r-other ]] && echo yes || echo no)" yes
check "SOLVER_SOLVE_BUDGET_USD wins" "$(grep -c -- '--max-budget-usd 3' $STUBDIR/calls)" 1
check "a note names the conflict" "$(grep -c 'SOLVER_SOLVE_BUDGET_USD and AB_SOLVE_BUDGET_USD are both set and differ' $T/err-n3)" 1

# Both set and equal: no note
rc=$(run n4 SOLVER_RUNS_DIR="$T/r-new" AB_RUNS_DIR="$T/r-new" SOLVER_EXPERIMENTS_DIR="$T/exp")
check "both set and equal: no note" "$(grep -c 'both set' $T/err-n4)" 0

# The container gets both names, so an image built before the rename still reads AB_NAME and AB_ALLOW_DOMAINS
rc=$(run n5 SOLVER_RUNS_DIR="$T/r-new" SOLVER_EXPERIMENTS_DIR="$T/exp" SOLVER_ALLOW_DOMAINS="extra.example")
check "container gets SOLVER_NAME" "$(grep -c -- '-e SOLVER_NAME=n5' $STUBDIR/calls)" 1
check "container gets AB_NAME" "$(grep -c -- '-e AB_NAME=n5' $STUBDIR/calls)" 1
check "container gets SOLVER_ALLOW_DOMAINS with the API host" "$(grep -c -- '-e SOLVER_ALLOW_DOMAINS=api.anthropic.com extra.example' $STUBDIR/calls)" 1
check "container gets AB_ALLOW_DOMAINS too" "$(grep -c -- '-e AB_ALLOW_DOMAINS=api.anthropic.com extra.example' $STUBDIR/calls)" 1

# solve refuses SOLVER_LOGIN=1 as it refused AB_LOGIN=1; the docs image is chosen for solve through either name
rc=$(run n6 SOLVER_RUNS_DIR="$T/r-new" SOLVER_EXPERIMENTS_DIR="$T/exp" SOLVER_LOGIN=1)
check "SOLVER_LOGIN=1 is refused" "$rc" 1
rc=$(run n7 SOLVER_RUNS_DIR="$T/r-new" SOLVER_EXPERIMENTS_DIR="$T/exp")
check "solve runs on the docs image" "$(grep -c -- 'ab-claude-docs claude' $STUBDIR/calls)" 1
rc=$(run n8 SOLVER_RUNS_DIR="$T/r-new" SOLVER_EXPERIMENTS_DIR="$T/exp" SOLVER_IMAGE=my-image)
check "SOLVER_IMAGE picks the image" "$(grep -c -- 'my-image claude' $STUBDIR/calls)" 1

# Container scripts: the new names first, the old ones as aliases
PW="$HERE/prepare-workdir.sh"
mkdir -p "$T/w1" "$T/w2" "$T/w3" "$T/w4"
echo x > "$T/w1/f"; echo x > "$T/w2/f"; echo x > "$T/w3/f"; echo x > "$T/w4/f"
( cd "$T/w1" && SOLVER_NAME=one bash "$PW" >/dev/null 2>&1 ); check "prepare-workdir: SOLVER_NAME" "$(git -C $T/w1 branch --show-current)" exp/one
( cd "$T/w2" && AB_NAME=two bash "$PW" >/dev/null 2>&1 );     check "prepare-workdir: AB_NAME alias" "$(git -C $T/w2 branch --show-current)" exp/two
( cd "$T/w3" && SOLVER_NAME=three AB_NAME=other bash "$PW" >/dev/null 2>&1 ); check "prepare-workdir: SOLVER_NAME wins" "$(git -C $T/w3 branch --show-current)" exp/three
( cd "$T/w4" && env -u SOLVER_NAME -u AB_NAME bash "$PW" >/dev/null 2>&1 ); check "prepare-workdir: no name is an error" "$?" 1
( cd "$T/w1" && true ); mkdir -p "$T/w5"; echo x > "$T/w5/f"
( cd "$T/w5" && SOLVER_NAME=five SOLVER_REMOTE=https://example.invalid/x bash "$PW" >/dev/null 2>&1 ); check "prepare-workdir: SOLVER_REMOTE" "$(git -C $T/w5 remote get-url origin)" https://example.invalid/x

rm -rf "$T"
print "test-env-names: $pass passed, $fail failed"
(( fail == 0 ))
