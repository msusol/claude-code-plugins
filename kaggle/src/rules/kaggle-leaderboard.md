---
description: Track every Kaggle experiment in docs/plans/leaderboard.md after each completed run + validation pass; record CV (OOF), public LB, and the takeaway.
paths:
  - "**/docs/plans/leaderboard.md"
---

# Kaggle leaderboard / run tracking

Maintain `docs/plans/leaderboard.md` as the running record of every experiment. Update
it **after each completed training run and validation pass** — before moving on to the
next idea.

## Each row records

- **Version** (`vX.Y`) tying back to the plan in `docs/plans/`.
- **Model / key change** — what was different from the previous row.
- **OOF** — out-of-fold cross-validation score (the metric you trust).
- **Kaggle LB** — public leaderboard score once submitted.
- **Takeaway** — one line: did it help, and the suspected reason.

## Discipline

- Trust **CV → LB correlation**; the public LB is a small slice. If they diverge, note
  it and investigate (likely a leak or distribution mismatch) in `docs/investigate/`.
- Always include the trivial baseline row (e.g. uniform prediction) so the must-beat
  floor is visible.
- Keep rows in chronological/version order so regressions are obvious.
- When a result needs explanation longer than one line, write it in `docs/investigate/`
  and link from the takeaway.
