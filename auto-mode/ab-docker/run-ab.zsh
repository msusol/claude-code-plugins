#!/usr/bin/env zsh
# Run one A/B experiment arm in an isolated container.
#
#   run-ab.zsh init [dir]                         create the experiments folder from the template (default ~/experiments)
#   run-ab.zsh build                              build the image (once, and after plugin changes); AB_DOCS=1 adds the docs/ harness
#   run-ab.zsh check                              prove the isolation (filesystem, network, tooling)
#   run-ab.zsh run <name> <model> <src-repo> [ref]  start Claude Code on a fresh export of <ref> (default HEAD)
#   run-ab.zsh resume <name> <model>              start a new session on an existing run folder (e.g. to fix review findings)
#   run-ab.zsh review-round <name>                push the arm's branch, get a Copilot PR review, write REVIEW-N.md (see review-round.zsh)
#   run-ab.zsh review-summary <name>...           table of review rounds and findings per arm
#   run-ab.zsh review-loop <name> <model>         unattended: review-round, then a headless fix session, until CLEAN or the cap
#
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
REPO_ROOT="${SCRIPT_DIR:h:h}"
# AB_DOCS=1 builds and uses the image with the docs/ harness (planning rules); it is a separate image tag.
if [[ "${AB_DOCS:-0}" == 1 ]]; then IMAGE="${AB_IMAGE:-ab-claude-docs}"; else IMAGE="${AB_IMAGE:-ab-claude}"; fi
EXP_DIR="${AB_EXPERIMENTS_DIR:-$HOME/experiments}"
RUNS_DIR="${AB_RUNS_DIR:-$EXP_DIR/runs}"

die() { print -u2 -- "run-ab: $*"; exit 1 }

usage() {
  print -u2 -- "usage: run-ab.zsh init [dir] | build | check | run <name> <model> <src-repo> [ref] | resume <name> <model> | review-round <name> | review-summary <name>... | review-loop <name> <model>"
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
  print "see $dest/README.md for the layout and naming"
}

cmd_build() {
  docker build -f "$SCRIPT_DIR/Dockerfile" --build-arg "HOST_UID=$(id -u)" --build-arg "WITH_DOCS=${AB_DOCS:-0}" -t "$IMAGE" "$REPO_ROOT"
}

cmd_check() {
  local tmp; tmp=$(mktemp -d)
  docker run --rm --cap-add NET_ADMIN -e AB_NAME=check -e "AB_DOCS=${AB_DOCS:-0}" -v "$tmp:/work" "$IMAGE" /usr/local/bin/isolation-check.sh
  local rc=$?
  rm -rf "$tmp"
  return $rc
}

now_utc() { date -u +%FT%TZ }

# Appends one row to <run>.reviews/steps.csv (outside the run folder, so the arm cannot touch it). The cost dashboard joins
# these rows to the session logs in <run>.session by time. Columns: start,end,type,round,model,commit,detail
# type: arm (interactive run), resume (interactive resume), fix (headless fix session), review (written by review-round.zsh)
# detail: ;-separated key=value pairs, no commas.
log_step() {  # name type round model dir detail start
  local logdir="$RUNS_DIR/$1.reviews" commit
  commit=$(git -C "$5" rev-parse --short HEAD 2>/dev/null || true)
  mkdir -p "$logdir"
  [[ -f "$logdir/steps.csv" ]] || print "start,end,type,round,model,commit,detail" > "$logdir/steps.csv"
  print -r -- "$7,$(now_utc),$2,$3,$4,$commit,$6" >> "$logdir/steps.csv"
}

# Number of review rounds recorded so far for a run (0 if none).
rounds_done() {  # name
  local csv="$RUNS_DIR/$1.reviews/rounds.csv"
  [[ -f "$csv" ]] && print $(( $(wc -l < "$csv") - 1 )) || print 0
}

# Reads ANTHROPIC_API_KEY from the env file when it is not already in the environment. The file is parsed, not sourced,
# so nothing else in it can run, and it must not be readable by other users.
load_env_key() {
  [[ -z "${ANTHROPIC_API_KEY:-}" ]] || return 0
  local f="${AB_ENV_FILE:-$EXP_DIR/.env}" line mode
  [[ -f "$f" ]] || return 0
  mode=$(stat -c %a "$f" 2>/dev/null || stat -f %Lp "$f")
  [[ "$mode" == 600 || "$mode" == 400 ]] || die "$f is readable by others (mode $mode); run: chmod 600 $f"
  line=$(grep -E '^[[:space:]]*(export[[:space:]]+)?ANTHROPIC_API_KEY=' "$f" | tail -1) || true
  [[ -n "$line" ]] || return 0
  line="${line#*=}"; line="${line%\"}"; line="${line#\"}"; line="${line%\'}"; line="${line#\'}"
  [[ -n "$line" ]] || return 0
  export ANTHROPIC_API_KEY="$line"
}

# Sets the global auth_args array: an API key (default), or AB_LOGIN=1 to sign in inside the container (/login) with a
# Claude account, e.g. a Pro, Max or Enterprise plan. Login needs claude.ai and platform.claude.com reachable, so they join the firewall allowlist.
typeset -a auth_args
auth_setup() {
  auth_args=()
  local allow="api.anthropic.com ${AB_ALLOW_DOMAINS:-}"   # AB_ALLOW_DOMAINS adds to the API host, never replaces it
  if [[ "${AB_LOGIN:-0}" == 1 ]]; then
    allow="$allow claude.ai platform.claude.com"
    print "AB_LOGIN=1: not passing ANTHROPIC_API_KEY; run /login inside the session. claude.ai and platform.claude.com are allowed through the firewall."
  else
    load_env_key
    [[ -n "${ANTHROPIC_API_KEY:-}" ]] || die "ANTHROPIC_API_KEY is not set and not in ${AB_ENV_FILE:-$EXP_DIR/.env} (or use AB_LOGIN=1 to sign in with an account)"
    auth_args=(-e ANTHROPIC_API_KEY)
  fi
  auth_args+=(-e "AB_ALLOW_DOMAINS=${allow% }")
}

launch() {  # name model dir   (uses auth_args)
  local sess="$RUNS_DIR/$1.session"; mkdir -p "$sess"
  docker run --rm -it --name "ab-$1" \
    --cap-add NET_ADMIN \
    "${auth_args[@]}" \
    -e "AB_NAME=$1" \
    -v "$3:/work" \
    -v "$sess:/home/claude/.claude/projects" \
    "$IMAGE" claude --model "$2"
}

cmd_run() {
  (( $# >= 3 )) || usage
  local name="$1" model="$2" src="$3" ref="${4:-HEAD}"

  [[ "$name" =~ '^[a-z0-9]+(-[a-z0-9]+)*$' ]] || die "name must be lowercase letters, digits and hyphens (got '$name')"
  auth_setup
  git -C "$src" rev-parse --git-dir >/dev/null 2>&1 || die "$src is not a git repository"
  git -C "$src" rev-parse --verify --quiet "$ref^{commit}" >/dev/null || die "ref '$ref' not found in $src"
  docker image inspect "$IMAGE" >/dev/null 2>&1 || die "image '$IMAGE' not built; run: run-ab.zsh build"

  local srcreal runreal dir
  srcreal="${src:A}"
  dir="$RUNS_DIR/$name"
  mkdir -p "$RUNS_DIR"
  runreal="${RUNS_DIR:A}"
  [[ "$runreal/" != "$srcreal/"* ]] || die "runs folder ($runreal) is inside the source repo; set AB_RUNS_DIR elsewhere"
  [[ ! -e "$dir" ]] || die "$dir already exists; remove it or pick another name (never reuse a run)"
  local stale; for stale in "$dir.session" "$dir.reviews"; do
    [[ ! -e "$stale" ]] || die "$stale is left over from an earlier run of this name; remove it first (it would mix two runs' logs)"
  done

  # Export the files at <ref> only: no .git, no other branches, no history.
  mkdir -p "$dir"
  git -C "$src" archive "$ref" | tar -x -C "$dir"
  print "exported $(git -C "$src" rev-parse --short "$ref") to $dir (only this folder is mounted)"

  local t0 rc=0; t0=$(now_utc)
  launch "$name" "$model" "$dir" || rc=$?
  log_step "$name" arm 0 "$model" "$dir" "interactive;exit=$rc" "$t0"

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
  log_step "$name" resume "$(rounds_done "$name")" "$model" "$dir" "interactive;exit=$rc" "$t0"
  return $rc
}

# One non-interactive Claude Code turn in the arm's container (no TTY, nothing to answer). Same image, mount and firewall
# as `run`. --dangerously-skip-permissions only skips permission prompts: the container is the sandbox, and git-guard and
# auto-mode are hooks, so they still apply. AB_FIX_TIMEOUT (seconds) and AB_FIX_BUDGET_USD bound one fix session.
launch_headless() {  # name model dir prompt   (uses auth_args)
  local name="$1" model="$2" dir="$3" prompt="$4" rc=0 sess="$RUNS_DIR/$1.session"
  mkdir -p "$sess"
  timeout "${AB_FIX_TIMEOUT:-1200}" docker run --rm --name "ab-$name" \
    --cap-add NET_ADMIN \
    "${auth_args[@]}" \
    -e "AB_NAME=$name" \
    -v "$dir:/work" \
    -v "$sess:/home/claude/.claude/projects" \
    "$IMAGE" claude -p "$prompt" \
      --model "$model" \
      --dangerously-skip-permissions \
      --max-budget-usd "${AB_FIX_BUDGET_USD:-2}" || rc=$?
  if (( rc == 124 )); then docker rm -f "ab-$name" >/dev/null 2>&1 || true; print -u2 -- "run-ab: fix session timed out after ${AB_FIX_TIMEOUT:-1200}s"; fi
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
    log_step "$name" fix "$round" "$model" "$dir" "headless;exit=$fix_rc" "$t0"
    (( fix_rc == 0 )) || die "fix session failed (see $logdir/fix-$round.log); nothing was reviewed again"
    [[ "$(git -C "$dir" rev-parse HEAD)" != "$head_before" ]] || die "fix session made no new commit (see $logdir/fix-$round.log); stopping"
    [[ -z "$(git -C "$dir" status --porcelain)" ]] || die "fix session left uncommitted changes in $dir; stopping"
  done
}

(( $# >= 1 )) || usage
sub="$1"; shift
case "$sub" in
  init)  cmd_init "$@" ;;
  build) cmd_build ;;
  check) cmd_check ;;
  run)   cmd_run "$@" ;;
  resume) cmd_resume "$@" ;;
  review-loop) cmd_review_loop "$@" ;;
  review-round|review-summary) exec zsh "$SCRIPT_DIR/review-round.zsh" "$sub" "$@" ;;
  *)     usage ;;
esac
