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


## Persistent Sessions
Always execute training under tmux on the DGX host. Never background long-running training jobs (nohup ... &) without tmux, as broken pipes or session disconnects can kill the training job unexpectedly.
