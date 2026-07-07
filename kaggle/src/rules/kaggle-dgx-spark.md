---
description: Environment conventions for training heavy LLM tasks on the DGX Spark GB10 workstation.
---

# DGX Spark Environment Conventions

The DGX Spark GB10 is a single-socket workstation with 120 GB of VRAM. It is used to run heavy LLM fine-tuning tasks (e.g. 5-fold cross-validation or 27B+ parameter model distillation) that exceed Kaggle limits.

Because the DGX is a shared workstation running background Docker services, training runs must actively manage system memory to prevent Linux OOM kills of critical daemons (sshd, systemd-networkd).

## Service Pausing

Always pause non-essential background Docker containers before running a heavy training script, and resume them after the script finishes (even if it fails). 

Every project using the DGX for training should include a standard `scripts/services.sh` script to automate pausing and resuming containers with `always` or `unless-stopped` restart policies. The state is saved to `.paused_containers`.

## Persistent Sessions
Always execute training under `tmux` on the DGX host. Never background long-running training jobs (`nohup ... &`) without `tmux`, as broken pipes or session disconnects can kill the training job unexpectedly.

## Progress Reporting

Any DGX script expected to run for more than a couple of minutes (training,
inference, calibration/grid-search fitting, batch scoring) must report progress
incrementally — wrap batch/row loops in `tqdm`, or add a periodic `print` every N
items/batches. A script that prints one line at the start of a long loop and nothing
until it's fully done is unmonitorable: there's no way to distinguish "still working
normally" from "hung" short of inspecting GPU utilization as a proxy, and no way to
estimate remaining time.

This applies to one-off/investigation scripts, not just training entrypoints — e.g. a
calibration-fitting script doing full-dataset inference deserves the same treatment as
`train_v03b.py`'s per-step logging.
