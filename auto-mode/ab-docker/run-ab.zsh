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
#
# <name> becomes the branch exp/<name> and the run folder $AB_RUNS_DIR/<name> (default ~/experiments/runs/<name>).
# The container sees only that folder (as /work) and can reach only api.anthropic.com.
# Auth for `run`: ANTHROPIC_API_KEY in the environment (pass it inline, not exported: ANTHROPIC_API_KEY=... run-ab.zsh run ...),
# or AB_LOGIN=1 to sign in with a Claude account inside the container. Use a dedicated key with a spend limit:
# the model can read it inside the container.

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h:h}"
# AB_DOCS=1 builds and uses the image with the docs/ harness (planning rules); it is a separate image tag.
if [[ "${AB_DOCS:-0}" == 1 ]]; then IMAGE="${AB_IMAGE:-ab-claude-docs}"; else IMAGE="${AB_IMAGE:-ab-claude}"; fi
EXP_DIR="${AB_EXPERIMENTS_DIR:-$HOME/experiments}"
RUNS_DIR="${AB_RUNS_DIR:-$EXP_DIR/runs}"

die() { print -u2 -- "run-ab: $*"; exit 1 }

usage() {
  print -u2 -- "usage: run-ab.zsh init [dir] | build | check | run <name> <model> <src-repo> [ref] | resume <name> <model> | review-round <name> | review-summary <name>..."
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
  docker run --rm --cap-add NET_ADMIN -e AB_NAME=check -v "$tmp:/work" "$IMAGE" /usr/local/bin/isolation-check.sh
  local rc=$?
  rm -rf "$tmp"
  return $rc
}

# Sets the global auth_args array: an API key (default), or AB_LOGIN=1 to sign in inside the container (/login) with a
# Claude account, e.g. Enterprise. Login needs claude.ai and platform.claude.com reachable, so they join the firewall allowlist.
typeset -a auth_args
auth_setup() {
  auth_args=()
  local allow="api.anthropic.com ${AB_ALLOW_DOMAINS:-}"   # AB_ALLOW_DOMAINS adds to the API host, never replaces it
  if [[ "${AB_LOGIN:-0}" == 1 ]]; then
    allow="$allow claude.ai platform.claude.com"
    print "AB_LOGIN=1: not passing ANTHROPIC_API_KEY; run /login inside the session. claude.ai and platform.claude.com are allowed through the firewall."
  else
    [[ -n "${ANTHROPIC_API_KEY:-}" ]] || die "ANTHROPIC_API_KEY is not set (or use AB_LOGIN=1 to sign in with an account)"
    auth_args=(-e ANTHROPIC_API_KEY)
  fi
  auth_args+=(-e "AB_ALLOW_DOMAINS=${allow% }")
}

launch() {  # name model dir   (uses auth_args)
  docker run --rm -it --name "ab-$1" \
    --cap-add NET_ADMIN \
    "${auth_args[@]}" \
    -e "AB_NAME=$1" \
    -v "$3:/work" \
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

  # Export the files at <ref> only: no .git, no other branches, no history.
  mkdir -p "$dir"
  git -C "$src" archive "$ref" | tar -x -C "$dir"
  print "exported $(git -C "$src" rev-parse --short "$ref") to $dir (only this folder is mounted)"

  launch "$name" "$model" "$dir"

  print "run folder: $dir   (git -C $dir log --oneline)"
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
  launch "$name" "$model" "$dir"
}

(( $# >= 1 )) || usage
sub="$1"; shift
case "$sub" in
  init)  cmd_init "$@" ;;
  build) cmd_build ;;
  check) cmd_check ;;
  run)   cmd_run "$@" ;;
  resume) cmd_resume "$@" ;;
  review-round|review-summary) exec zsh "$SCRIPT_DIR/review-round.zsh" "$sub" "$@" ;;
  *)     usage ;;
esac
