#!/usr/bin/env zsh
# Tests for `run-ab.zsh init` and the experiments template: structure, idempotence, and that the .gitignore files
# keep run folders and plan repos out of an outer repo. Stubbed docker; no network. Usage: zsh tests/test-experiments-template.zsh

HERE="${0:A:h}/.."; RUN="$HERE/run-ab.zsh"
pass=0; fail=0
ok()  { printf 'PASS  %s\n' "$1"; (( pass++ )) }
bad() { printf 'FAIL  %s\n' "$1"; (( fail++ )) }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi }

T=$(mktemp -d); E="$T/experiments"
mkdir -p "$T/bin"; printf '#!/bin/sh\nexit 0\n' > "$T/bin/docker"; chmod +x "$T/bin/docker"
# Hermetic git: fixtures are throwaway repos with fake remotes, so use the real git binary rather than any git-guard wrapper
# earlier in PATH (the wrapper guards real repos and would block these fixtures).
printf '#!/bin/sh\nexec "%s" "$@"\n' "$(command -p -v git)" > "$T/bin/git"; chmod +x "$T/bin/git"
export PATH="$T/bin:$PATH"
G() { git -c user.name=t -c user.email=t@t "$@" }

print "=== init"
out=$(zsh "$RUN" init "$E" 2>&1)
for f in README.md .gitignore .claude/settings.example.json plans/.keep plans/.gitignore runs/.keep runs/.gitignore results/index.md \
         results/TEMPLATE-comparison.md results/data/.keep docs/investigate/.keep plans/wordfreq/PLAN.md plans/wordfreq/.gitignore \
         plans/wordfreq-docs/docs/plans/0001-wordfreq.md plans/wordfreq-docs/docs/plans/TODO.md plans/wordfreq-docs/docs/index.md plans/wordfreq-docs/.gitignore; do
  check "created $f" "[[ -f $E/$f ]]"
done
check "examples/ is not copied" "[[ ! -e $E/examples ]]"
check "plan folder is a git repo with staged files, no commit" "[[ -d $E/plans/wordfreq/.git ]] && [[ -n \"\$(git -C $E/plans/wordfreq diff --cached --name-only)\" ]] && ! git -C $E/plans/wordfreq rev-parse HEAD >/dev/null 2>&1"
check "docs plan repo is a git repo with staged files, no commit" "[[ -d $E/plans/wordfreq-docs/.git ]] && git -C $E/plans/wordfreq-docs diff --cached --name-only | grep -q 'docs/plans/0001-wordfreq.md' && ! git -C $E/plans/wordfreq-docs rev-parse HEAD >/dev/null 2>&1"
check "docs plan has front matter, no number in the H1, and unchecked tasks" "head -1 $E/plans/wordfreq-docs/docs/plans/0001-wordfreq.md | grep -q '^---\$' && grep -q '^status: active' $E/plans/wordfreq-docs/docs/plans/0001-wordfreq.md && grep -q '^# Wordfreq CLI Implementation Plan\$' $E/plans/wordfreq-docs/docs/plans/0001-wordfreq.md && [[ \$(grep -c '^- \[ \]' $E/plans/wordfreq-docs/docs/plans/0001-wordfreq.md) == 4 ]]"
check "prints the next steps" "[[ \"$out\" == *'remote add origin'* && \"$out\" == *'commit -m'* ]]"
echo "my edit" >> "$E/README.md"; echo "my plan edit" >> "$E/plans/wordfreq/PLAN.md"
zsh "$RUN" init "$E" >/dev/null 2>&1
check "second init does not overwrite edited files" "grep -q 'my edit' $E/README.md && grep -q 'my plan edit' $E/plans/wordfreq/PLAN.md"
rm "$E/README.md"; zsh "$RUN" init "$E" >/dev/null 2>&1
check "second init restores a deleted template file" "[[ -f $E/README.md ]]"

print "=== .gitignore files in an outer repo"
git -C "$E" init -q -b main
mkdir -p "$E/runs/wordfreq-sonnet-r1/.git" "$E/runs/wordfreq-sonnet-r1.reviews" "$E/plans/other" "$E/results/data/2026-11-14-wordfreq-sonnet-vs-fable"
echo x > "$E/runs/wordfreq-sonnet-r1/wordfreq.py"; echo x > "$E/runs/wordfreq-sonnet-r1.reviews/rounds.csv"
echo x > "$E/plans/other/PLAN.md"; echo x > "$E/.env"; echo x > "$E/.DS_Store"; echo x > "$E/.claude/settings.local.json"
echo x > "$E/results/2026-11-14-wordfreq-sonnet-vs-fable.md"; echo x > "$E/results/data/2026-11-14-wordfreq-sonnet-vs-fable/rounds-sonnet-r1.csv"
add_out=$(git -C "$E" add -A 2>&1)
tracked=$(git -C "$E" ls-files | sort | tr '\n' ' ')
expected=".claude/settings.example.json .gitignore README.md docs/investigate/.keep plans/.gitignore plans/.keep results/2026-11-14-wordfreq-sonnet-vs-fable.md results/TEMPLATE-comparison.md results/data/.keep results/data/2026-11-14-wordfreq-sonnet-vs-fable/rounds-sonnet-r1.csv results/index.md runs/.gitignore runs/.keep "
check "tracked files are exactly the scaffold plus results" "[[ \"$tracked\" == \"$expected\" ]]"
check "run folder contents are not tracked" "! git -C $E ls-files | grep -q '^runs/wordfreq'"
check "run .reviews logs are not tracked" "! git -C $E ls-files | grep -q 'reviews'"
check "plan repos are not tracked or embedded" "! git -C $E ls-files | grep -q '^plans/[a-z]' && [[ \"$add_out\" != *'embedded'* ]]"
check ".env and .DS_Store are ignored" "! git -C $E ls-files | grep -qE '(^|/)(\.env|\.DS_Store)$'"

print "=== plan repo .gitignore, and a run end to end (stub docker)"
check "plan .gitignore ignores caches and review files" "( for p in __pycache__/a.pyc .pytest_cache/x REVIEW-1.md; do git -C $E/plans/wordfreq check-ignore -q \$p || exit 1; done )"
G -C "$E/plans/wordfreq" commit -qm "plan: wordfreq"
export ANTHROPIC_API_KEY=x AB_EXPERIMENTS_DIR="$E"; unset AB_RUNS_DIR
zsh "$RUN" run wordfreq-sonnet-r2 some-model "$E/plans/wordfreq" >/dev/null 2>&1
R="$E/runs/wordfreq-sonnet-r2"
check "run lands in <experiments>/runs by default" "[[ -f $R/PLAN.md ]]"
check "the plan's .gitignore is exported into the run" "[[ -f $R/.gitignore ]]"
(cd "$R" && AB_NAME=wordfreq-sonnet-r2 bash "$HERE/../solver-docker/prepare-workdir.sh")
mkdir -p "$R/__pycache__" "$R/.pytest_cache"; echo x > "$R/__pycache__/a.pyc"; echo x > "$R/.pytest_cache/x"; echo x > "$R/REVIEW-1.md"
printf 'REVIEW-*.md\n' >> "$R/.git/info/exclude"
check "run repo ignores caches and REVIEW files" "[[ -z \"\$(git -C $R status --porcelain)\" ]]"
check "run branch is exp/<run>" "[[ \"\$(git -C $R branch --show-current)\" == exp/wordfreq-sonnet-r2 ]]"
check "outer repo still sees nothing from the run" "[[ -z \"\$(git -C $E status --porcelain | grep 'runs/wordfreq-sonnet-r2')\" ]]"
check "run created the session folder and an arm step row" "[[ -d $E/runs/wordfreq-sonnet-r2.session ]] && grep -q ',arm,0,some-model,.*,interactive;exit=0;effort=default\$' $E/runs/wordfreq-sonnet-r2.reviews/steps.csv"
mkdir -p "$E/runs/wordfreq-sonnet-r3.session"
zsh "$RUN" run wordfreq-sonnet-r3 some-model "$E/plans/wordfreq" > "$T/out3" 2>&1; rc3=$?
check "a leftover .session folder blocks a new run of that name" "[[ $rc3 != 0 ]] && grep -q 'left over from an earlier run' $T/out3"
check "the blocked run exported nothing" "[[ ! -e $E/runs/wordfreq-sonnet-r3 ]]"
check "session and step logs are not tracked by an outer repo" "! git -C $E ls-files | grep -q 'session'"

print "=== docs harness build option"
printf '#!/bin/sh\necho "$@" >> %s/docker.log\n' "$T" > "$T/bin/docker"
unset AB_DOCS; zsh "$RUN" build >/dev/null 2>&1
check "plain build: WITH_DOCS=0 and tag ab-claude" "grep -q 'WITH_DOCS=0' $T/docker.log && grep -q -- '-t ab-claude ' $T/docker.log"
: > "$T/docker.log"; AB_DOCS=1 zsh "$RUN" build >/dev/null 2>&1
check "AB_DOCS=1 build: WITH_DOCS=1 and tag ab-claude-docs" "grep -q 'WITH_DOCS=1' $T/docker.log && grep -q -- '-t ab-claude-docs ' $T/docker.log"
: > "$T/docker.log"; AB_DOCS=1 zsh "$RUN" run wordfreq-docs-r1 some-model "$E/plans/wordfreq" >/dev/null 2>&1
check "AB_DOCS=1 run uses the docs image" "grep -q 'ab-claude-docs claude --model some-model' $T/docker.log"
check "run mounts its session folder as the container's projects dir" "grep -q -- '-v $E/runs/wordfreq-docs-r1.session:/home/claude/.claude/projects' $T/docker.log"
: > "$T/docker.log"; AB_EFFORT=medium AB_DOCS=1 zsh "$RUN" run wordfreq-docs-r2 some-model "$E/plans/wordfreq" >/dev/null 2>&1
check "AB_EFFORT=medium passes --effort medium to claude" "grep -q 'claude --model some-model --effort medium' $T/docker.log"
check "AB_EFFORT is logged in steps.csv" "grep -q 'interactive;exit=0;effort=medium\$' $E/runs/wordfreq-docs-r2.reviews/steps.csv"
check "an invalid AB_EFFORT is refused" "! AB_EFFORT=bogus zsh $RUN run wordfreq-docs-r3 some-model $E/plans/wordfreq >/dev/null 2>&1"
print '{"hard-solver":{"description":"d","prompt":"p","model":"claude-fable-5-2"}}' > "$T/agents.json"
: > "$T/docker.log"; AB_AGENTS_FILE="$T/agents.json" AB_DOCS=1 zsh "$RUN" run wordfreq-docs-r4 some-model "$E/plans/wordfreq" >/dev/null 2>&1
check "AB_AGENTS_FILE passes --agents with the JSON to an interactive run" "grep -q -- '--agents {\"hard-solver\"' $T/docker.log"
check "AB_AGENTS_FILE is logged in steps.csv" "grep -q 'interactive;exit=0;effort=default;agents=agents.json\$' $E/runs/wordfreq-docs-r4.reviews/steps.csv"
: > "$T/docker.log"; AB_DOCS=1 zsh "$RUN" run wordfreq-docs-r5 some-model "$E/plans/wordfreq" >/dev/null 2>&1
check "without AB_AGENTS_FILE no --agents is passed" "! grep -q -- '--agents' $T/docker.log"
check "and the step detail is unchanged" "grep -q 'interactive;exit=0;effort=default\$' $E/runs/wordfreq-docs-r5.reviews/steps.csv"
check "a missing AB_AGENTS_FILE is refused" "! AB_AGENTS_FILE=$T/nope.json zsh $RUN run wordfreq-docs-r6 some-model $E/plans/wordfreq >/dev/null 2>&1"
print '[1]' > "$T/bad-agents.json"; : > "$T/empty-agents.json"
check "an agents file that is not a JSON object is refused" "! AB_AGENTS_FILE=$T/bad-agents.json zsh $RUN run wordfreq-docs-r7 some-model $E/plans/wordfreq >/dev/null 2>&1"
check "an empty agents file is refused" "! AB_AGENTS_FILE=$T/empty-agents.json zsh $RUN run wordfreq-docs-r8 some-model $E/plans/wordfreq >/dev/null 2>&1"
check "Dockerfile: docs deploy is conditional and docs removed when off" "grep -q 'WITH_DOCS\" = \"1\".*docs/deploy.zsh' $HERE/../solver-docker/Dockerfile && grep -q 'rm -rf /opt/claude-code-plugins/docs' $HERE/../solver-docker/Dockerfile"

print "=== isolation-check docs section"
IC="$HERE/../solver-docker/isolation-check.sh"; H="$T/home"; P="$T/opt"
mkdir -p "$H/.claude/rules" "$P/docs"
printf '<!-- BEGIN git-guard-imports -->\n@~/.claude/rules/git-branch-naming.md\n' > "$H/.claude/CLAUDE.md"; : > "$H/.claude/rules/git-branch-naming.md"
rmdir "$P/docs"
runic() { HOME="$H" AB_PLUGINS_DIR="$P" AB_CHECK_ONLY=docs AB_DOCS="$1" bash "$IC" >/dev/null 2>&1; }
check "plain image state passes with AB_DOCS=0" "runic 0"
check "plain image state fails with AB_DOCS=1" "! runic 1"
mkdir -p "$P/docs"; : > "$H/.claude/rules/planning-docs-plans.md"
printf '<!-- BEGIN docs-imports (managed by deploy.zsh) -->\n@~/.claude/rules/planning-docs-plans.md\n<!-- END docs-imports -->\n' >> "$H/.claude/CLAUDE.md"
check "docs image state passes with AB_DOCS=1" "runic 1"
check "docs image state fails with AB_DOCS=0 (baseline contaminated)" "! runic 0"
rm "$H/.claude/rules/planning-docs-plans.md"
check "docs: missing rule file fails with AB_DOCS=1" "! runic 1"
: > "$T/docker.log"; zsh "$RUN" check >/dev/null 2>&1; AB_DOCS=1 zsh "$RUN" check >/dev/null 2>&1
check "check passes AB_DOCS into the container" "grep -q 'AB_DOCS=0' $T/docker.log && grep -q 'AB_DOCS=1' $T/docker.log"

rm -rf "$T"
print ""; printf '%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
