# solver-docker — one task, one model, in a sandbox

Runs Claude Code on one task in a container that can reach only `api.anthropic.com` and sees only one exported folder. Nothing here knows about A/B
experiments, so an orchestrator can use it to hand a hard task to a stronger model, and [../ab-docker/](../ab-docker/README.md) builds its A/B runs on it.

## Use

```zsh
auto-mode/solver-docker/solver.zsh build            # once, and after plugin changes; SOLVER_DOCS=1 adds the docs/ harness (ab-claude-docs image)
auto-mode/solver-docker/solver.zsh check            # prove the isolation (filesystem, network, tooling)
ANTHROPIC_API_KEY=sk-ant-... auto-mode/solver-docker/solver.zsh solve <name> <model> <src-repo> <ref> <brief-file>
```

`solve` exports `<ref>` of `<src-repo>` (no `.git`, no history), runs one headless session on the brief, and writes `$SOLVER_RUNS_DIR/<name>.out/`
(`result.txt`, `report.txt`, `solve.patch`, `stderr.txt`). Exit 0 means DONE, at least one commit and a clean tree; 3 means BLOCKED; 4 anything else.
It always runs on the docs image and never pushes or merges anything. Optional `SOLVER_SEED_CHECK=<script>` stops a run before export when the leak check fails.

The same three commands work through `ab-docker/run-ab.zsh`, which hands them to `solver.zsh`.

To hand a task to a solver, write the brief first: [BRIEF.md](BRIEF.md) has the template, the provenance rule, a checklist, and the steps for reading the result and merging the patch.

## Files

- `BRIEF.md` — how to write a brief for `solve`, and what to check after the run.
- `solver.zsh` — the `build`, `check` and `solve` commands.
- `lib.zsh` — shared by `solver.zsh` and `ab-docker/run-ab.zsh`: image choice, auth (key or `SOLVER_LOGIN=1`), export, interactive and headless launch, the step log.
- `Dockerfile`, `entrypoint.sh`, `init-firewall.sh`, `prepare-workdir.sh`, `isolation-check.sh`, `requirements.txt` — the image, the firewall, and the checks.

## Environment variables

Every variable is named `SOLVER_<X>`. The older `AB_<X>` names are kept as aliases indefinitely (not deprecated), so existing scripts, tests, docs and permission rules keep working. Use `SOLVER_<X>` in new code. If both are set and differ,
`SOLVER_<X>` wins and a note goes to stderr. `lib.zsh` reads each pair once, then sets both, so the A/B scripts that source it can go on reading `AB_*`; the container is
given both `SOLVER_NAME` and `AB_NAME` (and the same for the allowed domains), so an image built before the rename still works.

| Variable (alias `AB_<X>`) | Meaning | Default |
|---|---|---|
| `SOLVER_DOCS` | `1` builds and uses the docs image; `solve` always sets it | `0` |
| `SOLVER_IMAGE` | image tag | `ab-claude`, or `ab-claude-docs` with `SOLVER_DOCS=1` |
| `SOLVER_EXPERIMENTS_DIR` | folder that holds `runs/` and `.env` | `~/experiments` |
| `SOLVER_RUNS_DIR` | where run folders go (outside the source repo) | `$SOLVER_EXPERIMENTS_DIR/runs` |
| `SOLVER_ENV_FILE` | file with `ANTHROPIC_API_KEY=` (chmod 600) | `$SOLVER_EXPERIMENTS_DIR/.env` |
| `SOLVER_LOGIN` | `1` signs in inside the container; `solve` refuses it | `0` |
| `SOLVER_EFFORT` | `--effort` for every session (`low` to `max`) | model default |
| `SOLVER_AGENTS_FILE` | JSON file of subagents (`claude --agents`) | none |
| `SOLVER_ALLOW_DOMAINS` | extra hosts the firewall allows | API host only |
| `SOLVER_SEED_CHECK` | leak-check script run before export | none |
| `SOLVER_SOLVE_TIMEOUT`, `SOLVER_SOLVE_BUDGET_USD` | bounds of one `solve` (seconds, dollars) | 3600, 10 |
| `SOLVER_FIX_TIMEOUT`, `SOLVER_FIX_BUDGET_USD` | bounds of one fix session | 1200, 2 |

Inside the container (set by the launcher, or by tests): `SOLVER_NAME`, `SOLVER_REMOTE`, `SOLVER_CHECK_ONLY`, `SOLVER_PLUGINS_DIR`, each with its `AB_` alias.

Not changed: the images keep their `ab-claude` names, and the per-run log folder is still `<name>.reviews/`, so the cost dashboard keeps working. The isolation guarantees and
the A/B-only options (`AB_REVIEW_REPO`, `AB_MAX_ROUNDS` and the rest of `review-round`) are documented in [../ab-docker/README.md](../ab-docker/README.md).
Tests: `ab-docker/tests/` (stubbed `docker`) and `solver-docker/tests/test-env-names.zsh`.
