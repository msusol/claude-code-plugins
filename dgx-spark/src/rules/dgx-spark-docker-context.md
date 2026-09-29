# DGX Spark: two Docker daemons/contexts — check which one you're on

`spark-db62` has **both** a native Docker Engine (`unix:///var/run/docker.sock`,
context `default`) **and** Docker Desktop for Linux installed
(`unix:///home/msusol/.docker/desktop/docker.sock`, context `desktop-linux`).
`docker ps`, `docker network ls`, `docker compose up`, and every other Docker
CLI command operate on whichever context is currently active — silently. A
container or network that's "missing" under one context can be alive and
healthy under the other.

## The real production stack lives under `default`

Confirmed live 2026-09-28: `mattermost`, `mm-db`, `metabase`, `accountant-db`,
`mattermost-bridge`, `clp-app`, `clp-db`, `ollama-server`, `nginx-proxy`,
`rnaseq-server`, and their networks (`mattermost_default`,
`coloradolandpartners_default`, `ollama-server_default`, etc.) all run under
the **native `default` context**. `desktop-linux` typically has just whatever
was created most recently while that context happened to be active (e.g. a
throwaway `investment_agent_openwebui` container, a stray never-started
`clp-db`).

## What this caused, live

The DGX Spark's active Docker CLI context had been switched to `desktop-linux`
at some point. Consequences discovered while investigating a real incident:

- `docker network ls`/`docker ps` under `desktop-linux` showed no
  `ollama-server` container and no `ollama-server_default` network — looked
  exactly like the container had never been brought up.
- **`ColoradoLandPartners`'s daily CLP foreclosure pipeline (a systemd
  timer running `docker compose`) failed outright** with `network
  ollama-server_default declared as external, but could not be found` —
  because whatever context it resolved to at run time didn't have that
  network, even though it existed fine under `default`. No jobs ran that day
  (no scraping, no leads, no skip-tracing, no ReiReply export, no summary
  email).
- Nearly caused a **real, unnecessary outage**: believing `ollama-server` was
  a rogue bare-metal process, the fix path was about to kill its PID
  directly — which would have taken down a container that had actually been
  healthy for 33 hours, serving Mattermost/Lori, accountant-agent, Open
  WebUI/Travis, and other live consumers.

## Diagnostic tell

If a process's cgroup is `system.slice/docker-<hash>.scope` (check
`cat /proc/<pid>/cgroup`) but `docker inspect <hash>` / `docker ps -a` under
the *current* context says "no such object" — that process belongs to a
*different* Docker context's daemon, not to no daemon at all. Don't conclude
"orphaned process" or "never containerized" from one context's view alone.

## Rule

1. **Before concluding a container or network is missing on this host, run
   `docker context ls` first.** If `desktop-linux` is marked current (`*`),
   check `docker --context default ps -a` / `docker --context default
   network ls` before trusting the active context's view.
2. **If the real stack turns out to be under `default`, switch it back**:
   `docker context use default`. This is the canonical context for this
   host's actual workloads; `desktop-linux` should not be the default.
3. **Never send a raw `kill`/`kill -9` to a PID that shows `docker-default`
   in `cat /proc/<pid>/attr/current`** (AppArmor's Docker confinement) —
   even `sudo kill -9` as root returns `Permission denied` for a
   containerized process signaled from outside Docker's own management
   path. Use `docker stop`/`docker kill` (from whichever context actually
   manages that container) instead of a host-side signal.
4. If a scheduled/systemd-triggered `docker compose` job can fail this way,
   consider pinning its `DOCKER_CONTEXT`/`DOCKER_HOST` explicitly in the
   unit file rather than relying on whatever the ambient default happens to
   be at run time — not yet done as of 2026-09-28; worth doing as a
   follow-up hardening step for `clp-foreclosure-pipeline.service` and any
   other systemd-timer-triggered compose job on this host.
