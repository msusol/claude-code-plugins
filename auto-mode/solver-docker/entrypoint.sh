#!/usr/bin/env bash
# Container entrypoint. As root: apply the egress firewall, then re-exec as the unprivileged `claude`
# user with every capability dropped. As claude: prepare /work, then run the command.
set -euo pipefail

if [[ "$(id -u)" -eq 0 ]]; then
  /usr/local/bin/init-firewall.sh
  exec setpriv --reuid=claude --regid=claude --init-groups \
       --bounding-set=-all --inh-caps=-all --no-new-privs \
       env HOME=/home/claude /usr/local/bin/entrypoint.sh "$@"
fi

cd /work
/usr/local/bin/prepare-workdir.sh
exec "$@"
