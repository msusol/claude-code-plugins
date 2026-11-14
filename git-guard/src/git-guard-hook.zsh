#!/usr/bin/env zsh
# PreToolUse hook — intercepts git commit/push/tag, and non-conforming
# branch-creation names, in Bash tool calls.
# Exit 2 blocks the tool and surfaces the message to Claude.
#
# Exemption: plain `git commit` on an `exp/*` branch (see the commit block).
#
# Bypass: a command that begins with `GIT_GUARD_SANCTIONED=1 ` is treated
# as originating from the git-commit or git-push skill (the sanctioned,
# audited path), or as a deliberate, explained override of the branch-naming
# check. Both skills prepend that env-var sentinel to every git write so
# this hook stays out of the way during the confirmed workflow.
# The sentinel is intentionally visible in the command string the operator
# sees — any bypass shows up in the Bash command rendered for confirmation.

input=$(cat)

if command -v jq &>/dev/null; then
  cmd=$(echo "$input" | jq -r '.tool_input.command // ""')
  hook_cwd=$(echo "$input" | jq -r '.cwd // ""')
else
  cmd=$(echo "$input" | grep -o '"command":"[^"]*"' | sed 's/"command":"//;s/"$//')
  hook_cwd=$(echo "$input" | grep -o '"cwd":"[^"]*"' | head -1 | sed 's/"cwd":"//;s/"$//')
fi

# Sanctioned-path bypass — let the skill through. The sentinel must lead the
# command, optionally after plain `cd <dir> &&` prefixes (only cd — any other
# command before it still fails the check).
stripped=$(echo "$cmd" | sed -E 's/^[[:space:]]*(cd[[:space:]]+[^&;|]+&&[[:space:]]*)+//')
if echo "$stripped" | grep -qE '^[[:space:]]*GIT_GUARD_SANCTIONED=1[[:space:]]+'; then
  exit 0
fi

# git accepts global options between `git` and the subcommand
# (`git -C dir commit`, `git -c k=v push`, `git --git-dir=x tag`, `git --no-pager commit`).
# Match them, or those forms slip past the subcommand checks below.
GIT_GOPT='(-C[[:space:]]+[^[:space:]]+|-c[[:space:]]+[^[:space:]]+|--(git-dir|work-tree|namespace|config-env)[=[:space:]][^[:space:]]+|--[a-z][a-z-]*|-[pP])'
GIT_PRE="git([[:space:]]+${GIT_GOPT})*[[:space:]]+"

# --- Aliases ---
# An alias can hide a write (`git -c alias.x=commit x`, `git ci` with ci = commit),
# so (1) refuse to define one on the command line, in the environment, or via
# `git config`, and (2) resolve the aliases this repo/user already has and
# treat a call to one that expands to push/commit/tag as that operation.
# Shell-form aliases are matched by looking for `git ... push|commit|tag` in the
# body; scripts, wrappers and `python -c` are out of reach of a pattern match.
if echo "$cmd" | grep -qiE "(^|[[:space:]])(-c[[:space:]]*|--config-env[=[:space:]]+)alias\\.|GIT_CONFIG_(KEY_[0-9]+|PARAMETERS)=[^[:space:]]*alias\\." \
   || { echo "$cmd" | grep -qiE "${GIT_PRE}config[[:space:]].*alias\\." \
        && ! echo "$cmd" | grep -qE -- '[[:space:]]--(get|get-all|get-regexp|list)([[:space:]]|$)|[[:space:]]-l([[:space:]]|$)'; }; then
  echo "git-guard: defining a git alias is blocked in Claude Code sessions." >&2
  echo "An alias can hide git commit/push/tag from the guard. Run the git command itself," >&2
  echo "or use /git-commit or /git-push for the sanctioned path." >&2
  exit 2
fi

alias_kind=""
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  key="${line%% *}"; val="${line#* }"; name="${key#alias.}"
  [[ "$name" =~ '^[A-Za-z0-9_-]+$' ]] || continue
  echo "$cmd" | grep -qiE "${GIT_PRE}${name}([[:space:]]|\$)" || continue
  if [[ "$val" == '!'* ]]; then body="${val#!}"; else body="git $val"; fi
  if   echo "$body" | grep -qE "${GIT_PRE}push\\b";   then alias_kind=push; break
  elif echo "$body" | grep -qE "${GIT_PRE}commit\\b"; then alias_kind=commit
  elif echo "$body" | grep -qE "${GIT_PRE}tag\\b";    then [[ -z "$alias_kind" ]] && alias_kind=tag
  fi
done < <(git -C "${hook_cwd:-.}" config --get-regexp '^alias\.' 2>/dev/null)

if [[ "$alias_kind" == push ]] || echo "$cmd" | grep -qE "${GIT_PRE}push\\b"; then
  echo "git-guard: git write operation intercepted by PreToolUse hook." >&2
  echo "Do NOT attempt this git command directly." >&2
  echo "Use the /git-push skill — it verifies the remote allowlist and requires explicit confirmation for this specific push." >&2
  exit 2
fi

if [[ "$alias_kind" == (commit|tag) ]] || echo "$cmd" | grep -qE "${GIT_PRE}(commit|tag)\\b"; then
  # Experiment-branch exemption: a plain `git commit` is allowed while the
  # session's working directory is on an `exp/*` branch (A/B experiments,
  # spikes). Scoped on purpose:
  #   - commit only — `git tag` stays guarded, and the push check above has
  #     already run, so `git commit && git push` is still blocked;
  #   - the branch is read from the hook's own `cwd`, so a command that could
  #     act on a different repo (`cd`, or `-C` / `--git-dir` / `--work-tree`
  #     before the subcommand) is not exempt;
  #   - the shell wrapper still enforces the remote allowlist on the commit.
  if [[ "$alias_kind" != tag ]] && ! echo "$cmd" | grep -qE "${GIT_PRE}tag\\b" \
     && ! echo "$cmd" | grep -qE '(^|[^[:alnum:]_-])cd[[:space:]]' \
     && ! echo "$cmd" | sed -E 's/[[:space:]](commit|tag|push)([[:space:]].*)?$//' | grep -qE '(^|[[:space:]])(-C[[:space:]]|--git-dir|--work-tree)' \
     && [[ -n "$hook_cwd" && -d "$hook_cwd" ]]; then
    cur_branch=$(git -C "$hook_cwd" branch --show-current 2>/dev/null)
    if [[ "$cur_branch" == exp/* ]]; then
      exit 0
    fi
  fi
  echo "git-guard: git write operation intercepted by PreToolUse hook." >&2
  echo "Do NOT attempt this git command directly." >&2
  echo "Use the /git-commit skill — it verifies the remote allowlist, collects attribution, and requires explicit confirmation before executing." >&2
  exit 2
fi

# --- Branch naming convention (GitFlow Lite) ---
# Extract a candidate branch name from a creation command. Each pattern
# below matches exactly one token after the flag/keyword, so a start-point
# argument (e.g. `checkout -b <name> <start-point>`) or a rename's second
# argument is never mistaken for the name.
branch_name=""
match=$(echo "$cmd" | grep -oE '(checkout[[:space:]]+-[bB]|switch[[:space:]]+-[cC])[[:space:]]+[^&|;[:space:]]+' | head -1)
if [[ -n "$match" ]]; then
  branch_name="${match##* }"
else
  match=$(echo "$cmd" | grep -oE 'branch[[:space:]]+[^&|;[:space:]-][^&|;[:space:]]*' | head -1)
  if [[ -n "$match" ]]; then
    branch_name="${match##* }"
  fi
fi

if [[ -n "$branch_name" && "$branch_name" != "main" && "$branch_name" != "develop" ]]; then
  if ! echo "$branch_name" | grep -qE '^(feature|bugfix|chore)/[A-Z][A-Z0-9]+-[0-9]+-[a-z0-9]+(-[a-z0-9]+)*$' \
     && ! echo "$branch_name" | grep -qE '^(release|hotfix)/[0-9]+\.[0-9]+\.[0-9]+$' \
     && ! echo "$branch_name" | grep -qE '^exp/[a-z0-9]+(-[a-z0-9]+)*$'; then
    echo "git-guard: branch name '$branch_name' doesn't match the GitFlow (Lite) naming convention." >&2
    echo "  feature/<TICKET>-<slug>      e.g. feature/PROJ-1234-bulk-export" >&2
    echo "  bugfix/<TICKET>-<slug>       e.g. bugfix/PROJ-1301-null-pointer-on-save" >&2
    echo "  chore/<TICKET>-<slug>        e.g. chore/PROJ-1310-bump-node-20" >&2
    echo "  release/<major.minor.patch>  e.g. release/2.4.0" >&2
    echo "  hotfix/<major.minor.patch>   e.g. hotfix/2.3.1" >&2
    echo "  exp/<slug>                   e.g. exp/sonnet-vs-fable (commits allowed without /git-commit)" >&2
    echo "See the git-branch-naming rule for the full GitFlow (Lite) convention." >&2
    echo "Deliberate, explained exception: prefix with GIT_GUARD_SANCTIONED=1." >&2
    exit 2
  fi
fi

exit 0