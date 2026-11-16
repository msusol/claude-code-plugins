# Shared by solver.zsh and ab-docker/run-ab.zsh (source it; do not run it). The generic sandbox pieces: image selection, auth,
# export of a ref, interactive and headless launch, and the step log. Nothing in here knows about A/B pairing or reviews.
# Callers set `set -euo pipefail` and define their own `usage`. Env vars keep their AB_ prefix (see ADR 0001, open question).

SOLVER_DIR="${${(%):-%x}:A:h}"
REPO_ROOT="${SOLVER_DIR:h:h}"
# AB_DOCS=1 builds and uses the image with the docs/ harness (planning rules); it is a separate image tag.
# `solve` always runs on the docs image: the solver must follow the docs/ planning rules (plan and TODO sync, commits).
[[ "${1:-}" == solve ]] && AB_DOCS=1
if [[ "${AB_DOCS:-0}" == 1 ]]; then IMAGE="${AB_IMAGE:-ab-claude-docs}"; else IMAGE="${AB_IMAGE:-ab-claude}"; fi
EXP_DIR="${AB_EXPERIMENTS_DIR:-$HOME/experiments}"
RUNS_DIR="${AB_RUNS_DIR:-$EXP_DIR/runs}"

die() { print -u2 -- "run-ab: $*"; exit 1 }

# AB_EFFORT (low|medium|high|xhigh|max) is passed to every Claude Code session as --effort, so both arms of a comparison run at
# the same effort. Unset, each model uses its own default, which can differ between models. The value is logged in steps.csv.
typeset -a effort_args; effort_args=()
if [[ -n "${AB_EFFORT:-}" ]]; then
  [[ "$AB_EFFORT" =~ '^(low|medium|high|xhigh|max)$' ]] || die "AB_EFFORT must be low, medium, high, xhigh or max (got '$AB_EFFORT')"
  effort_args=(--effort "$AB_EFFORT")
fi

now_utc() { date -u +%FT%TZ }

# Appends one row to <run>.reviews/steps.csv (outside the run folder, so the arm cannot touch it). The cost dashboard joins
# these rows to the session logs in <run>.session by time. Columns: start,end,type,round,model,commit,detail
# type: arm (interactive run), resume (interactive resume), fix (headless fix session), review (written by review-round.zsh),
#       solve (headless solve)
# detail: ;-separated key=value pairs, no commas.
log_step() {  # name type round model dir detail start
  local logdir="$RUNS_DIR/$1.reviews" commit
  commit=$(git -C "$5" rev-parse --short HEAD 2>/dev/null || true)
  mkdir -p "$logdir"
  [[ -f "$logdir/steps.csv" ]] || print "start,end,type,round,model,commit,detail" > "$logdir/steps.csv"
  print -r -- "$7,$(now_utc),$2,$3,$4,$commit,$6" >> "$logdir/steps.csv"
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
    "$IMAGE" claude --model "$2" "${effort_args[@]}"
}

# Validates a new run and exports <ref> of <src> to $RUNS_DIR/<name> (no .git, no history). Sets the global `dir`.
prepare_run() {  # name src ref   (calls auth_setup)
  local name="$1" src="$2" ref="$3"
  [[ "$name" =~ '^[a-z0-9]+(-[a-z0-9]+)*$' ]] || die "name must be lowercase letters, digits and hyphens (got '$name')"
  auth_setup
  git -C "$src" rev-parse --git-dir >/dev/null 2>&1 || die "$src is not a git repository"
  git -C "$src" rev-parse --verify --quiet "$ref^{commit}" >/dev/null || die "ref '$ref' not found in $src"
  docker image inspect "$IMAGE" >/dev/null 2>&1 || die "image '$IMAGE' not built; run: run-ab.zsh build"

  local srcreal runreal
  srcreal="${src:A}"
  dir="$RUNS_DIR/$name"
  mkdir -p "$RUNS_DIR"
  runreal="${RUNS_DIR:A}"
  [[ "$runreal/" != "$srcreal/"* ]] || die "runs folder ($runreal) is inside the source repo; set AB_RUNS_DIR elsewhere"
  [[ ! -e "$dir" ]] || die "$dir already exists; remove it or pick another name (never reuse a run)"
  local stale; for stale in "$dir.session" "$dir.reviews"; do
    [[ ! -e "$stale" ]] || die "$stale is left over from an earlier run of this name; remove it first (it would mix two runs' logs)"
  done

  # Optional leak check: AB_SEED_CHECK=<script> is run as `zsh <script> <src> <ref>` and must exit 0 before anything is exported.
  if [[ -n "${AB_SEED_CHECK:-}" ]]; then
    [[ -f "$AB_SEED_CHECK" ]] || die "AB_SEED_CHECK=$AB_SEED_CHECK not found"
    zsh "$AB_SEED_CHECK" "$src" "$ref" || die "seed leak check failed for $src @ $ref; nothing exported"
  fi

  # Export the files at <ref> only: no .git, no other branches, no history.
  mkdir -p "$dir"
  git -C "$src" archive "$ref" | tar -x -C "$dir"
  print "exported $(git -C "$src" rev-parse --short "$ref") to $dir (only this folder is mounted)"
}

# One non-interactive Claude Code turn in the arm's container (no TTY, nothing to answer). Same image, mount and firewall
# as `run`. --dangerously-skip-permissions only skips permission prompts: the container is the sandbox, and git-guard and
# auto-mode are hooks, so they still apply. AB_FIX_TIMEOUT (seconds) and AB_FIX_BUDGET_USD bound one fix session.
launch_headless() {  # name model dir prompt   (uses auth_args)
  local name="$1" model="$2" dir="$3" prompt="$4" rc=0 sess="$RUNS_DIR/$1.session"
  local secs="${5:-${AB_FIX_TIMEOUT:-1200}}" budget="${6:-${AB_FIX_BUDGET_USD:-2}}"   # solve passes its own, larger bounds
  mkdir -p "$sess"
  timeout "$secs" docker run --rm --name "ab-$name" \
    --cap-add NET_ADMIN \
    "${auth_args[@]}" \
    -e "AB_NAME=$name" \
    -v "$dir:/work" \
    -v "$sess:/home/claude/.claude/projects" \
    "$IMAGE" claude -p "$prompt" \
      --model "$model" \
      "${effort_args[@]}" \
      --dangerously-skip-permissions \
      --max-budget-usd "$budget" || rc=$?
  if (( rc == 124 )); then docker rm -f "ab-$name" >/dev/null 2>&1 || true; print -u2 -- "run-ab: headless session timed out after ${secs}s"; fi
  return $rc
}
