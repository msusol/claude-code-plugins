#!/usr/bin/env zsh
# Run one A/B experiment arm in an isolated container.
#
#   run-ab.zsh build                              build the image (once, and after plugin changes)
#   run-ab.zsh check                              prove the isolation (filesystem, network, tooling)
#   run-ab.zsh run <name> <model> <src-repo> [ref]  start Claude Code on a fresh export of <ref> (default HEAD)
#
# <name> becomes the branch exp/<name> and the run folder $AB_RUNS_DIR/<name> (default ~/ab-runs/<name>).
# The container sees only that folder (as /work) and can reach only api.anthropic.com.
# Needs ANTHROPIC_API_KEY in your environment for `run`. Use a dedicated key with a spend limit:
# the model can read it inside the container.

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h:h}"
IMAGE="${AB_IMAGE:-ab-claude}"
RUNS_DIR="${AB_RUNS_DIR:-$HOME/ab-runs}"

die() { print -u2 -- "run-ab: $*"; exit 1 }

usage() {
  print -u2 -- "usage: run-ab.zsh build | check | run <name> <model> <src-repo> [ref]"
  exit 2
}

cmd_build() {
  docker build -f "$SCRIPT_DIR/Dockerfile" --build-arg "HOST_UID=$(id -u)" -t "$IMAGE" "$REPO_ROOT"
}

cmd_check() {
  local tmp; tmp=$(mktemp -d)
  docker run --rm --cap-add NET_ADMIN -e AB_NAME=check -v "$tmp:/work" "$IMAGE" /usr/local/bin/isolation-check.sh
  local rc=$?
  rm -rf "$tmp"
  return $rc
}

cmd_run() {
  (( $# >= 3 )) || usage
  local name="$1" model="$2" src="$3" ref="${4:-HEAD}"

  [[ "$name" =~ '^[a-z0-9]+(-[a-z0-9]+)*$' ]] || die "name must be lowercase letters, digits and hyphens (got '$name')"
  [[ -n "${ANTHROPIC_API_KEY:-}" ]] || die "ANTHROPIC_API_KEY is not set"
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

  docker run --rm -it --name "ab-$name" \
    --cap-add NET_ADMIN \
    -e ANTHROPIC_API_KEY \
    -e "AB_NAME=$name" \
    ${AB_ALLOW_DOMAINS:+-e "AB_ALLOW_DOMAINS=$AB_ALLOW_DOMAINS"} \
    -v "$dir:/work" \
    "$IMAGE" claude --model "$model"

  print "run folder: $dir   (git -C $dir log --oneline)"
}

(( $# >= 1 )) || usage
sub="$1"; shift
case "$sub" in
  build) cmd_build ;;
  check) cmd_check ;;
  run)   cmd_run "$@" ;;
  *)     usage ;;
esac
