# ab-docker — isolated A/B runs

Run each arm of an A/B experiment (say, two models on the same plan) in its own container, so the model cannot
see your global `~/.claude`, your other projects, the other arm's branch, or any code that already solves the
plan. Worktrees and "a folder outside the IDE root" hide things from the IDE but not from a process running as
you; a container actually removes them.

> **Status: untested end to end.** The scripts pass syntax checks and the export/prepare logic is tested with a
> stubbed `docker`, but the image has not been built or run. Build it, then run `run-ab.zsh check` before you
> trust a result.

## What is and is not isolated

| | In the container? |
|---|---|
| Your home folder, `~/.claude` (CLAUDE.md, skills, settings, memory, history), `~/.ssh`, `gh` credentials | No. None of it is mounted |
| Your other repos and the real project's `.git` (other branches, the solution) | No. `/work` is a plain export of one commit with no history |
| The other experiment arm | No. Separate container and separate folder |
| Docker socket | No |
| Files you put in `/work` | Yes, and it is the only mount, so the only host folder it can write |
| Web access | Only `api.anthropic.com` (egress firewall); `WebFetch` and `WebSearch` are also denied in settings |
| Your API key | Yes, as an environment variable the model can read. Use a dedicated key with a spend limit |

Not covered: the model's own training data (isolation stops file access, not recall of public solutions, so pick
a task with no public solution); DNS lookups (allowed so the API host resolves, a slow side channel); anything tied
to your Claude account if you sign in instead of using an API key; Docker itself (a container is a strong boundary
but not a VM).

## Use

```zsh
# once, from anywhere (builds with the repo root as context; installs git-guard + auto-mode from GitHub main)
auto-mode/ab-docker/run-ab.zsh build

# prove the isolation before a real run
auto-mode/ab-docker/run-ab.zsh check

# one terminal per arm; the plan must be committed in <src-repo> at <ref>
export ANTHROPIC_API_KEY=sk-ant-...        # a dedicated, spend-limited key
auto-mode/ab-docker/run-ab.zsh run model-a <model-a> ~/code/ab-scratch main
auto-mode/ab-docker/run-ab.zsh run model-b <model-b> ~/code/ab-scratch main
```

`run` exports the files at `<ref>` to `~/ab-runs/<name>` (override with `AB_RUNS_DIR`; it must be outside the source
repo and must not already exist), mounts only that folder as `/work`, turns it into a fresh one-commit repo on
`exp/<name>`, and starts Claude Code. Because the branch is `exp/*`, git-guard allows plain commits and auto-mode
turns itself on. Paste the same prompt into both (see [../AB-SMOKE-TEST.md](../AB-SMOKE-TEST.md) for a cheap
task). The first launch may show Claude Code's one-time setup prompts (API key, folder trust).

## Compare

The run folders are ordinary repos on your host:

```zsh
git -C ~/ab-runs/model-a log --oneline
git -C ~/ab-runs/model-a diff --stat main
git diff --no-index --stat ~/ab-runs/model-a ~/ab-runs/model-b
(cd ~/ab-runs/model-a && pytest) ; (cd ~/ab-runs/model-b && pytest)
```

Delete a run with `rm -rf ~/ab-runs/<name>`. To keep a winner, copy the files you want into a normal branch of the
real project and commit with `/git-commit`.

## How it works

- `Dockerfile` — Node + Claude Code, a `claude` user with your host uid (so mounted files stay yours), and the
  plugin sources copied in without any git history; runs the plugins' own `deploy.zsh` to install them.
- `entrypoint.sh` — as root applies the firewall, then re-executes as `claude` with every capability dropped
  (`setpriv`, checked on a Linux host: capabilities end at zero), then prepares `/work`.
- `init-firewall.sh` — drops all outbound traffic except DNS, loopback and HTTPS to the allowlisted hosts
  (`AB_ALLOW_DOMAINS` adds more); self-tests that `example.com` fails and the API connects. Needs
  `--cap-add NET_ADMIN`, which `run-ab.zsh` passes. IP addresses are resolved once at start.
- `prepare-workdir.sh` — `git init`, a fake `origin` (`example.invalid`, allowlisted inside the image only), a
  baseline commit, branch `exp/<name>`.
- `isolation-check.sh` — the checks behind `run-ab.zsh check`.

## Known unknowns to verify on first run

- The `iptables` backend (nft vs legacy) depends on your Docker host; if `init-firewall.sh` fails, check that first.
- The env var names that quiet Claude Code's non-essential traffic can differ by version; the firewall is the real
  enforcement, so a blocked telemetry call is harmless.
- If Claude Code needs another host for your setup, add it with `AB_ALLOW_DOMAINS="api.anthropic.com host2"`.
