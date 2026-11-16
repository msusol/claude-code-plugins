# ab-docker — isolated A/B runs

Run each arm of an A/B experiment (say, two models on the same plan) in its own container, so the model cannot
see your global `~/.claude`, your other projects, the other arm's branch, or any code that already solves the
plan. Worktrees and "a folder outside the IDE root" hide things from the IDE but not from a process running as
you; a container actually removes them.

> **Layering.** The generic sandbox (image, firewall, isolation check, export of a ref, interactive and headless launch, `solve`) lives in
> [../solver-docker/](../solver-docker/README.md); this folder adds the A/B parts (experiments folder, `run` and `resume`, the Copilot
> review loop). `run-ab.zsh build`, `check` and `solve` hand over to `solver-docker/solver.zsh`, so every command here still works as before.
> See ADR 0001 in the experiments repo.

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
# once: create the experiments folder (plans/, runs/, results/, docs/) from the template, with .keep and .gitignore files
auto-mode/ab-docker/run-ab.zsh init            # default ~/experiments; see experiments-template/README.md

# once, from anywhere (builds with the repo root as context; installs git-guard + auto-mode from this checkout, not GitHub main)
auto-mode/ab-docker/run-ab.zsh build

# prove the isolation before a real run
auto-mode/ab-docker/run-ab.zsh check

# one terminal per arm; name runs <plan>-<model>-r<N>; the plan must be committed in <src-repo> at <ref>.
# Pass the key inline (do not export it): a shell-wide ANTHROPIC_API_KEY makes Claude Code use API billing
# instead of your subscription everywhere you run it.
ANTHROPIC_API_KEY=sk-ant-... auto-mode/ab-docker/run-ab.zsh run wordfreq-model-a-r1 <model-a> ~/experiments/plans/wordfreq main
ANTHROPIC_API_KEY=sk-ant-... auto-mode/ab-docker/run-ab.zsh run wordfreq-model-b-r1 <model-b> ~/experiments/plans/wordfreq main
```

`run` exports the files at `<ref>` to `~/experiments/runs/<name>` (override with `AB_RUNS_DIR`, or move everything with `AB_EXPERIMENTS_DIR`; it must be outside the source
repo and must not already exist), mounts only that folder as `/work`, turns it into a fresh one-commit repo on
`exp/<name>`, and starts Claude Code. Because the branch is `exp/*`, git-guard allows plain commits and auto-mode
turns itself on. Paste the same prompt into both (see [../AB-SMOKE-TEST.md](../AB-SMOKE-TEST.md) for a cheap
task). The first launch may show Claude Code's one-time setup prompts (API key, folder trust).

## Letting an assistant run the arms (opt-in permissions)

By default a Claude Code session on the host cannot start the arms for you: `tmux new-session`, `run-ab.zsh run`, `resume` and `review-loop` are blocked until allowed
(the unattended loop pushes to GitHub and runs headless sessions, so it is rightly gated). `run-ab.zsh init` copies
[experiments-template/.claude/settings.example.json](experiments-template/.claude/settings.example.json) to `~/experiments/.claude/settings.example.json`. It is inert:
review it and merge its `permissions.allow` entries into `~/experiments/.claude/settings.local.json` yourself. The plugin does not install it, and `init` does not
overwrite or create `settings.local.json`, so nothing becomes permitted unless you add it. Set the API workspace spend limit first; it is the real cap on what a permitted
session can spend. Details and what each entry allows: [experiments-template/README.md](experiments-template/README.md).

## Pinning the effort level

`AB_EFFORT=medium` (or `low`, `high`, `xhigh`, `max`) is passed to every Claude Code session as `--effort`: `run`, `resume` and the headless fix sessions of `review-loop`.
Set the same value for every arm of a comparison; unset, each model uses its own default, which can differ between models. Use the same value for `run`, `resume` and
`review-loop`. The value is logged in each `steps.csv` row (`effort=medium`, or `effort=default`). An invalid value is refused. Confirm it in a transcript on the first run.

## Adding the docs/ harness

The default image has Claude Code, git-guard and auto-mode only. To test with the `docs/` plugin's planning rules too
(installed to `~/.claude/rules/` and @-imported from `~/.claude/CLAUDE.md` inside the container):

```zsh
AB_DOCS=1 auto-mode/ab-docker/run-ab.zsh build     # image ab-claude-docs; the plain ab-claude image is untouched
AB_DOCS=1 ANTHROPIC_API_KEY=... auto-mode/ab-docker/run-ab.zsh run wordfreq-sonnet-docs-r1 <model> ~/experiments/plans/wordfreq main
```

Use the same `AB_DOCS` value for `build`, `run` and `resume`; `review-round` needs no change. Notes:

- Both arms of a comparison must use the same image, and the results file's `harness:` line should say so.
- The rules work against the plan repo's own `docs/` folder (plans, ADRs), so the plan you export should include one.
- The plain image deletes the docs sources at build time, so a baseline arm cannot read the planning rules. `run-ab.zsh check`
  verifies this: with `AB_DOCS=1` it requires the rules, their imports and the plugin; without it, it requires their absence.
- The docs rules and the plugins themselves come from your checkout at build time, not from GitHub `main` (the build rewrites the marketplace entries to the copied folders), so
  the image is exactly the checkout, pushed or not. Rebuild after changing them. The commit it was built from is in the image label `ab.source-rev` (`+dirty` if uncommitted
  changes were copied in): `docker image inspect <image> --format '{{ index .Config.Labels "ab.source-rev" }}'`. Put it, and the plugin versions, on the results file's `harness:` line.
  Before this change the image fetched each plugin from GitHub `main` and could be older than the checkout (a pilot ran auto-mode 1.7.0 while the checkout had 1.9.0).
- Other plugins (e.g. docs-hub) can be added the same way: copy the folder, run its `deploy.zsh` under a build arg.

## Experiments folder

`run-ab.zsh init` copies [experiments-template/](experiments-template/README.md) to `~/experiments` (or the folder you
name; it never overwrites a file that exists, so re-running is safe):

```
~/experiments/
├── plans/    one git repo per plan (so an arm only sees its own plan); contents ignored, .keep tracked
├── runs/     <plan>-<model>-r<N>/ run folders and their .reviews/ logs; contents ignored, .keep tracked
├── results/  index.md, TEMPLATE-comparison.md, data/   <- what you keep
└── docs/investigate/
```

It needs no git repo of its own. If you make it one, the `.gitignore` files in `runs/` and `plans/` keep every run folder
and nested plan repo out, and `.env` and `.DS_Store` are ignored at the top. The template's README has the naming
convention and the first-plan steps (`init` stages the example `plans/wordfreq` but does not commit it, because git-guard
needs an allowlisted `origin`; give it one that is never pushed).

## Python libraries for a task

The container has no network at run time, so a task cannot `pip install` anything; the libraries it needs go into the
image at build time. List them in [requirements.txt](../solver-docker/requirements.txt) (one per line, versions pinned so every arm gets the
same ones), then rebuild with `run-ab.zsh build`. The file ships with no requirements, which is right for a task that uses
only the standard library, like the wordfreq smoke test.

- They are installed into a virtualenv at `~/.venv` in the image that also sees the OS packages (pytest), and it is
  first on `PATH`, so `python`, `python3` and `pip` all work and mean the same thing.
- The exact installed set is recorded in `~/.ab-pip-freeze.txt` in the image; read it with
  `docker run --rm --entrypoint "" ab-claude cat /home/claude/.ab-pip-freeze.txt`.
- The image sets `PIP_NO_BUILD_ISOLATION=0`, so an arm can run `pip install -e .` on its own `pyproject.toml` offline (setuptools and wheel are in the venv; with isolation pip would try to
  download setuptools and the firewall blocks it). No `PYTHONPATH` is set, so an arm that relies on one still has to document it.
- Changing the file changes the image, so arms built before and after it are not on the same image. Build once, run
  every arm of a comparison on that image, and note the image id and `requirements.txt` with the results.
- Libraries are fetched from PyPI during the build, where the network is open. Packages that need system libraries
  (compilers, headers) may also need an `apt-get` line in the Dockerfile.

## Getting a spend-limited API key

A Claude subscription (Max, Team, Enterprise) and the Claude Console are separate products, and API usage is billed
through the Console. For experiments, use a personal Console account:

1. Sign in at platform.claude.com. One email address can create one Console organization.
2. Add a small prepaid balance (say $10-20) and leave auto-reload off. The balance is itself a hard cap.
3. Create a workspace such as `ab-experiments` (the Default Workspace cannot have limits).
4. On the Workspaces page, open the workspace, choose Spend limits, and set a monthly cap with alerts. You can also
   set an organization limit under Billing.
5. Create the API key inside that workspace and use only it for experiments.

Monthly API credits that come with some plans may not apply to Claude Code; check how they apply before relying on them.

## Using a Claude subscription (Pro, Max, Team, Enterprise) instead of a key

If you have a personal subscription such as Claude Max, you can run the test with no Console account and no key:

```zsh
AB_LOGIN=1 auto-mode/ab-docker/run-ab.zsh run wordfreq-model-a-r1 <model-a> ~/experiments/plans/wordfreq main
# then run /login inside the session and follow the URL it prints in your host browser
```

`AB_LOGIN=1` never passes `ANTHROPIC_API_KEY` into the container, even if your shell has one exported, so the
session bills your subscription. It also adds `claude.ai` and `platform.claude.com` to the firewall allowlist so
sign-in works. Start the second arm the same way in its own terminal; each container needs its own `/login`.

What to expect with a personal plan such as Max:

- **Limits, not dollars.** Usage counts against your plan's usage limits, shared with claude.ai and Claude Code on
  your host. There is no spend cap to set, but a runaway arm can use up your current window and lock you out of your
  everyday sessions until it resets. The smoke test is small (four steps per arm, and auto-mode's continuation cap
  stops a loop), so run it when you don't need the headroom, and check your plan's usage view afterward.
- **Check extra-usage billing.** If your plan allows paid extra usage beyond the limits, make sure it is off, or
  capped, in your account settings before the run, so hitting a limit stops the run instead of billing you.
- **Model access depends on the plan.** Pick two models your plan includes for `<model-a>` and `<model-b>`.
- **Sign in every run.** The token lives in the container's own `~/.claude` and is discarded when the container
  exits. The model can read it while the session runs, which is the main isolation cost of this path.
- **Weaker isolation than a key.** Opening `claude.ai` gives the model a general website to talk to, not just an
  API. The allowlist is IP-based and resolved once at start, and sites behind shared CDNs can rotate addresses, so
  sign-in may be flaky. Run `run-ab.zsh check` and ask the session what tools it has before trusting a result.
- **Team and Enterprise accounts** can also bring organization-managed settings and connectors into the container,
  and the spend cap is set by an admin. Check your employer's policy before using a company account.

This login path has not been tested. For the fairest, most contained comparison, the spend-limited key above is
still the safer choice; the subscription is the convenient one.

## Compare

The run folders are ordinary repos on your host:

```zsh
git -C ~/experiments/runs/model-a log --oneline
git -C ~/experiments/runs/model-a diff --stat main
git diff --no-index --stat ~/experiments/runs/model-a ~/experiments/runs/model-b
(cd ~/experiments/runs/model-a && pytest) ; (cd ~/experiments/runs/model-b && pytest)
```

Delete a run with `rm -rf ~/experiments/runs/<name>`. To keep a winner, copy the files you want into a normal branch of the
real project and commit with `/git-commit`.

## Copilot review loop (host side)

To measure how many Copilot review rounds each arm needs, run the review from your host. The arm containers have no
GitHub access, so findings reach the arm as a file. Setup once: a **private** scratch repo (`gh repo create ab-review-scratch
--private`), its URL allowlisted in `~/.config/git-guard/allowlist` (pushes go through your normal `git`), and `gh`
logged in with your Copilot-licensed account. The Copilot code-review policy must be enabled for your org.
Use a repo that only does this job, never a seed or plan repo: the loop pushes each arm's `base/<name>` and `exp/<name>` branches and opens a PR
per arm, and those would mix unrelated histories and full solutions into the seed. (The author's was `ab-scratch`, renamed `ab-review-scratch`; GitHub redirects the old name.)

```zsh
export AB_REVIEW_REPO=msusol/ab-review-scratch            # owner/name of the scratch repo
auto-mode/ab-docker/run-ab.zsh review-round model-a   # push exp/model-a, open the PR, request Copilot, wait,
                                                      # write ~/experiments/runs/model-a/REVIEW-1.md
auto-mode/ab-docker/run-ab.zsh resume model-a <model-a>   # new session on the same folder; paste the printed prompt
auto-mode/ab-docker/run-ab.zsh review-round model-a   # round 2 ... until it prints CLEAN or hits AB_MAX_ROUNDS (5)
auto-mode/ab-docker/run-ab.zsh review-summary model-a model-b
```

Per arm it records `round, time, commit, pr, findings, status` in `~/experiments/runs/<name>.reviews/rounds.csv` (outside the
run folder, so the arm cannot touch it), and `review-summary` prints rounds, findings per round, and the round that
first came back clean. Pair it with a separate API key per arm to compare model cost against Copilot rounds and reviews. GitHub bills
code review in AI credits ($0.01 each) from your plan's included credits, not per request; one review averaged about 29 credits ($0.29) over
8 reviews in our runs, and the dashboard's A/B tab uses that average. Read the real usage at github.com/settings/billing/ai_usage.

Guard rails and caveats:

- Each arm gets its own base branch (`base/<name>`, its baseline commit) and PR (`exp/<name>`), because the arms'
  baselines are separate commits.
- It refuses if the repo is not private, the run folder has uncommitted changes, there are no new commits since the
  last round, or `.github/` differs from the baseline (Copilot reads review instructions from the PR's head branch,
  so an arm could soften its own reviews; override with `AB_ALLOW_GITHUB_DIR_CHANGES=1` after inspecting the diff).
- Copilot does not re-review on its own after a push, so each round requests it (`AB_COPILOT_REVIEWER`, default
  `copilot-pull-request-reviewer[bot]`). If the API request fails you get a warning and the script keeps waiting while
  you click Copilot in the PR's Reviewers menu. `AB_NO_REQUEST=1` skips the request for repos that review pushes automatically.
- Copilot leaves "Comment" reviews only, so "clean" means no new inline comments, not an approval.
- Copilot varies from run to run: repeat each arm 3 or more times before drawing a conclusion.
- Tested with a stubbed `gh` and a local bare repo (`tests/test-review-round.zsh`). **Not tested against GitHub:** the
  reviewer login, the requested-reviewers API call, and the shape of Copilot's review and comment objects.

## Session logs and the step log (for cost reporting)

The arm's container is removed when it exits, so its Claude Code transcripts used to vanish with it. Now every container
(`run`, `resume` and the headless fix sessions of `review-loop`) mounts `$AB_RUNS_DIR/<run>.session` as its `~/.claude/projects`,
so the transcripts land on the host, outside the run folder where the arm works. The cost dashboard can read them with
`--root $AB_RUNS_DIR/<run>.session`.

`$AB_RUNS_DIR/<run>.reviews/steps.csv` records each step so Claude sessions and Copilot rounds can be told apart and priced:

```text
start,end,type,round,model,commit,detail
2026-11-15T05:07:08Z,2026-11-15T05:07:20Z,review,1,copilot,af4ca71,pr=3;findings=1;status=findings;premium_requests=1;effort=balanced
2026-11-15T05:07:21Z,2026-11-15T05:08:40Z,fix,1,claude-fable-5-2,dbc3b50,headless;exit=0
```

- `type` is `arm` (`run`), `resume`, `fix` (headless) or `review` (`review-round`). `start` and `end` are UTC; a session belongs to the
  step whose window it falls in.
- GitHub bills code review in AI credits and no API gives a per-review price, so a `review` row records the review count
  (`premium_requests=1`, or 0 with `AB_NO_REQUEST=1`) and the effort Copilot reports, not dollars. `premium_requests` is the key's historical name;
  it counts review requests, not billing units. The cost dashboard turns the count into an estimate.
- `run` refuses a name whose `.session` or `.reviews` folder is left over from an earlier run, because two runs' logs would mix.
  Remove both when you remove the run folder, after copying out what you want to keep.

## Unattended review loop (`review-loop`)

`run-ab.zsh review-loop <name> <model>` runs the whole Copilot loop without a human: `review-round`, then a headless fix
session (`claude -p`, no TTY) in the arm's container, then `review-round` again, until a round is CLEAN or `AB_MAX_ROUNDS`
(default 5). auto-mode keeps each fix turn going until `AUTO-MODE: DONE`, but it cannot wait for GitHub, so the loop around
it runs on the host. The arm still never gets GitHub access: pushes and the Copilot wait happen on the host.

```zsh
AB_DOCS=1 AB_REVIEW_REPO=msusol/ab-review-scratch auto-mode/ab-docker/run-ab.zsh review-loop wordfreq-docs-fable-r1 claude-fable-5-2
```

- **Needs an API key.** `/login` needs a human, so `AB_LOGIN=1` is refused. Put the key in `~/experiments/.env` (see below).
- **Fails closed.** It stops if a fix session fails, makes no commit, or leaves uncommitted changes, and prints where the log is
  (`<run>.reviews/fix-N.log`). Re-running it continues from the last recorded round.
- **Bounds per fix session:** `AB_FIX_TIMEOUT` (seconds, default 1200) and `AB_FIX_BUDGET_USD` (default 2, passed as `--max-budget-usd`).
- **Permissions:** the session runs with `--dangerously-skip-permissions`, which only skips prompts. The container (firewall, only
  `/work` mounted) is the sandbox, and git-guard and auto-mode are hooks that still apply.
- **Not yet run against real Claude Code or GitHub.** The tests use stubbed `gh` and `docker`. Try it on one arm first and
  read `fix-1.log`.

## One task for one model (`solve`)

`run-ab.zsh solve <name> <model> <src-repo> <ref> <brief-file>` runs one headless session (`claude -p`) in the same sandbox as an arm,
with the docs/ harness (`AB_DOCS=1` is implied). The brief file is the task. The session is told to follow the repo's docs/ planning
rules, check off only the plan tasks the brief assigns it, and end with `AUTO-MODE: DONE` (or `AUTO-MODE: BLOCKED` plus its question).
It never gets GitHub access and cannot ask questions; a decision it needs comes back as BLOCKED.

```zsh
auto-mode/ab-docker/run-ab.zsh solve fix-parser claude-fable-5-2 ~/proj main ~/briefs/fix-parser.md
```

- **Output** goes to `$AB_RUNS_DIR/<name>.out/`: `result.txt` (keys `marker`, `exit`, `base`, `head`, `commits`, `dirty`, `docs_files`,
  `patch`, which is the path of `solve.patch`, or empty when the solver made no commit and so there is no patch), `report.txt` (the final
  message), `solve.patch` (only when there is a commit) and `stderr.txt`.
- **Exit codes:** 0 = a line of its own saying `AUTO-MODE: DONE` anywhere in the report (a recap after it is fine), at least one commit, clean tree; 3 = a `AUTO-MODE: BLOCKED` line (it wins if both appear); 4 = anything else. Apply the
  patch to a branch of the source with `git am --3way solve.patch`, then check that the plan and `TODO.md` agree.
- **Bounds:** `AB_SOLVE_TIMEOUT` (seconds, default 3600) and `AB_SOLVE_BUDGET_USD` (default 10). Needs an API key; `AB_LOGIN=1` is refused.
- **Not yet run against real Docker or the API.** The tests use a stubbed `docker`. Run one real task first and read `report.txt`.
- Do not put untrusted text (ticket or web content) in a brief as instructions; see the spec in the experiments repo.

## Checking the seed before export (`AB_SEED_CHECK`)

`prepare_run` can run a leak check before it exports anything. Set `AB_SEED_CHECK` to a script; it is run as
`zsh <script> <src-repo> <ref>`, and a non-zero exit stops the run with nothing exported. A missing script also stops the run.
The experiments repo ships one, `scripts/check-seed.zsh`, which fails if the exported ref has a `.git` folder or any file that
matches the oracle tests, the reference solution, the mutation tooling or the prompts (by content, name or marker string).

```zsh
AB_SEED_CHECK=~/experiments/scripts/check-seed.zsh auto-mode/ab-docker/run-ab.zsh run leave-sonnet-r6 claude-sonnet-5-5 ~/experiments/plans/leave-engine-docs ccf241e
```

## API key in an env file

If `ANTHROPIC_API_KEY` is not in the environment, `run`, `resume` and `review-loop` read it from `$AB_ENV_FILE`
(default `~/experiments/.env`). The file must be `chmod 600`, is parsed rather than sourced, and `.env` is already gitignored
by the experiments template. `AB_LOGIN=1` never reads it.

```zsh
umask 077
read -rs "k?Paste the API key (hidden): "; print "ANTHROPIC_API_KEY=$k" > ~/experiments/.env; unset k
chmod 600 ~/experiments/.env
```

## How it works

These five files now live in [../solver-docker/](../solver-docker/) (moved, not changed apart from their `COPY` paths); the descriptions stay here for context.

- `Dockerfile` — Node + Claude Code, a `claude` user with your host uid (so mounted files stay yours), and the
  plugin sources copied in without any git history; runs the plugins' own `deploy.zsh` to install them.
- `entrypoint.sh` — as root applies the firewall, then re-executes as `claude` with every capability dropped
  (`setpriv`, checked on a Linux host: capabilities end at zero), then prepares `/work`.
- `init-firewall.sh` — drops all outbound traffic except DNS, loopback and HTTPS to the allowlisted hosts
  (`AB_ALLOW_DOMAINS` adds more); self-tests that `example.com` fails and the API connects. Needs
  `--cap-add NET_ADMIN`, which `run-ab.zsh` passes. IP addresses are resolved once at start.
- `prepare-workdir.sh` — `git init`, a fake `origin` (`example.invalid`, allowlisted inside the image only), a
  baseline commit, branch `exp/<name>`.
- `experiments-template/` — the folder scaffold `run-ab.zsh init` copies (`.keep` and `.gitignore` files included).
- `isolation-check.sh` — the checks behind `run-ab.zsh check`.
- `review-round.zsh` — the host-side Copilot review loop (`review-round`, `review-summary`); `run-ab.zsh resume` starts a new session on an existing run folder.

## Known unknowns to verify on first run

- The `iptables` backend (nft vs legacy) depends on your Docker host; if `init-firewall.sh` fails, check that first.
- The env var names that quiet Claude Code's non-essential traffic can differ by version; the firewall is the real
  enforcement, so a blocked telemetry call is harmless.
- If Claude Code needs another host for your setup, add it with `AB_ALLOW_DOMAINS="api.anthropic.com host2"`.
