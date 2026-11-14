#!/usr/bin/env zsh
# Host-side Copilot review loop for A/B runs (run it via run-ab.zsh; it is not run inside the container).
#
#   run-ab.zsh review-round <name>        one round: push exp/<name>, open or reuse the PR, request a Copilot
#                                         review, wait for it, and write the findings to REVIEW-N.md
#   run-ab.zsh review-summary <name>...   rounds, findings and rounds-to-clean per arm
#
# The arm containers have no GitHub access, so this runs on your host and passes findings in as a file:
#   1. the arm finishes the plan (commits on exp/<name>)
#   2. run-ab.zsh review-round <name>   -> $AB_RUNS_DIR/<name>/REVIEW-1.md (ignored by git inside the run folder)
#   3. run-ab.zsh resume <name> <model>, then paste the prompt this script prints; the arm fixes and commits
#   4. repeat from 2 until a round reports 0 findings ("clean") or the round cap is reached
# Everything is logged outside the run folder, in $AB_RUNS_DIR/<name>.reviews/ (rounds.csv, REVIEW-N.md copies),
# so the arm cannot see or edit its own history.
#
# Needs: git, gh (logged in), jq. Environment:
#   AB_REVIEW_REPO              required. owner/name of a PRIVATE scratch repo you created (code is pushed there)
#   AB_RUNS_DIR                 default ~/ab-runs
#   AB_MAX_ROUNDS               default 5
#   AB_REVIEW_TIMEOUT / _POLL   seconds to wait for Copilot (default 600) and between checks (default 15)
#   AB_COPILOT_REVIEWER         reviewer login to request (default copilot-pull-request-reviewer[bot])
#   AB_NO_REQUEST=1             do not request the review (use when the repo reviews new pushes automatically)
#   AB_ALLOW_GITHUB_DIR_CHANGES=1   allow the arm to have changed .github/ (refused by default: Copilot reads
#                               its review instructions from the PR's head branch, so an arm could soften its own reviews)
#   AB_REVIEW_REMOTE_URL        default https://github.com/$AB_REVIEW_REPO.git
#
# The push goes through your normal `git`, so git-guard's remote allowlist applies: the scratch repo's URL must
# match a pattern in ~/.config/git-guard/allowlist. Each Copilot review uses one premium request from your quota.

set -euo pipefail

RUNS_DIR="${AB_RUNS_DIR:-$HOME/ab-runs}"
REPO="${AB_REVIEW_REPO:-}"
REMOTE_URL="${AB_REVIEW_REMOTE_URL:-https://github.com/${REPO}.git}"
REVIEWER="${AB_COPILOT_REVIEWER:-copilot-pull-request-reviewer[bot]}"
MAX_ROUNDS="${AB_MAX_ROUNDS:-5}"
TIMEOUT="${AB_REVIEW_TIMEOUT:-600}"
POLL="${AB_REVIEW_POLL:-15}"

die()  { print -u2 -- "review-round: $*"; exit 1 }
warn() { print -u2 -- "review-round: $*" }

validate_name() { [[ "$1" =~ '^[a-z0-9]+(-[a-z0-9]+)*$' ]] || die "name must be lowercase letters, digits and hyphens (got '$1')" }

cmd_round() {
  (( $# == 1 )) || die "usage: review-round <name>"
  local name="$1"; validate_name "$name"
  local dir="$RUNS_DIR/$name" logdir="$RUNS_DIR/$name.reviews"
  local branch="exp/$name" base="base/$name"

  for c in git gh jq; do command -v "$c" >/dev/null || die "$c not found"; done
  [[ -n "$REPO" ]] || die "set AB_REVIEW_REPO=owner/name (a private scratch repo)"
  [[ -d "$dir/.git" ]] || die "$dir is not a started run folder"
  gh auth status >/dev/null 2>&1 || die "gh is not logged in (gh auth login)"
  [[ "$(gh api "repos/$REPO" | jq -r .private)" == true ]] || die "$REPO is not private (or not reachable); refusing to push experiment code there"

  [[ "$(git -C "$dir" branch --show-current)" == "$branch" ]] || die "$dir is not on $branch"
  [[ -z "$(git -C "$dir" status --porcelain)" ]] || die "$dir has uncommitted changes; ask the arm to commit first"
  local head; head=$(git -C "$dir" rev-parse HEAD)
  [[ "$head" != "$(git -C "$dir" rev-parse main)" ]] || die "no commits beyond the baseline yet"

  mkdir -p "$logdir"
  local -a done_rounds; done_rounds=("$logdir"/REVIEW-*.md(N))
  local round=$(( ${#done_rounds} + 1 ))
  (( round <= MAX_ROUNDS )) || die "round cap reached ($MAX_ROUNDS); raise AB_MAX_ROUNDS to go on"
  [[ ! -f "$logdir/last-head" || "$(<"$logdir/last-head")" != "$head" ]] || die "no new commits since round $(( round - 1 )); have the arm fix the findings first"

  if ! git -C "$dir" diff --quiet main HEAD -- .github; then
    [[ "${AB_ALLOW_GITHUB_DIR_CHANGES:-0}" == 1 ]] || die ".github/ differs from the baseline (Copilot reads review instructions from the head branch). Inspect: git -C $dir diff main HEAD -- .github ; override with AB_ALLOW_GITHUB_DIR_CHANGES=1"
  fi

  # Push the arm's baseline as its own base branch (each arm has its own baseline commit) and its work branch.
  [[ "$(git -C "$dir" remote get-url origin 2>/dev/null)" == "$REMOTE_URL" ]] || git -C "$dir" remote set-url origin "$REMOTE_URL"
  (( round > 1 )) || git -C "$dir" push -q origin "main:refs/heads/$base"
  git -C "$dir" push -q origin "$branch"

  local pr; pr=$(gh pr list --repo "$REPO" --head "$branch" --state open --json number | jq -r '.[0].number // empty')
  if [[ -z "$pr" ]]; then
    pr=$(gh pr create --repo "$REPO" --base "$base" --head "$branch" --title "A/B arm: $name" \
           --body "Experiment arm \`$name\`. Created by run-ab.zsh review-round." | tail -1)
    pr="${pr:t}"
  fi
  print "round $round: PR #$pr in $REPO at ${head[1,7]}"

  if [[ "${AB_NO_REQUEST:-0}" != 1 ]]; then
    gh api -X POST "repos/$REPO/pulls/$pr/requested_reviewers" -f "reviewers[]=$REVIEWER" >/dev/null 2>&1 \
      || warn "could not request '$REVIEWER' through the API; request Copilot in the PR's Reviewers menu now (waiting for it)"
  fi

  # Wait for a Copilot review of exactly this commit.
  local deadline=$(( SECONDS + TIMEOUT )) reviews rid
  while true; do
    reviews=$(gh api --paginate "repos/$REPO/pulls/$pr/reviews" | jq -s 'add // []')
    rid=$(print -r -- "$reviews" | jq -r --arg sha "$head" \
            '[.[] | select((.user.login | startswith("copilot-pull-request-reviewer")) and .commit_id == $sha)] | last | .id // empty')
    [[ -z "$rid" ]] || break
    (( SECONDS < deadline )) || die "no Copilot review of ${head[1,7]} after ${TIMEOUT}s. Check PR #$pr, then re-run (nothing was recorded for this round)"
    sleep "$POLL"
  done

  local comments mine count review_body
  comments=$(gh api --paginate "repos/$REPO/pulls/$pr/comments" | jq -s 'add // []')
  mine=$(print -r -- "$comments" | jq --argjson rid "$rid" '[.[] | select(.pull_request_review_id == $rid)]')
  count=$(print -r -- "$mine" | jq 'length')
  review_body=$(print -r -- "$reviews" | jq -r --argjson rid "$rid" '.[] | select(.id == $rid) | .body // ""')

  local out="$logdir/REVIEW-$round.md" outcome=findings
  (( count > 0 )) || outcome=clean
  {
    print "# Copilot review, round $round ($name @ ${head[1,7]})"
    print
    print -r -- "$review_body"
    print
    print "Findings: $count"
    print
    print -r -- "$mine" | jq -r '.[] | "## \(.path):\(.line // .original_line // "file")\n\n\(.body)\n"'
  } > "$out"

  print "$head" > "$logdir/last-head"
  [[ -f "$logdir/rounds.csv" ]] || print "round,time,head,pr,findings,status" > "$logdir/rounds.csv"
  print "$round,$(date -u +%FT%TZ),${head[1,7]},$pr,$count,$outcome" >> "$logdir/rounds.csv"

  if [[ "$outcome" == clean ]]; then
    print "round $round: CLEAN (0 findings). Rounds used: $round. Details: $out"
    return 0
  fi

  # Hand the findings to the arm as a file it can read but git ignores (so it is never committed or reviewed).
  cp "$out" "$dir/REVIEW-$round.md"
  grep -qxF 'REVIEW-*.md' "$dir/.git/info/exclude" 2>/dev/null || print 'REVIEW-*.md' >> "$dir/.git/info/exclude"

  print "round $round: $count findings -> $dir/REVIEW-$round.md"
  print
  print "Next: run-ab.zsh resume $name <model>   (or use the session that is still open), then paste:"
  print
  print "  Read REVIEW-$round.md and resolve every finding: fix the code or add the missing test. If you disagree with"
  print "  one, say why in your commit message. Run the tests, commit, and end with AUTO-MODE: DONE."
  print
  print "Then: run-ab.zsh review-round $name"
}

cmd_summary() {
  (( $# >= 1 )) || die "usage: review-summary <name>..."
  printf '%-16s %-7s %-10s %s\n' ARM ROUNDS CLEAN-AT FINDINGS-PER-ROUND
  local name csv rounds clean per
  for name in "$@"; do
    validate_name "$name"
    csv="$RUNS_DIR/$name.reviews/rounds.csv"
    [[ -f "$csv" ]] || { printf '%-16s %s\n' "$name" "no rounds yet"; continue }
    rounds=$(( $(wc -l < "$csv") - 1 ))
    per=$(tail -n +2 "$csv" | cut -d, -f5 | paste -sd, -)
    clean=$(tail -n +2 "$csv" | awk -F, '$6=="clean"{print $1; exit}')
    [[ -n "$clean" ]] && clean="round $clean" || clean="not yet"
    printf '%-16s %-7s %-10s %s\n' "$name" "$rounds" "$clean" "$per"
  done
}

case "${1:-}" in
  review-round)   shift; cmd_round "$@" ;;
  review-summary) shift; cmd_summary "$@" ;;
  *) die "run via: run-ab.zsh review-round <name> | review-summary <name>..." ;;
esac
