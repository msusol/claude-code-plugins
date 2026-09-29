---
description: Kaggle-specific conventions for training heavy LLM tasks on the DGX Spark GB10 workstation.
---

# DGX Spark: Kaggle training conventions

The DGX Spark GB10 is used to run heavy LLM fine-tuning tasks for Kaggle
competitions (e.g. 5-fold cross-validation or 27B+ parameter model
distillation) that exceed Kaggle's own notebook compute limits.

For the host-level facts and conventions that apply to *any* heavy job on this
shared machine — the OOM risk, pausing background Docker services, running
under `tmux` — see the `dgx-spark` plugin's
`dgx-spark-heavy-compute-jobs.md` (deployed globally to
`~/.claude/rules/`, not duplicated here). This rule only covers what's
specific to a *Kaggle* project's training runs.

## Service pausing automation

Every Kaggle project using the DGX for training should include a standard
`scripts/services.sh` script implementing the pause/resume convention from
`dgx-spark-heavy-compute-jobs.md`: pause non-essential background Docker
containers with `always` or `unless-stopped` restart policies before a
training run, and resume them after (even if the run fails). Save the paused
set to `.paused_containers` so resume knows exactly what to bring back.

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
