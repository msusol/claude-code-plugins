#!/usr/bin/env bash
# Turn /work (a plain export of the base commit, no history) into a fresh one-commit repo on exp/<AB_NAME>.
# The branch name makes git-guard allow plain commits and auto-mode switch on. No-op if /work is already a repo.
set -euo pipefail

name="${AB_NAME:?AB_NAME must be set (lowercase letters, digits, hyphens)}"
[[ "$name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || { echo "prepare-workdir: bad AB_NAME '$name'" >&2; exit 1; }

[[ -d .git ]] && exit 0

git init -q -b main
git remote add origin "${AB_REMOTE:-https://example.invalid/ab/scratch}"
git add -A
git commit -q --allow-empty -m "baseline"
git checkout -q -b "exp/${name}"
