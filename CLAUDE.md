# CLAUDE.md — claude-code-plugins

This repo holds Claude Code plugins, each in its own top-level folder (`docs/`, `docs-hub/`,
`git-guard/`, and so on). Each plugin's version lives in one place:
`<plugin>/plugins/<plugin>/.claude-plugin/plugin.json`.

## Every push raises the version of each plugin it changes

Claude Code decides whether an installed plugin has an update by its `version`, so a change that
ships with the same version can sit unnoticed. Rule:

- A push (the repo has a single branch and no PRs, so the push is the unit) that changes anything
  under `<plugin>/` must raise that plugin's version in its `plugin.json`.
- Commits roll up: commit freely and leave the version alone while work is in progress. The bump
  goes in the last commit of the batch, before the push. One bump per plugin per push, however
  many commits it covers.
- Pick the level: **patch** for fixes, docs or wording; **minor** for new or changed behavior;
  **major** for breaking changes.
- Check and bump with the script, which the `git-push` skill also runs before every push here:

  ```zsh
  scripts/check-plugin-versions.zsh                    # exit 1 if a changed plugin kept its version
  scripts/check-plugin-versions.zsh bump docs-hub minor
  ```

  Commit the bump as `chore(<plugin>): bump to <x.y.z>`, or fold it into the last commit.
- After pushing, `./deploy-all.zsh` (or `./deploy-all.zsh <plugin>`) installs the new version
  locally; restart Claude Code to load it.

`usage-statusline/` has no `plugin.json` (it is not a marketplace plugin) and is not checked.
