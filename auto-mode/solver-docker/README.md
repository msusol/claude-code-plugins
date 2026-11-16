# solver-docker — one task, one model, in a sandbox

Runs Claude Code on one task in a container that can reach only `api.anthropic.com` and sees only one exported folder. Nothing here knows about A/B
experiments, so an orchestrator can use it to hand a hard task to a stronger model, and [../ab-docker/](../ab-docker/README.md) builds its A/B runs on it.

## Use

```zsh
auto-mode/solver-docker/solver.zsh build            # once, and after plugin changes; AB_DOCS=1 adds the docs/ harness (ab-claude-docs image)
auto-mode/solver-docker/solver.zsh check            # prove the isolation (filesystem, network, tooling)
ANTHROPIC_API_KEY=sk-ant-... auto-mode/solver-docker/solver.zsh solve <name> <model> <src-repo> <ref> <brief-file>
```

`solve` exports `<ref>` of `<src-repo>` (no `.git`, no history), runs one headless session on the brief, and writes `$AB_RUNS_DIR/<name>.out/`
(`result.txt`, `report.txt`, `solve.patch`, `stderr.txt`). Exit 0 means DONE, at least one commit and a clean tree; 3 means BLOCKED; 4 anything else.
It always runs on the docs image and never pushes or merges anything. Optional `AB_SEED_CHECK=<script>` stops a run before export when the leak check fails.

The same three commands work through `ab-docker/run-ab.zsh`, which hands them to `solver.zsh`.

## Files

- `solver.zsh` — the `build`, `check` and `solve` commands.
- `lib.zsh` — shared by `solver.zsh` and `ab-docker/run-ab.zsh`: image choice, auth (key or `AB_LOGIN=1`), export, interactive and headless launch, the step log.
- `Dockerfile`, `entrypoint.sh`, `init-firewall.sh`, `prepare-workdir.sh`, `isolation-check.sh`, `requirements.txt` — the image, the firewall, and the checks.

## Not changed yet

The environment variables keep their `AB_` prefix, the images keep their `ab-claude` names, and the per-run log folder is still `<name>.reviews/`, so the cost
dashboard keeps working. Options, bounds, the API-key file, `AB_LOGIN` and the isolation guarantees are documented in [../ab-docker/README.md](../ab-docker/README.md)
until they are worth moving here. Tests: `ab-docker/tests/` (stubbed `docker`).
