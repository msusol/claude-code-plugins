# DGX Spark: running heavy compute jobs on a shared host

`spark-db62` (the DGX Spark GB10) is a single-socket workstation with 120 GB of
VRAM, but it is **shared** — it also runs the always-on production Docker stack
(`mattermost`, `ollama-server`, `clp-db`, etc. — see
`dgx-spark-docker-context.md`) alongside whatever heavy compute job you're about
to run (LLM fine-tuning, large batch inference, GIS/parcel processing, or
anything else that saturates CPU/GPU/RAM for an extended period).

This applies to any heavy job on this host, not just one project's training
runs — the risk and the mitigations below are about the machine, not about
Kaggle, ETL, or any other specific workload.

## The risk: OOM kills of critical daemons

A heavy job that doesn't manage memory can trigger Linux OOM kills against
background services sharing the host — including critical daemons like `sshd`
and `systemd-networkd`. Losing either of those mid-job can cut off your own
access to the machine, not just crash the job.

## Service pausing

Before running a heavy compute job, pause non-essential background Docker
containers, and resume them after the job finishes — **even if it fails**
(pausing without a matching resume-on-failure path just trades one outage for
another). A project running heavy jobs on this host should have its own
pause/resume automation (see `kaggle-dgx-spark.md` for one concrete
implementation, `scripts/services.sh` + a `.paused_containers` state file) —
the mechanism can vary per project, but every heavy-job project on this host
needs one.

Check `docker context ls` first if a pause/resume script can't find containers
it expects — see `dgx-spark-docker-context.md`.

## Persistent sessions

Always run a heavy job under `tmux` on this host. Never background a
long-running job with bare `nohup ... &` — a broken pipe or a disconnected
session can kill the job unexpectedly, with no supervisor to notice or
restart it. `tmux` survives a disconnect; a bare backgrounded process
attached to a dead shell does not.
