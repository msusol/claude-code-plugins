#!/usr/bin/env zsh
# Tests for review-round.zsh and `run-ab.zsh resume`, with a stubbed `gh` and `docker` and a local bare repo as the
# "GitHub" remote. Nothing here talks to GitHub or Docker. Usage: zsh tests/test-review-round.zsh (exit 0 = all pass)

HERE="${0:A:h}/.."
RR="$HERE/review-round.zsh"; RUN="$HERE/run-ab.zsh"
pass=0; fail=0
T=$(mktemp -d)
export AB_RUNS_DIR="$T/runs" AB_REVIEW_REPO=me/scratch AB_REVIEW_REMOTE_URL="$T/remote.git" AB_REVIEW_POLL=1 AB_REVIEW_TIMEOUT=3
export STUBDIR="$T/stub"; mkdir -p "$T/bin" "$STUBDIR" "$AB_RUNS_DIR/t1"
# Hermetic git: the fixtures here are throwaway repos in $T with a fake origin and a local bare remote, so use the real git
# binary instead of any git-guard wrapper earlier in PATH (the wrapper guards real repos and would block these fixtures).
printf '#!/bin/sh\nexec "%s" "$@"\n' "$(command -p -v git)" > "$T/bin/git"
chmod +x "$T/bin/git"; export PATH="$T/bin:$PATH"
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
     echo "[{\"id\":$(cat $S/rid),\"user\":{\"login\":\"copilot-pull-request-reviewer[bot]\"},\"commit_id\":\"$H\",\"copilot_code_review_effort\":\"balanced\",\"body\":\"$(cat $S/body)\"}]" ;;
  "api --paginate repos/me/scratch/pulls/7/comments") cat $S/comments.json ;;
  *) echo "unexpected gh call: $*" >&2; exit 9 ;;
esac
STUB
cat > "$T/bin/docker" <<'STUB'
#!/bin/sh
echo "DOCKER $*" >> "$STUBDIR/docker.log"
echo "KEY=$ANTHROPIC_API_KEY" >> "$STUBDIR/docker.log"
[ "$1" = ps ] && cat "$STUBDIR/ps" 2>/dev/null
case "$*" in
  *"claude -p"*)
    [ -f "$STUBDIR/failmode" ] && exit 1
    # a headless fix session: with fixmode it commits a change, and Copilot's next review comes back clean
    if [ -f "$STUBDIR/fixmode" ]; then
      echo fix >> "$RUNDIR/wordfreq.py"; git -C "$RUNDIR" add -A
      git -C "$RUNDIR" -c user.name=t -c user.email=t@t commit -qm "fix findings"
      echo '[]' > "$STUBDIR/comments.json"; echo "Copilot generated no comments." > "$STUBDIR/body"
      echo $(( $(cat "$STUBDIR/rid") + 1 )) > "$STUBDIR/rid"
    fi ;;
esac
exit 0
STUB
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
check "origin is restored to the container remote after the pushes" "[[ \$(git -C $D remote get-url origin) == https://example.invalid/ab/scratch ]]"

print "=== round 2: clean"
echo more >> "$D/wordfreq.py"; gcommit "fix findings"
: > "$STUBDIR/comments.json"; echo "[]" > "$STUBDIR/comments.json"; echo 12 > "$STUBDIR/rid"; echo "Copilot generated no comments." > "$STUBDIR/body"
expect_ok "round 2 is clean" "CLEAN" zsh "$RR" review-round t1
check "PR reused, not recreated" "[[ \$(grep -c 'pr create' $STUBDIR/calls) == 1 && \$(grep -c requested_reviewers $STUBDIR/calls) == 2 ]]"
check "clean round writes no REVIEW file to the run folder" "[[ ! -f $D/REVIEW-2.md ]]"
check "csv has both rounds" "[[ \$(tail -n +2 $AB_RUNS_DIR/t1.reviews/rounds.csv | wc -l) == 2 ]]"
check "steps.csv has a header and one review row per round" "[[ \$(head -1 $AB_RUNS_DIR/t1.reviews/steps.csv) == 'start,end,type,round,model,commit,detail' && \$(grep -c ',review,' $AB_RUNS_DIR/t1.reviews/steps.csv) == 2 ]]"
check "review rows record Copilot, findings, status, review count and effort" "grep -q ',review,1,copilot,.*,pr=7;findings=2;status=findings;premium_requests=1;effort=balanced\$' $AB_RUNS_DIR/t1.reviews/steps.csv && grep -q ',review,2,copilot,.*;findings=0;status=clean;premium_requests=1;effort=balanced\$' $AB_RUNS_DIR/t1.reviews/steps.csv"
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
check "AB_NO_REQUEST round records premium_requests=0" "tail -1 $AB_RUNS_DIR/t1.reviews/steps.csv | grep -q 'premium_requests=0'"

print "=== run-ab.zsh resume and dispatch"
export ANTHROPIC_API_KEY=x
expect_ok "resume starts a container on the existing folder" "" zsh "$RUN" resume t1 some-model
check "resume mounts the run's session folder as the container's projects dir" "grep -q -- \"-v $AB_RUNS_DIR/t1.session:/home/claude/.claude/projects\" $STUBDIR/docker.log && [[ -d $AB_RUNS_DIR/t1.session ]]"
check "resume logs a resume step with the round it follows" "tail -1 $AB_RUNS_DIR/t1.reviews/steps.csv | grep -q ',resume,[0-9]*,some-model,.*,interactive;exit=0;effort=default\$'"
check "resume mounts the run folder and passes the key" "grep -q 'run --rm -it --name ab-t1 .*-e ANTHROPIC_API_KEY .*-v $D:/work' $STUBDIR/docker.log"
mkdir -p "$AB_RUNS_DIR/raw"
expect_fail "resume refuses a folder that was never started" "not a started run" zsh "$RUN" resume raw m
echo "ab-t1" > "$STUBDIR/ps"
expect_fail "resume refuses when the container is already running" "already running" zsh "$RUN" resume t1 m
rm "$STUBDIR/ps"
expect_ok "run-ab.zsh dispatches review-summary" "ARM" zsh "$RUN" review-summary t1


print "=== review-loop (unattended)"
mkarm() {  # name: a started run folder with one commit beyond the baseline
  local d="$AB_RUNS_DIR/$1"; mkdir -p "$d"
  git -C "$d" init -q -b main; git -C "$d" remote add origin https://example.invalid/ab/scratch
  echo plan > "$d/PLAN.md"; git -C "$d" add -A; git -C "$d" -c user.name=t -c user.email=t@t commit -qm baseline
  git -C "$d" checkout -q -b "exp/$1"; echo code > "$d/wordfreq.py"; git -C "$d" add -A
  git -C "$d" -c user.name=t -c user.email=t@t commit -qm "step 1"
}
setfindings() {  # rid: Copilot's next review has one finding
  echo "$1" > "$STUBDIR/rid"; echo "Copilot generated 1 comment." > "$STUBDIR/body"
  print -r -- "[{\"pull_request_review_id\":$1,\"path\":\"wordfreq.py\",\"line\":1,\"body\":\"Fix me.\"}]" > "$STUBDIR/comments.json"
}
expect_fail "loop refuses AB_LOGIN" "needs ANTHROPIC_API_KEY" env AB_LOGIN=1 zsh "$RUN" review-loop t1 m
expect_fail "loop refuses a folder that was never started" "not a started run" zsh "$RUN" review-loop raw m
expect_fail "loop needs a key" "ANTHROPIC_API_KEY is not set" env -u ANTHROPIC_API_KEY AB_ENV_FILE="$T/none.env" zsh "$RUN" review-loop t1 m

mkarm t2; export RUNDIR="$AB_RUNS_DIR/t2"; D2="$RUNDIR"; setfindings 21; touch "$STUBDIR/fixmode"; : > "$STUBDIR/docker.log"
expect_ok "loop: findings, headless fix, then CLEAN" "t2 CLEAN after 2 round" zsh "$RUN" review-loop t2 some-model
check "loop recorded both rounds" "[[ \$(tail -n +2 $AB_RUNS_DIR/t2.reviews/rounds.csv | wc -l) == 2 ]]"
check "fix session ran headless (no TTY) with the fix prompt" "grep -q 'run --rm --name ab-t2 ' $STUBDIR/docker.log && ! grep -q 'run --rm -it --name ab-t2' $STUBDIR/docker.log && grep -q 'claude -p Read REVIEW-1.md' $STUBDIR/docker.log"
check "fix session passes model, permission skip and a budget cap" "grep -q -- '--model some-model' $STUBDIR/docker.log && grep -q -- '--dangerously-skip-permissions' $STUBDIR/docker.log && grep -q -- '--max-budget-usd 2' $STUBDIR/docker.log"
check "fix log kept outside the run folder" "[[ -f $AB_RUNS_DIR/t2.reviews/fix-1.log ]]"
check "headless fix session mounts the run's session folder" "grep 'claude -p' $STUBDIR/docker.log | grep -q -- \"-v $AB_RUNS_DIR/t2.session:/home/claude/.claude/projects\""
check "steps.csv shows review, fix, review in order" "[[ \$(tail -n +2 $AB_RUNS_DIR/t2.reviews/steps.csv | cut -d, -f3,4 | paste -sd' ' -) == 'review,1 fix,1 review,2' ]]"
check "fix step records the model and exit code" "grep -q ',fix,1,some-model,.*,headless;exit=0;effort=default\$' $AB_RUNS_DIR/t2.reviews/steps.csv"
check "origin is still the container remote" "[[ \$(git -C $D2 remote get-url origin) == https://example.invalid/ab/scratch ]]"

mkarm t3; export RUNDIR="$AB_RUNS_DIR/t3"; D3="$RUNDIR"; setfindings 31; rm -f "$STUBDIR/fixmode"
expect_fail "loop stops when the fix session makes no commit" "no new commit" zsh "$RUN" review-loop t3 m
touch "$STUBDIR/fixmode"
expect_ok "re-running continues at the fix, then reaches CLEAN" "resuming at the fix" zsh "$RUN" review-loop t3 m
check "t3 ended clean" "[[ \$(tail -1 $AB_RUNS_DIR/t3.reviews/rounds.csv | cut -d, -f6) == clean ]]"

mkarm t4; export RUNDIR="$AB_RUNS_DIR/t4"; setfindings 41
expect_fail "loop stops at the round cap" "round cap (1) reached" env AB_MAX_ROUNDS=1 zsh "$RUN" review-loop t4 m

mkarm t5; export RUNDIR="$AB_RUNS_DIR/t5"; setfindings 51; touch "$STUBDIR/failmode"
expect_fail "a failing fix session stops the loop" "fix session failed" zsh "$RUN" review-loop t5 m
check "a failed fix is still logged, with its exit code" "grep -q ',fix,1,m,.*,headless;exit=1;effort=default\$' $AB_RUNS_DIR/t5.reviews/steps.csv"
rm -f "$STUBDIR/failmode"

print "=== API key from an env file"
print -r -- 'ANTHROPIC_API_KEY="sk-ant-fromfile"' > "$T/key.env"; chmod 644 "$T/key.env"
expect_fail "env file readable by others is refused" "chmod 600" env -u ANTHROPIC_API_KEY AB_ENV_FILE="$T/key.env" zsh "$RUN" resume t1 m
chmod 600 "$T/key.env"; : > "$STUBDIR/docker.log"
expect_ok "key is read from a 600 env file" "" env -u ANTHROPIC_API_KEY AB_ENV_FILE="$T/key.env" zsh "$RUN" resume t1 m
check "the quoted key value reached docker" "grep -q 'KEY=sk-ant-fromfile' $STUBDIR/docker.log"
print -r -- 'OTHER=1; touch '"$T"'/pwned' > "$T/evil.env"; chmod 600 "$T/evil.env"
expect_fail "an env file without the key is not executed" "ANTHROPIC_API_KEY is not set" env -u ANTHROPIC_API_KEY AB_ENV_FILE="$T/evil.env" zsh "$RUN" resume t1 m
check "nothing in the env file ran" "[[ ! -e $T/pwned ]]"
expect_ok "AB_LOGIN ignores the env file" "AB_LOGIN=1" env -u ANTHROPIC_API_KEY AB_LOGIN=1 AB_ENV_FILE="$T/key.env" zsh "$RUN" resume t1 m

print "=== Copilot unable to review (quota) is an error, not a clean round"
D="$AB_RUNS_DIR/t1"; export RUNDIR="$D"   # later sections re-point the stub at other runs
rm -f "$STUBDIR/fixmode"; echo more3 >> "$D/wordfreq.py"; gcommit "round 5 change"
echo "Copilot was unable to review this pull request because the user who requested the review has insufficient remaining quota. Try requesting a review again later." > "$STUBDIR/body"
echo "[]" > "$STUBDIR/comments.json"; echo 14 > "$STUBDIR/rid"
rows_before=$(tail -n +2 "$AB_RUNS_DIR/t1.reviews/rounds.csv" | wc -l)
expect_fail "a quota failure stops the round with an error" "unable to review" zsh "$RR" review-round t1
check "the quota failure recorded no round" "[[ \$(tail -n +2 $AB_RUNS_DIR/t1.reviews/rounds.csv | wc -l) == $rows_before && ! -f $AB_RUNS_DIR/t1.reviews/REVIEW-5.md ]]"
check "the quota failure was not counted as CLEAN" "! tail -n +2 $AB_RUNS_DIR/t1.reviews/rounds.csv | tail -1 | grep -q ',clean\$' || [[ \$(tail -n +2 $AB_RUNS_DIR/t1.reviews/rounds.csv | wc -l) == $rows_before ]]"
echo "Copilot generated no comments." > "$STUBDIR/body"; echo 15 > "$STUBDIR/rid"
expect_ok "after the cause is fixed a real review is accepted for the same commit" "CLEAN" zsh "$RR" review-round t1

rm -rf "$T"
print ""; printf '%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
