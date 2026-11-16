#!/usr/bin/env zsh
# Run one task for one model in an isolated container (no GitHub, API only, one folder mounted). Generic: nothing here knows about A/B.
#
#   solver.zsh build                                              build the image (once, and after plugin changes); AB_DOCS=1 adds the docs/ harness
#   solver.zsh check                                              prove the isolation (filesystem, network, tooling)
#   solver.zsh solve <name> <model> <src-repo> <ref> <brief-file>   unattended: export <ref>, run one headless session on the brief, write the result (see cmd_solve)
#
# ab-docker/run-ab.zsh calls build, check and solve through here; it adds A/B pairing, the interactive run, and the Copilot review loop.
# <name> becomes the branch exp/<name> and the run folder $AB_RUNS_DIR/<name> (default ~/experiments/runs/<name>).
# Auth: ANTHROPIC_API_KEY in the environment, or in $AB_ENV_FILE (default ~/experiments/.env, chmod 600). `solve` is unattended and refuses AB_LOGIN=1.
# Use a dedicated key with a spend limit: the model can read it inside the container.

set -euo pipefail
SCRIPT_DIR="${0:A:h}"
source "$SCRIPT_DIR/lib.zsh"

usage() {
  print -u2 -- "usage: solver.zsh build | check | solve <name> <model> <src-repo> <ref> <brief-file>"
  exit 2
}

cmd_build() {
  # The image installs the plugins from this checkout (see the Dockerfile); record which commit, and whether it was dirty.
  local rev; rev=$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || print unknown)
  [[ -z "$(git -C "$REPO_ROOT" status --porcelain -- .claude-plugin git-guard auto-mode docs 2>/dev/null)" ]] || rev="$rev+dirty"
  docker build -f "$SCRIPT_DIR/Dockerfile" --build-arg "HOST_UID=$(id -u)" --build-arg "WITH_DOCS=${AB_DOCS:-0}" --build-arg "SRC_REV=$rev" -t "$IMAGE" "$REPO_ROOT"
}

cmd_check() {
  local tmp; tmp=$(mktemp -d)
  docker run --rm --cap-add NET_ADMIN -e AB_NAME=check -e "AB_DOCS=${AB_DOCS:-0}" -v "$tmp:/work" "$IMAGE" /usr/local/bin/isolation-check.sh
  local rc=$?
  rm -rf "$tmp"
  return $rc
}

# Unattended solve: one headless session on a brief, for a task an orchestrator hands off (see docs/specs/sonnet-orchestrates-fable-solver.md).
# Exports <ref>, runs `claude -p "<brief text>"` in the container (same image, mount and firewall as `run`; auto-mode and git-guard
# apply because the branch is exp/*), then writes the outcome to $RUNS_DIR/<name>.out/:
#   result.txt   key=value lines: marker (DONE|BLOCKED|NONE), exit, base, head, commits, dirty, docs_files (changed under docs/), patch
#   solve.patch  `git format-patch --stdout base..head` (apply to a branch cut from <ref> with: git am --3way solve.patch)
#   report.txt   the session's final message (the solver's report; owner questions come back here, it cannot ask)
# Exit status: 0 DONE with commits and a clean tree; 3 BLOCKED; 4 no marker, no commits or uncommitted changes; else the session's own status.
# Runs on the docs image (docs/ planning rules); a standard preamble is added before the brief. Merging the result into the source
# repo (cut a branch from <ref>, git am --3way, check plan/TODO parity) is the orchestrator's job; see the spec's Coalescing section.
# Bounds: AB_SOLVE_TIMEOUT seconds (default 3600) and AB_SOLVE_BUDGET_USD (default 10). It never pushes or merges anything.
cmd_solve() {
  (( $# == 5 )) || usage
  local name="$1" model="$2" src="$3" ref="$4" brief="$5" dir
  [[ -r "$brief" && -s "$brief" ]] || die "brief file '$brief' is missing or empty"
  [[ "${AB_LOGIN:-0}" != 1 ]] || die "solve runs unattended and needs ANTHROPIC_API_KEY; AB_LOGIN=1 needs a human for /login"
  prepare_run "$name" "$src" "$ref"

  local out="$RUNS_DIR/$name.out" logdir="$RUNS_DIR/$name.reviews" t0 rc=0 marker=NONE base head commits dirty=1 code=1
  mkdir -p "$out" "$logdir"
  t0=$(now_utc)
  local preamble="Follow this repository's docs/ planning rules. Check off only the plan tasks this brief assigns you, in both the plan file and its docs/plans/TODO.md section, in the same commit as the work; do not edit other tasks, other plans or docs/index.md. Commit after each task with a Conventional Commits message that ends in a Verified: line. You cannot ask questions: put any owner question in your final report and end with AUTO-MODE: BLOCKED. When done, end with AUTO-MODE: DONE.

"
  launch_headless "$name" "$model" "$dir" "$preamble$(<"$brief")" "${AB_SOLVE_TIMEOUT:-3600}" "${AB_SOLVE_BUDGET_USD:-10}" \
    > "$out/report.txt" 2> "$out/stderr.txt" || rc=$?
  log_step "$name" solve 0 "$model" "$dir" "headless;exit=$rc;effort=${AB_EFFORT:-default}" "$t0"

  # The marker must be a line of its own, anywhere in the report (a solver often adds a recap after it, so "last line" is not
  # reliable); a mention inside a sentence does not count. If both appear, BLOCKED wins, so a question is never lost.
  if grep -qE '^[[:space:]]*AUTO-MODE: BLOCKED\.?[[:space:]]*$' "$out/report.txt"; then marker=BLOCKED
  elif grep -qE '^[[:space:]]*AUTO-MODE: DONE\.?[[:space:]]*$' "$out/report.txt"; then marker=DONE; fi

  base=$(git -C "$dir" rev-list --max-parents=0 HEAD 2>/dev/null | tail -1 || true)
  head=$(git -C "$dir" rev-parse HEAD 2>/dev/null || true)
  commits=0; [[ -n "$base" && -n "$head" ]] && commits=$(git -C "$dir" rev-list --count "$base..$head")
  [[ -z "$(git -C "$dir" status --porcelain 2>/dev/null)" ]] && dirty=0
  (( commits > 0 )) && git -C "$dir" format-patch --stdout "$base..$head" > "$out/solve.patch"
  # Files under docs/ the solver changed: these are what has to be merged with the orchestrator's own plan and TODO edits.
  local docs_files=""
  (( commits > 0 )) && docs_files=$(git -C "$dir" diff --name-only "$base..$head" -- docs | paste -sd, -)
  {
    print "marker=$marker"; print "exit=$rc"; print "base=$base"; print "head=$head"
    print "commits=$commits"; print "dirty=$dirty"; print "docs_files=$docs_files"; print "patch=$out/solve.patch"
  } > "$out/result.txt"
  print "solve $name: marker=$marker exit=$rc commits=$commits dirty=$dirty   result: $out/result.txt"

  (( rc == 0 )) || return $rc
  [[ "$marker" == BLOCKED ]] && return 3
  [[ "$marker" == DONE && $commits -gt 0 && $dirty -eq 0 ]] && code=0 || code=4
  return $code
}

(( $# >= 1 )) || usage
sub="$1"; shift
case "$sub" in
  build) cmd_build ;;
  check) cmd_check ;;
  solve) cmd_solve "$@" ;;
  *)     usage ;;
esac
