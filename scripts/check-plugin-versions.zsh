#!/usr/bin/env zsh
# Every push that changes a plugin must raise that plugin's version.
# A change to a plugin's README.md, LICENSE or images/ at its top level does not count: those files do not ship.
#
#   scripts/check-plugin-versions.zsh [BASE_REF]
#       Compares BASE_REF (default: the upstream branch, @{u}) with HEAD. For each plugin whose
#       files changed in BASE_REF..HEAD, the "version" in its .claude-plugin/plugin.json must be
#       higher than it was at BASE_REF. Exit 1 and list the plugins that are not.
#
#   scripts/check-plugin-versions.zsh bump PLUGIN patch|minor|major
#       Raise PLUGIN's version in its plugin.json (does not commit).
#
# Why: Claude Code decides whether a plugin has an update by its version, so a change that ships
# with the same version can sit unnoticed on installed copies. The check runs at push time, so
# many commits can roll up into one version bump (put the bump in the last commit of the batch).
#
# semver: patch = fix, docs or wording; minor = new or changed behaviour; major = breaking.

set -euo pipefail
REPO_DIR="${0:A:h:h}"
cd "$REPO_DIR"

manifest_of() {   # plugin top-level dir -> its plugin.json (relative path)
  local f
  for f in "$1"/plugins/*/.claude-plugin/plugin.json(N); do print -r -- "$f"; return; done
}

version_in() {    # JSON text on stdin -> version string (empty if none)
  python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("version",""))
except Exception: print("")'
}

newer() {         # $1 > $2 as dotted integers?
  python3 - "$1" "$2" <<'PY'
import sys
t = lambda v: tuple(int(x) for x in v.split("."))
sys.exit(0 if t(sys.argv[1]) > t(sys.argv[2]) else 1)
PY
}

if [[ "${1:-}" == "bump" ]]; then
  plugin="${2:?usage: $0 bump PLUGIN patch|minor|major}"
  level="${3:?usage: $0 bump PLUGIN patch|minor|major}"
  file="$(manifest_of "$plugin")"
  [[ -n "$file" ]] || { print -u2 "no plugin.json under $plugin/plugins/*/.claude-plugin/"; exit 1; }
  python3 - "$file" "$level" <<'PY'
import json, re, sys
path, level = sys.argv[1], sys.argv[2]
text = open(path).read()
old = json.loads(text)["version"]
a, b, c = (int(x) for x in old.split("."))
new = {"patch": (a, b, c + 1), "minor": (a, b + 1, 0), "major": (a + 1, 0, 0)}[level]
new = ".".join(map(str, new))
open(path, "w").write(re.sub(r'("version"\s*:\s*")[^"]+(")', r"\g<1>" + new + r"\g<2>", text, count=1))
print(f"{path}: {old} -> {new}")
plugin = path.split("/")[0]
readme = open("README.md").read()
row = re.compile(r"(\| \[" + re.escape(plugin) + r"\]\(" + re.escape(plugin) + r"/\) \| )[^ |]+( \|)")
if row.search(readme):
    open("README.md", "w").write(row.sub(r"\g<1>" + new + r"\g<2>", readme, count=1))
    print(f"README.md: {plugin} row -> {new}")
else:
    print(f"README.md has no row for {plugin}; add one")
PY
  exit 0
fi

base="${1:-}"
[[ -n "$base" ]] || base='@{u}'
git rev-parse --verify --quiet "$base^{commit}" >/dev/null || { print -u2 "base ref not found: $base"; exit 2; }

failed=()
for manifest in */plugins/*/.claude-plugin/plugin.json(N); do
  plugin="${manifest%%/*}"
  # A plugin's README, LICENSE and images do not ship in the plugin (only plugins/ does), so changing them needs no new version.
  changed="$(git diff --name-only "$base" HEAD -- "$plugin/" | grep -v "^$manifest\$" | grep -Ev "^$plugin/(README\.md|LICENSE|images/.*)\$" || true)"
  [[ -n "$changed" ]] || continue
  old="$(git show "$base:$manifest" 2>/dev/null | version_in || true)"
  new="$(version_in < "$manifest")"
  if [[ -z "$old" ]]; then
    print "ok    $plugin: new plugin at ${new:-?}"
  elif [[ -n "$new" ]] && newer "$new" "$old"; then
    print "ok    $plugin: $old -> $new"
  else
    print "FAIL  $plugin: changed since $base but version is still ${new:-missing} (was ${old})"
    print -r -- "$changed" | sed 's/^/        /' | head -5
    failed+=("$plugin")
  fi
done

# The Version column of the README table must match each plugin.json (a README change needs no bump, so this is checked on every run).
stale=()
for manifest in */plugins/*/.claude-plugin/plugin.json(N); do
  plugin="${manifest%%/*}"
  have="$(grep -E "^\| \[$plugin\]\($plugin/\) \|" README.md | awk -F'|' '{gsub(/ /, "", $3); print $3}' || true)"
  want="$(version_in < "$manifest")"
  if [[ -z "$have" ]]; then
    print "FAIL  README.md has no table row for $plugin"; stale+=("$plugin")
  elif [[ "$have" != "$want" ]]; then
    print "FAIL  README.md lists $plugin $have but its plugin.json says $want"; stale+=("$plugin")
  fi
done
(( ${#stale[@]} )) && { print "Fix the Version column in README.md (bump does it for you)."; exit 1; }

if (( ${#failed[@]} )); then
  print ""
  print "Raise the version before pushing:  scripts/check-plugin-versions.zsh bump <plugin> patch|minor|major"
  exit 1
fi
print "plugin versions OK"
