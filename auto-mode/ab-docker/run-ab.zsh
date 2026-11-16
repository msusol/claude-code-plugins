#!/usr/bin/env zsh
# Run one A/B experiment arm in an isolated container. The generic sandbox (image, firewall, export, launch, solve) lives in
# ../solver-docker; this script adds the A/B parts: the experiments folder, the interactive run and resume, and the Copilot review loop.
#
#   run-ab.zsh init [dir]                         create the experiments folder from the template (default ~/experiments)
#   run-ab.zsh build                              build the image (once, and after plugin changes); AB_DOCS=1 adds the docs/ harness   [solver-docker]
#   run-ab.zsh check                              prove the isolation (filesystem, network, tooling)   [solver-docker]
#   run-ab.zsh run <name> <model> <src-repo> [ref]  start Claude Code on a fresh export of <ref> (default HEAD)
#   run-ab.zsh resume <name> <model>              start a new session on an existing run folder (e.g. to fix review findings)
#   run-ab.zsh solve <name> <model> <src-repo> <ref> <brief-file>   unattended: export <ref>, run one headless session on the brief   [solver-docker]
#   run-ab.zsh review-round <name>                push the arm's branch, get a Copilot PR review, write REVIEW-N.md (see review-round.zsh)
#   run-ab.zsh review-summary <name>...           table of review rounds and findings per arm
#   run-ab.zsh review-loop <name> <model>         unattended: review-round, then a headless fix session, until CLEAN or the cap
#
# AB_EFFORT=medium (or low|high|xhigh|max) pins Claude Code's --effort for every session of every arm; set the same value for all arms.
# <name> becomes the branch exp/<name> and the run folder $AB_RUNS_DIR/<name> (default ~/experiments/runs/<name>).
# The container sees only that folder (as /work) and can reach only api.anthropic.com. Claude Code's own session logs
# (transcripts) are written to $AB_RUNS_DIR/<name>.session (mounted as the container's ~/.claude/projects) so they survive
# the container, and every step is logged to $AB_RUNS_DIR/<name>.reviews/steps.csv for the cost dashboard.
# Auth for `run`: ANTHROPIC_API_KEY in the environment (pass it inline, not exported: ANTHROPIC_API_KEY=... run-ab.zsh run ...),
# or AB_LOGIN=1 to sign in with a Claude account inside the container. Use a dedicated key with a spend limit:
# the model can read it inside the container. If ANTHROPIC_API_KEY is not set, it is read from $AB_ENV_FILE
# (default ~/experiments/.env, must be chmod 600, one line ANTHROPIC_API_KEY=sk-ant-...; the file is parsed, never sourced).

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
source "$SCRIPT_DIR/../solver-docker/lib.zsh"   # IMAGE, RUNS_DIR, die, effort_args, auth_setup, launch, launch_headless, prepare_run, log_step, now_utc

usage() {
  print -u2 -- "usage: run-ab.zsh init [dir] | build | check | run <name> <model> <src-repo> [ref] | resume <name> <model> | solve <name> <model> <src-repo> <ref> <brief-file> | review-round <name> | review-summary <name>... | review-loop <name> <model>"
  exit 2
}

# Copies experiments-template/ to <dir> without overwriting anything that exists, and creates the example plan repo.
cmd_init() {
  local dest="${1:-$EXP_DIR}" tpl="$SCRIPT_DIR/experiments-template" f
  [[ -d "$tpl" ]] || die "template not found at $tpl"
  mkdir -p "$dest"
  for f in $(cd "$tpl" && find . -path ./examples -prune -o -type f -print); do
    [[ -e "$dest/$f" ]] && continue
    mkdir -p "$dest/${f:h}"
    cp "$tpl/$f" "$dest/$f"
  done
  local ex name
  for ex in "$tpl"/examples/*(/N); do
    name="${ex:t}"
    [[ -e "$dest/plans/$name" ]] && continue
    cp -R "$ex" "$dest/plans/$name"
    git -C "$dest/plans/$name" init -q -b main
    git -C "$dest/plans/$name" add -A
    print "created plans/$name (git init, files staged, not committed)"
  done
  print "experiments folder ready: $dest"
  print "next, for each plan in $dest/plans (wordfreq, wordfreq-docs):"
  print "  git -C $dest/plans/<plan> remote add origin https://github.com/<you>/<plan>-plan   # never pushed; satisfies git-guard"
  print "  git -C $dest/plans/<plan> commit -m 'plan: <plan>'"
  print "  export AB_RUNS_DIR=$dest/runs   # only needed if $dest is not ~/experiments"
  print "optional: to let an assistant start tmux sessions and run-ab.zsh for you, review $dest/.claude/settings.example.json and merge it into"
  print "  $dest/.claude/settings.local.json yourself (it is not active until you do; see $dest/README.md)"
  print "see $dest/README.md for the layout and naming"
}

# Number of review rounds recorded so far for a run (0 if none).
rounds_done() {  # name
  local csv="$RUNS_DIR/$1.reviews/rounds.csv"
  [[ -f "$csv" ]] && print $(( $(wc -l < "$csv") - 1 )) || print 0
}

cmd_run() {
  (( $# >= 3 )) || usage
  local name="$1" model="$2" src="$3" ref="${4:-HEAD}" dir
  prepare_run "$name" "$src" "$ref"

  local t0 rc=0; t0=$(now_utc)
  launch "$name" "$model" "$dir" || rc=$?
  log_step "$name" arm 0 "$model" "$dir" "interactive;exit=$rc;effort=${AB_EFFORT:-default}" "$t0"

  print "run folder: $dir   (git -C $dir log --oneline)"
  print "session logs: $dir.session   step log: $dir.reviews/steps.csv"
  return $rc
}

# New session on an existing run folder, e.g. to resolve a REVIEW-N.md. The repo, branch and history are kept;
# only the container is new (so a /login session needs signing in again).
cmd_resume() {
  (( $# == 2 )) || usage
  local name="$1" model="$2" dir="$RUNS_DIR/$1"
  [[ "$name" =~ '^[a-z0-9]+(-[a-z0-9]+)*$' ]] || die "name must be lowercase letters, digits and hyphens (got '$name')"
  [[ -d "$dir/.git" ]] || die "$dir is not a started run folder; use: run-ab.zsh run $name <model> <src-repo>"
  auth_setup
  docker image inspect "$IMAGE" >/dev/null 2>&1 || die "image '$IMAGE' not built; run: run-ab.zsh build"
  docker ps --format '{{.Names}}' | grep -qx "ab-$name" && die "a container for '$name' is already running"
  local t0 rc=0; t0=$(now_utc)
  launch "$name" "$model" "$dir" || rc=$?
  log_step "$name" resume "$(rounds_done "$name")" "$model" "$dir" "interactive;exit=$rc;effort=${AB_EFFORT:-default}" "$t0"
  return $rc
}

# Unattended review loop. auto-mode keeps each fix turn going to AUTO-MODE: DONE, but it cannot wait for GitHub, so this
# host-side loop does the rest: review-round, then a headless fix session on the same run folder, until a round is CLEAN
# or AB_MAX_ROUNDS is reached. It stops (fails closed) if a fix session makes no commit or leaves uncommitted changes.
# It needs an API key: a /login session needs a human. Re-running it continues from the last recorded round.
cmd_review_loop() {
  (( $# == 2 )) || usage
  local name="$1" model="$2" dir="$RUNS_DIR/$1" logdir="$RUNS_DIR/$1.reviews" max="${AB_MAX_ROUNDS:-5}"
  local csv="$logdir/rounds.csv" round last head_before t0 fix_rc
  [[ "$name" =~ '^[a-z0-9]+(-[a-z0-9]+)*$' ]] || die "name must be lowercase letters, digits and hyphens (got '$name')"
  [[ "${AB_LOGIN:-0}" != 1 ]] || die "review-loop runs unattended and needs ANTHROPIC_API_KEY; AB_LOGIN=1 needs a human for /login"
  [[ -d "$dir/.git" ]] || die "$dir is not a started run folder; use: run-ab.zsh run $name <model> <src-repo>"
  auth_setup
  docker image inspect "$IMAGE" >/dev/null 2>&1 || die "image '$IMAGE' not built; run: run-ab.zsh build"
  docker ps --format '{{.Names}}' | grep -qx "ab-$name" && die "a container for '$name' is already running; /exit it first"

  while true; do
    # A recorded round with findings whose commit has not changed still needs its fix: skip straight to the fix.
    if [[ -f "$csv" && "$(tail -1 "$csv" | cut -d, -f6)" == findings && -f "$logdir/last-head" \
          && "$(<"$logdir/last-head")" == "$(git -C "$dir" rev-parse HEAD)" ]]; then
      print "review-loop: resuming at the fix for round $(( $(wc -l < "$csv") - 1 ))"
    else
      zsh "$SCRIPT_DIR/review-round.zsh" review-round "$name" || die "review-round stopped (see above). Re-run review-loop to continue"
    fi
    last=$(tail -1 "$csv" | cut -d, -f6)
    round=$(( $(wc -l < "$csv") - 1 ))
    if [[ "$last" == clean ]]; then print "review-loop: $name CLEAN after $round round(s)"; return 0; fi
    (( round < max )) || die "round cap ($max) reached with findings still open for $name"

    head_before=$(git -C "$dir" rev-parse HEAD)
    print "review-loop: round $round has findings; headless fix session on $model (log: $logdir/fix-$round.log)"
    fix_rc=0; t0=$(now_utc)
    launch_headless "$name" "$model" "$dir" \
      "Read REVIEW-$round.md and resolve every finding: fix the code or add the missing test. If you disagree with one, say why in your commit message. Run the tests, commit, and end with AUTO-MODE: DONE." \
      2>&1 | tee "$logdir/fix-$round.log" || fix_rc=$?
    log_step "$name" fix "$round" "$model" "$dir" "headless;exit=$fix_rc;effort=${AB_EFFORT:-default}" "$t0"
    (( fix_rc == 0 )) || die "fix session failed (see $logdir/fix-$round.log); nothing was reviewed again"
    [[ "$(git -C "$dir" rev-parse HEAD)" != "$head_before" ]] || die "fix session made no new commit (see $logdir/fix-$round.log); stopping"
    [[ -z "$(git -C "$dir" status --porcelain)" ]] || die "fix session left uncommitted changes in $dir; stopping"
  done
}

(( $# >= 1 )) || usage
sub="$1"; shift
case "$sub" in
  init)  cmd_init "$@" ;;
  build|check|solve) exec zsh "$SCRIPT_DIR/../solver-docker/solver.zsh" "$sub" "$@" ;;
  run)   cmd_run "$@" ;;
  resume) cmd_resume "$@" ;;
  review-loop) cmd_review_loop "$@" ;;
  review-round|review-summary) exec zsh "$SCRIPT_DIR/review-round.zsh" "$sub" "$@" ;;
  *)     usage ;;
esac
