#!/usr/bin/env zsh
# Sourced by kaggle/deploy.zsh. Kept in its own file so tests can load it without running a deploy.
#
# The kaggle rules belong in a Kaggle workspace root. deploy.zsh defaults its target to $PWD, and
# deploy-all.zsh runs every plugin's deploy from wherever it is invoked, so running deploy-all from
# the claude-code-plugins checkout made that checkout the target and wrote .claude/rules/ and a
# CLAUDE.md into it (2026-10-02). Those files then load kaggle rules into any session started there.

# target_is_plugin_repo <target-dir> <plugin-repo-root>
# Succeeds when <target-dir> is the plugin repo itself or anywhere inside it. Both paths are resolved
# (symlinks followed) first. A sibling that merely shares a name prefix, such as
# /x/claude-code-plugins-other, is not inside /x/claude-code-plugins.
target_is_plugin_repo() {
  local target="${1:A}" repo_root="${2:A}"
  [[ "$target" == "$repo_root" || "$target" == "$repo_root"/* ]]
}
