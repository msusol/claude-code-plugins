# syntax=docker/dockerfile:1
# Isolated runner for A/B experiments: Claude Code + git-guard + auto-mode in a container that
# sees only /work and can reach only the Anthropic API.
#
# Build from the repo root (run-ab.zsh does this for you):
#   docker build -f auto-mode/ab-docker/Dockerfile --build-arg HOST_UID=$(id -u) -t ab-claude .
FROM node:22-bookworm-slim

ARG HOST_UID=1000

RUN apt-get update && apt-get install -y --no-install-recommends \
      zsh git jq python3 python3-pytest curl ca-certificates iptables ipset util-linux procps \
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
RUN chown -R claude /opt/claude-code-plugins

COPY auto-mode/ab-docker/entrypoint.sh auto-mode/ab-docker/init-firewall.sh \
     auto-mode/ab-docker/prepare-workdir.sh auto-mode/ab-docker/isolation-check.sh /usr/local/bin/
RUN chmod 755 /usr/local/bin/entrypoint.sh /usr/local/bin/init-firewall.sh \
              /usr/local/bin/prepare-workdir.sh /usr/local/bin/isolation-check.sh

USER claude
ENV HOME=/home/claude
ENV PATH=/home/claude/.local/bin:$PATH

# Install the plugins exactly as on your machine: the wrapper, hook, allowlist and settings come from
# git-guard/deploy.zsh; the skills and Stop hook from the plugin installs it runs. Plugin sources are
# fetched from GitHub (the marketplace points at msusol/claude-code-plugins), so the image gets what is on main.
RUN zsh /opt/claude-code-plugins/git-guard/deploy.zsh \
 && zsh /opt/claude-code-plugins/auto-mode/deploy.zsh

# Container-only config: the scratch remote is allowlisted, commits have an author, and the web tools are
# denied (the firewall below is the enforcement; this stops the model from even trying).
RUN echo "example.invalid/ab" >> "$HOME/.config/git-guard/allowlist" \
 && git config --global user.name "ab-runner" \
 && git config --global user.email "ab@example.invalid" \
 && jq '.permissions.deny = (((.permissions.deny // []) + ["WebFetch","WebSearch"]) | unique)' \
       "$HOME/.claude/settings.json" > /tmp/settings.json \
 && mv /tmp/settings.json "$HOME/.claude/settings.json"

# Keep non-essential outbound traffic off (names as documented by Claude Code; verify on your version).
ENV CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
    DISABLE_TELEMETRY=1 \
    DISABLE_ERROR_REPORTING=1 \
    DISABLE_AUTOUPDATER=1

# Start as root only so the entrypoint can set the firewall; it then drops to `claude` with no capabilities.
USER root
WORKDIR /work
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["claude"]
