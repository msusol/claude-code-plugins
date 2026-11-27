# CLAUDE.md — claude-code-plugins

This repo holds Claude Code plugins, each in its own top-level folder (`docs/`, `docs-hub/`,
`git-guard/`, and so on). Each plugin's version lives in one place:
`<plugin>/plugins/<plugin>/.claude-plugin/plugin.json`.

## Work goes through pull requests, and every pull request raises the version of each plugin it changes

`main` is protected: GitHub rejects a direct push ("Changes must be made through a pull request", rule GH013). Work on a branch
(`docs/<slug>`, `feat/<slug>` or `fix/<slug>`), push the branch, and open a pull request into `main`.

Claude Code decides whether an installed plugin has an update by its `version`, so a change that
ships with the same version can sit unnoticed. Rule:

- A pull request that changes anything
  under `<plugin>/` must raise that plugin's version in its `plugin.json`, except a plugin's
  top-level `README.md`, `LICENSE` and `images/`: they do not ship, so changing them needs no bump.
- Commits roll up: commit freely and leave the version alone while work is in progress. The bump
  goes in the last commit of the branch, before you push it. One bump per plugin per pull request, however
  many commits it covers.
- Pick the level: **patch** for fixes, docs or wording; **minor** for new or changed behavior;
  **major** for breaking changes.
- The plugin table in the root `README.md` has a **Version** column that must equal each
  `plugin.json`. Whenever you raise a version, update that plugin's row in the same commit (the `bump`
  command below does both), and a new plugin gets a row. The check fails when a row is missing
  or stale, even when no plugin changed.
- Check and bump with the script. Check against `origin/main`: with no argument it compares with the branch's own upstream,
  which after the first push is the branch itself, so a missing bump would pass unseen (the `git-push` skill also runs it
  before every push):

  ```zsh
  scripts/check-plugin-versions.zsh origin/main        # exit 1 if a changed plugin kept its version, or a README row is stale
  scripts/check-plugin-versions.zsh bump docs-hub minor   # raises plugin.json and the README row
  ```

  Commit the bump as `chore(<plugin>): bump to <x.y.z>`, or fold it into the last commit.
- After the pull request is merged, run `./deploy-all.zsh` (or `./deploy-all.zsh <plugin>`) to install the new version
  locally, then restart Claude Code to load it. The installed marketplace follows `main` on GitHub, so deploying before the
  merge finds nothing new ("already at the latest version").

`usage-statusline/` has no `plugin.json` (it is not a marketplace plugin) and is not checked.
