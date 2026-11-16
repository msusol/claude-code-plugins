# syntax=docker/dockerfile:1
# Isolated runner for A/B experiments: Claude Code + git-guard + auto-mode in a container that
# sees only /work and can reach only the Anthropic API.
#
# Build from the repo root (run-ab.zsh does this for you):
#   docker build -f auto-mode/solver-docker/Dockerfile --build-arg HOST_UID=$(id -u) -t ab-claude .
# Add the docs/ harness (planning rules) with --build-arg WITH_DOCS=1; `AB_DOCS=1 run-ab.zsh build` does this and tags
# the image ab-claude-docs, so both variants can coexist. Leave it off for the plain baseline (the smoke test).
FROM node:22-bookworm-slim

ARG HOST_UID=1000
ARG WITH_DOCS=0

RUN apt-get update && apt-get install -y --no-install-recommends \
      zsh git jq python3 python3-pip python3-venv python3-pytest curl ca-certificates iptables ipset util-linux procps \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g @anthropic-ai/claude-code

# The node image ships a `node` user at uid 1000; replace it so the runner can use the host uid
# (files in the mounted /work then belong to you on the host).
RUN userdel -r node 2>/dev/null || true \
 && useradd -m -u "${HOST_UID}" -s /bin/zsh claude

# Only the plugin sources are copied in -- no .git, no history, nothing else from the repo.
COPY .claude-plugin /opt/claude-code-plugins/.claude-plugin
COPY git-guard      /opt/claude-code-plugins/git-guard
COPY auto-mode      /opt/claude-code-plugins/auto-mode
# docs/ is copied only so the optional step below can install it; the next RUN removes it when WITH_DOCS is not 1,
# so the baseline image does not contain the planning rules at all.
COPY docs           /opt/claude-code-plugins/docs
RUN if [ "$WITH_DOCS" != "1" ]; then rm -rf /opt/claude-code-plugins/docs; fi
# Install the plugins from the sources copied above, not from GitHub main. The marketplace entries are git-subdir sources with
# ref "main", so without this the image gets whatever is on GitHub main, which can be older than your checkout (the first
# leave-engine pilot ran auto-mode 1.7.0 from main while the checkout had 1.9.0). Point each entry at its copied folder and keep
# only the plugins present in the image. The image is then exactly this checkout; see the ab.source-rev label.
RUN jq --arg docs "$WITH_DOCS" \
      '.plugins |= (map(select(.name == "git-guard" or .name == "auto-mode" or (.name == "docs" and $docs == "1"))) | map(.source = ("./" + .source.path)))' \
      /opt/claude-code-plugins/.claude-plugin/marketplace.json > /tmp/marketplace.json \
 && mv /tmp/marketplace.json /opt/claude-code-plugins/.claude-plugin/marketplace.json
RUN chown -R claude /opt/claude-code-plugins

COPY auto-mode/solver-docker/entrypoint.sh auto-mode/solver-docker/init-firewall.sh \
     auto-mode/solver-docker/prepare-workdir.sh auto-mode/solver-docker/isolation-check.sh /usr/local/bin/
RUN chmod 755 /usr/local/bin/entrypoint.sh /usr/local/bin/init-firewall.sh \
              /usr/local/bin/prepare-workdir.sh /usr/local/bin/isolation-check.sh

USER claude
ENV HOME=/home/claude
ENV PATH=/home/claude/.venv/bin:/home/claude/.local/bin:$PATH

# Install the plugins exactly as on your machine: the wrapper, hook, allowlist and settings come from
# git-guard/deploy.zsh; the skills and Stop hook from the plugin installs it runs. Plugin sources are
# installed from the copied sources (the marketplace entries were rewritten to local folders above), so the image is this checkout.
# The marketplace's GitHub shorthand clones over SSH, and this image has no ssh client or keys by design, so the
# deploy scripts' installs failed silently (they swallow errors). Rewrite GitHub SSH URLs to HTTPS for the install
# only (the repo must be public), drop the rewrite afterwards, and fail the build if a plugin is missing.
#
# Optional: the docs/ harness (only with --build-arg WITH_DOCS=1). It installs the planning-* rules into
# ~/.claude/rules/ and @-imports them from ~/.claude/CLAUDE.md, so every session in the container loads them.
# The plan repo you export should carry its own docs/ folder (plans, ADRs) for the rules to work against.
RUN git config --global url."https://github.com/".insteadOf "git@github.com:" \
 && git config --global --add url."https://github.com/".insteadOf "ssh://git@github.com/" \
 && zsh /opt/claude-code-plugins/git-guard/deploy.zsh \
 && zsh /opt/claude-code-plugins/auto-mode/deploy.zsh \
 && if [ "$WITH_DOCS" = "1" ]; then zsh /opt/claude-code-plugins/docs/deploy.zsh; fi \
 && git config --global --unset-all url."https://github.com/".insteadOf \
 && claude plugin list | grep -q git-guard \
 && claude plugin list | grep -q auto-mode \
 && if [ "$WITH_DOCS" = "1" ]; then claude plugin list | grep -q "docs@losus-ai"; fi

# Container-only config: the scratch remote is allowlisted, commits have an author, and the web tools are
# denied (the firewall below is the enforcement; this stops the model from even trying).
RUN echo "example.invalid/ab" >> "$HOME/.config/git-guard/allowlist" \
 && git config --global user.name "ab-runner" \
 && git config --global user.email "ab@example.invalid" \
 && jq '.permissions.deny = (((.permissions.deny // []) + ["WebFetch","WebSearch"]) | unique)' \
       "$HOME/.claude/settings.json" > /tmp/settings.json \
 && mv /tmp/settings.json "$HOME/.claude/settings.json"

# Python libraries for the experiments' tasks, from requirements.txt next to this file. The container has no network at
# run time (the firewall allows only the Anthropic API), so anything a task needs must be installed here, at build
# time: edit requirements.txt and rebuild. The venv also sees the apt packages (pytest) and is first on PATH, so
# `python`, `python3` and `pip` all mean the same thing. The installed set is recorded in ~/.ab-pip-freeze.txt.
COPY --chown=claude auto-mode/solver-docker/requirements.txt /home/claude/.ab-requirements.txt
RUN python3 -m venv --system-site-packages "$HOME/.venv" \
 && "$HOME/.venv/bin/pip" install --no-cache-dir -r "$HOME/.ab-requirements.txt" \
 && "$HOME/.venv/bin/pip" freeze > "$HOME/.ab-pip-freeze.txt"

# `pip install -e .` on an arm's pyproject.toml works offline: with build isolation pip tries to download setuptools (blocked by the
# firewall), so turn isolation off. The setuptools and wheel already in the venv do the build. (pip reads PIP_NO_BUILD_ISOLATION=0 as
# "no build isolation"; a pip.conf entry did not work in testing.) Set after the build-time pip install above, so it only affects arms.
ENV PIP_NO_BUILD_ISOLATION=0

# Keep non-essential outbound traffic off (names as documented by Claude Code; verify on your version).
ENV CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
    DISABLE_TELEMETRY=1 \
    DISABLE_ERROR_REPORTING=1 \
    DISABLE_AUTOUPDATER=1

# The checkout this image was built from (run-ab.zsh build passes it; "+dirty" means uncommitted changes were copied in).
# Read it with: docker image inspect <image> --format '{{ index .Config.Labels "ab.source-rev" }}'
ARG SRC_REV=unknown
LABEL ab.source-rev=$SRC_REV

# Start as root only so the entrypoint can set the firewall; it then drops to `claude` with no capabilities.
USER root
WORKDIR /work
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["claude"]
