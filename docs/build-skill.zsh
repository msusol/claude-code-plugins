#!/usr/bin/env zsh
# build-skill.zsh — package skill/planning-docs/ plus src/rules/ into an
# uploadable skill zip (Claude Settings → Capabilities → Skills → Upload).
#
# src/rules/ stays the single source of truth: rules are copied into
# references/ at build time with their Claude Code frontmatter stripped.
#
# docs-plan-handoff has no references/: its SKILL.md is the whole skill, so it is
# packaged as-is.
#
# Usage: ./build-skill.zsh        writes dist/planning-docs.zip
#                                 and dist/docs-plan-handoff.zip

set -euo pipefail

REPO_DIR="${0:A:h}"
SKILL_NAME="planning-docs"
STAGE="$(mktemp -d)/$SKILL_NAME"
OUT_DIR="$REPO_DIR/dist"
RULES=(
  planning-global
  planning-docs-canonical
  planning-docs-adr
  planning-docs-specs
  planning-docs-plans
  planning-docs-process
  planning-docs-investigate
  planning-docs-artifacts
  planning-plan-sync
  planning-desync-cleanup
  planning-ai-skepticism
  planning-markdown-diagrams
  planning-markdown-codeblocks
)

mkdir -p "$STAGE/references" "$OUT_DIR"
cp "$REPO_DIR/skill/$SKILL_NAME/SKILL.md" "$STAGE/SKILL.md"

for r in $RULES; do
  src="$REPO_DIR/src/rules/$r.md"
  [[ -f "$src" ]] || { print "error: missing $src" >&2; exit 1 }
  # Drop a leading YAML frontmatter block (--- ... ---) if present.
  awk 'NR==1 && /^---$/ {fm=1; next} fm && /^---$/ {fm=0; next} !fm' "$src" \
    > "$STAGE/references/$r.md"
done

rm -f "$OUT_DIR/$SKILL_NAME.zip"
(cd "${STAGE:h}" && zip -rq "$OUT_DIR/$SKILL_NAME.zip" "$SKILL_NAME")
print "✓ Built $OUT_DIR/$SKILL_NAME.zip (${#RULES[@]} references)"

# docs-plan-handoff: SKILL.md only, no references.
HANDOFF_NAME="docs-plan-handoff"
HANDOFF_STAGE="$(mktemp -d)/$HANDOFF_NAME"
mkdir -p "$HANDOFF_STAGE"
cp "$REPO_DIR/skill/$HANDOFF_NAME/SKILL.md" "$HANDOFF_STAGE/SKILL.md"

rm -f "$OUT_DIR/$HANDOFF_NAME.zip"
(cd "${HANDOFF_STAGE:h}" && zip -rq "$OUT_DIR/$HANDOFF_NAME.zip" "$HANDOFF_NAME")
print "✓ Built $OUT_DIR/$HANDOFF_NAME.zip"
