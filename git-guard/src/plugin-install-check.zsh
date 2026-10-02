#!/usr/bin/env zsh
# Sourced by git-guard/deploy.zsh. Kept in its own file so tests can load it without running a deploy.
#
# deploy.zsh used to ask "is git-guard installed?" with `claude plugin list | grep -qw git-guard`, which
# is true for git-guard@ANY-marketplace. A stale git-guard@msusol from a retired marketplace therefore made
# the installer skip git-guard@losus-ai, and the commit skill stayed at an old version (2026-10-02).

# plugin_install_state <plugin> <marketplace>
# Reads `claude plugin list` output on stdin and prints exactly one of:
#   present                      <plugin>@<marketplace> is listed
#   present,other:<m1,m2>        it is listed, and <plugin> is also installed from other marketplaces
#   other:<m1,m2>                <plugin> is installed only from other marketplaces
#   absent                       <plugin> is not installed from anywhere
# Only whole names match: git-guard-extras@losus-ai and xgit-guard@losus-ai do not count as git-guard.
plugin_install_state() {
  local plugin="$1" marketplace="$2" line mk present=0
  local -a others
  local re="(^|[[:space:]])${plugin}@([A-Za-z0-9._-]+)([[:space:]]|\$)"

  while IFS= read -r line; do
    [[ $line =~ $re ]] || continue
    mk="${match[2]}"
    if [[ "$mk" == "$marketplace" ]]; then
      present=1
    else
      others+=("$mk")
    fi
  done
  others=(${(u)others})

  if (( present && ${#others} )); then
    print "present,other:${(j:,:)others}"
  elif (( present )); then
    print "present"
  elif (( ${#others} )); then
    print "other:${(j:,:)others}"
  else
    print "absent"
  fi
}
