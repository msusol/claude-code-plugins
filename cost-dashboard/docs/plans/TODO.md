# TODO

## 0001 Cost dashboard plugin

- [x] Parse session logs and de-duplicate streamed assistant messages
- [x] Aggregate cost per session, task, model, day, and subagent
- [x] Self-contained HTML template (KPIs, daily chart, model table, expandable sessions)
- [x] Verify totals against a hand calculation on synthetic logs
- [x] Create `cost-dashboard/plugins/cost-dashboard/` with `plugin.json`, command, scripts, `pricing.json`
- [x] Add `deploy.zsh`, `uninstall.zsh`, `README.md`, `LICENSE`
- [x] Add the `git-subdir` entry to `.claude-plugin/marketplace.json`
- [x] Add the plugin to the root `README.md` (table, deploy and uninstall lists)
- [ ] Run `/cost-dashboard:dashboard` against real logs and sanity-check the totals
- [ ] Verify `pricing.json` rates against current Anthropic pricing
- [ ] Install via `./deploy.zsh` and confirm the command appears as `/cost-dashboard:dashboard`
- [ ] Commit on a `feature/` branch and open a PR
- [ ] Attribute separate-file subagent cost to the task that spawned it
- [ ] Optional `SessionEnd` hook to refresh the dashboard automatically
- [ ] Per-project grouping view
- [ ] Token-type breakdown per task (input, output, cache write, cache read)

## Next steps

### 0001 Cost dashboard plugin

1. Run the command against real logs and sanity-check the totals.
2. Verify `pricing.json` rates against current pricing.
3. Install via `./deploy.zsh`, then commit on a `feature/` branch and open a PR.
