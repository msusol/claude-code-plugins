#!/usr/bin/env zsh
# Checks that the verify-before-commit requirement is still present in the commit skill and rules.
# Usage: zsh tests/test-git-commit-skill.zsh
# Exit 0 = all pass, exit 1 = any failure

ROOT="${0:A:h}/../.."
SKILL="$ROOT/git-guard/plugins/git-guard/skills/git-commit/SKILL.md"
RULE="$ROOT/docs/src/rules/planning-commit-verification.md"
DESC="$ROOT/docs/src/rules/planning-commit-description.md"
pass=0
fail=0

# has FILE PATTERN DESCRIPTION: pass if the fixed string PATTERN appears in FILE
has() {
  local file="$1" pattern="$2" desc="$3"
  if grep -qF -- "$pattern" "$file" 2>/dev/null; then
    printf 'PASS  %s\n' "$desc"; (( pass++ ))
  else
    printf 'FAIL  %s — "%s" not found in %s\n' "$desc" "$pattern" "${file:t}"; (( fail++ ))
  fi
}

# line_of FILE PATTERN: first line number of the fixed string, or 0
line_of() { grep -nF -- "$2" "$1" | head -1 | cut -d: -f1 | grep . || print 0 }

# --- the skill ---------------------------------------------------------------------
has "$SKILL" "## Step 2 — Verify the change" "skill has a verify step"
has "$SKILL" "Run this before I commit:" "skill uses the explicit challenge wording"
has "$SKILL" "Not verified:" "skill names the proceed-without-evidence marker"
has "$SKILL" "Never offer a follow-up commit" "skill rules out follow-up commits for evidence"
has "$SKILL" "\`Verified:\` section" "skill requires a Verified section in the message"

verify_line=$(line_of "$SKILL" "## Step 2 — Verify the change")
stage_line=$(line_of "$SKILL" "## Step 3 — Stage files")
message_line=$(line_of "$SKILL" "## Step 6 — Commit message")
if (( verify_line > 0 && verify_line < stage_line && stage_line < message_line )); then
  printf 'PASS  verify step comes before staging and the commit message\n'; (( pass++ ))
else
  printf 'FAIL  step order wrong (verify=%s stage=%s message=%s)\n' "$verify_line" "$stage_line" "$message_line"; (( fail++ ))
fi

# --- the rules ---------------------------------------------------------------------
[[ -f "$RULE" ]] && { printf 'PASS  planning-commit-verification rule exists\n'; (( pass++ )) } \
                 || { printf 'FAIL  planning-commit-verification rule missing\n'; (( fail++ )) }
has "$RULE" "Run this before I commit:" "rule uses the explicit challenge wording"
has "$RULE" "same commit" "rule puts the evidence in the same commit"
has "$RULE" "Fail closed" "rule fails closed"
has "$DESC" "Verified" "commit-description rule defines the Verified section"

print ""
printf '%d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))
