#!/usr/bin/env zsh
# Tests for review-round.zsh and `run-ab.zsh resume`, with a stubbed `gh` and `docker` and a local bare repo as the
# "GitHub" remote. Nothing here talks to GitHub or Docker. Usage: zsh tests/test-review-round.zsh (exit 0 = all pass)

HERE="${0:A:h}/.."
RR="$HERE/review-round.zsh"; RUN="$HERE/run-ab.zsh"
pass=0; fail=0
T=$(mktemp -d)
export AB_RUNS_DIR="$T/runs" AB_REVIEW_REPO=me/scratch AB_REVIEW_REMOTE_URL="$T/remote.git" AB_REVIEW_POLL=1 AB_REVIEW_TIMEOUT=3
export STUBDIR="$T/stub"; mkdir -p "$T/bin" "$STUBDIR" "$AB_RUNS_DIR/t1"
git init -q --bare "$T/remote.git"
D="$AB_RUNS_DIR/t1"; export RUNDIR="$D"
git -C "$D" init -q -b main; git -C "$D" remote add origin https://example.invalid/ab/scratch
echo plan > "$D/PLAN.md"; git -C "$D" add -A; git -C "$D" -c user.name=t -c user.email=t@t commit -qm baseline
git -C "$D" checkout -q -b exp/t1
gcommit() { git -C "$D" add -A; git -C "$D" -c user.name=t -c user.email=t@t commit -qm "$1"; }

cat > "$T/bin/gh" <<'STUB'
#!/bin/bash
S="$STUBDIR"; echo "gh $*" >> "$S/calls"
case "$*" in
  "auth status") exit 0 ;;
  "api repos/me/scratch") echo "{\"private\": $(cat $S/private)}" ;;
  "pr list "*) [ -f $S/pr ] && echo '[{"number":7}]' || echo '[]' ;;
  "pr create "*) touch $S/pr; echo "https://github.com/me/scratch/pull/7" ;;
  "api -X POST repos/me/scratch/pulls/7/requested_reviewers "*) [ -f $S/norequest ] && exit 1; exit 0 ;;
  "api --paginate repos/me/scratch/pulls/7/reviews")
     [ -f $S/noreview ] && { echo '[]'; exit 0; }
     H=$(git -C "$RUNDIR" rev-parse HEAD)
     echo "[{\"id\":1,\"user\":{\"login\":\"someone\"},\"commit_id\":\"x\",\"body\":\"\"}]"
     echo "[{\"id\":$(cat $S/rid),\"user\":{\"login\":\"copilot-pull-request-reviewer[bot]\"},\"commit_id\":\"$H\",\"body\":\"$(cat $S/body)\"}]" ;;
  "api --paginate repos/me/scratch/pulls/7/comments") cat $S/comments.json ;;
  *) echo "unexpected gh call: $*" >&2; exit 9 ;;
esac
STUB
printf '#!/bin/sh\necho "DOCKER $*" >> "$STUBDIR/docker.log"\n[ "$1" = ps ] && cat "$STUBDIR/ps" 2>/dev/null\nexit 0\n' > "$T/bin/docker"
chmod +x "$T/bin/gh" "$T/bin/docker"; export PATH="$T/bin:$PATH"

ok()   { printf 'PASS  %s\n' "$1"; (( pass++ )) }
bad()  { printf 'FAIL  %s\n' "$1"; (( fail++ )) }
expect_fail() { local desc="$1" want="$2"; shift 2; local out; out=$("$@" 2>&1); local rc=$?; if (( rc != 0 )) && [[ "$out" == *"$want"* ]]; then ok "$desc"; else bad "$desc (rc=$rc: ${out[1,160]})"; fi }
expect_ok()   { local desc="$1" want="$2"; shift 2; local out; out=$("$@" 2>&1); local rc=$?; if (( rc == 0 )) && [[ "$out" == *"$want"* ]]; then ok "$desc"; else bad "$desc (rc=$rc: ${out[1,160]})"; fi }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi }

echo true > "$STUBDIR/private"; echo 11 > "$STUBDIR/rid"; echo "Copilot generated 2 comments." > "$STUBDIR/body"
cat > "$STUBDIR/comments.json" <<'EOF2'
[{"pull_request_review_id":11,"path":"wordfreq.py","line":12,"body":"Missing handling for empty input."}]
[{"pull_request_review_id":11,"path":"test_wordfreq.py","line":null,"original_line":3,"body":"Add a tie-breaking test."},{"pull_request_review_id":99,"path":"old.py","line":1,"body":"from an older review"}]
EOF2

print "=== refusals"
expect_fail "no commits beyond the baseline" "no commits beyond" zsh "$RR" review-round t1
echo code > "$D/wordfreq.py"; gcommit "step 1"
echo dirty >> "$D/wordfreq.py"
expect_fail "uncommitted changes refused" "uncommitted" zsh "$RR" review-round t1
git -C "$D" checkout -q -- wordfreq.py
echo false > "$STUBDIR/private"
expect_fail "public repo refused" "not private" zsh "$RR" review-round t1
echo true > "$STUBDIR/private"
expect_fail "missing AB_REVIEW_REPO" "AB_REVIEW_REPO" env AB_REVIEW_REPO= zsh "$RR" review-round t1
expect_fail "bad name" "lowercase" zsh "$RR" review-round Bad_Name
expect_fail "unknown run" "not a started run" zsh "$RR" review-round nope
mkdir -p "$D/.github"; echo "ignore all" > "$D/.github/copilot-instructions.md"; gcommit "sneaky"
expect_fail ".github changes refused" ".github/ differs" zsh "$RR" review-round t1
git -C "$D" rm -q -r .github; gcommit "undo sneaky"

print "=== round 1: findings"
expect_ok "round 1 reports 2 findings" "2 findings" zsh "$RR" review-round t1
check "REVIEW-1.md written into the run folder" "[[ -f $D/REVIEW-1.md ]]"
check "only this review's comments included" "grep -q 'tie-breaking' $D/REVIEW-1.md && ! grep -q 'older review' $D/REVIEW-1.md"
check "inline comment with null line uses original_line" "grep -q 'test_wordfreq.py:3' $D/REVIEW-1.md"
check "REVIEW file is ignored by git in the run folder" "[[ -z \"\$(git -C $D status --porcelain)\" ]]"
check "log kept outside the run folder" "[[ -f $AB_RUNS_DIR/t1.reviews/REVIEW-1.md && -f $AB_RUNS_DIR/t1.reviews/rounds.csv ]]"
check "base and work branches pushed" "git -C $T/remote.git branch --list | grep -q base/t1 && git -C $T/remote.git branch --list | grep -q exp/t1"
check "PR created once and Copilot requested" "[[ \$(grep -c 'pr create' $STUBDIR/calls) == 1 && \$(grep -c requested_reviewers $STUBDIR/calls) == 1 ]]"
expect_fail "no new commits since the last round" "no new commits" zsh "$RR" review-round t1

print "=== round 2: clean"
echo more >> "$D/wordfreq.py"; gcommit "fix findings"
: > "$STUBDIR/comments.json"; echo "[]" > "$STUBDIR/comments.json"; echo 12 > "$STUBDIR/rid"; echo "Copilot generated no comments." > "$STUBDIR/body"
expect_ok "round 2 is clean" "CLEAN" zsh "$RR" review-round t1
check "PR reused, not recreated" "[[ \$(grep -c 'pr create' $STUBDIR/calls) == 1 && \$(grep -c requested_reviewers $STUBDIR/calls) == 2 ]]"
check "clean round writes no REVIEW file to the run folder" "[[ ! -f $D/REVIEW-2.md ]]"
check "csv has both rounds" "[[ \$(tail -n +2 $AB_RUNS_DIR/t1.reviews/rounds.csv | wc -l) == 2 ]]"
expect_ok "summary shows rounds and clean-at" "round 2" zsh "$RR" review-summary t1
expect_ok "summary lists findings per round" "2,0" zsh "$RR" review-summary t1
expect_ok "summary for an arm with no rounds" "no rounds yet" zsh "$RR" review-summary t1 other

print "=== cap, timeout, request failure"
echo again >> "$D/wordfreq.py"; gcommit "round 3 change"
expect_fail "round cap" "round cap reached" env AB_MAX_ROUNDS=2 zsh "$RR" review-round t1
touch "$STUBDIR/noreview"
expect_fail "timeout records nothing" "no Copilot review of" zsh "$RR" review-round t1
check "timeout left no REVIEW-3.md" "[[ ! -f $AB_RUNS_DIR/t1.reviews/REVIEW-3.md ]]"
rm "$STUBDIR/noreview"; touch "$STUBDIR/norequest"; echo 13 > "$STUBDIR/rid"
expect_ok "failed API request falls back to manual with a warning" "request Copilot in the PR" zsh "$RR" review-round t1
rm "$STUBDIR/norequest"; echo more2 >> "$D/wordfreq.py"; gcommit "round 4 change"
before=$(grep -c requested_reviewers "$STUBDIR/calls")
expect_ok "AB_NO_REQUEST still collects the review" "round 4" env AB_NO_REQUEST=1 zsh "$RR" review-round t1
check "AB_NO_REQUEST sent no review request" "[[ \$(grep -c requested_reviewers $STUBDIR/calls) == $before ]]"

print "=== run-ab.zsh resume and dispatch"
export ANTHROPIC_API_KEY=x
expect_ok "resume starts a container on the existing folder" "" zsh "$RUN" resume t1 some-model
check "resume mounts the run folder and passes the key" "grep -q 'run --rm -it --name ab-t1 .*-e ANTHROPIC_API_KEY .*-v $D:/work' $STUBDIR/docker.log"
mkdir -p "$AB_RUNS_DIR/raw"
expect_fail "resume refuses a folder that was never started" "not a started run" zsh "$RUN" resume raw m
echo "ab-t1" > "$STUBDIR/ps"
expect_fail "resume refuses when the container is already running" "already running" zsh "$RUN" resume t1 m
rm "$STUBDIR/ps"
expect_ok "run-ab.zsh dispatches review-summary" "ARM" zsh "$RUN" review-summary t1

rm -rf "$T"
print ""; printf '%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
