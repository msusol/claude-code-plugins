#!/usr/bin/env bash
# Turn /work (a plain export of the base commit, no history) into a fresh one-commit repo on exp/<SOLVER_NAME>.
# The branch name makes git-guard allow plain commits and auto-mode switch on. No-op if /work is already a repo.
set -euo pipefail

name="${SOLVER_NAME:-${AB_NAME:-}}"   # AB_NAME is the older alias
[[ -n "$name" ]] || { echo "prepare-workdir: SOLVER_NAME must be set (lowercase letters, digits, hyphens)" >&2; exit 1; }
[[ "$name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || { echo "prepare-workdir: bad SOLVER_NAME '$name'" >&2; exit 1; }

[[ -d .git ]] && exit 0

git init -q -b main
git remote add origin "${SOLVER_REMOTE:-${AB_REMOTE:-https://example.invalid/ab/scratch}}"
git add -A
git commit -q --allow-empty -m "baseline"
git checkout -q -b "exp/${name}"
