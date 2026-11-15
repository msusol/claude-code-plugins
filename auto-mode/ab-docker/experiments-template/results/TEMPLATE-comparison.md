---
plan: <plan-slug>
plan-commit: <sha of plans/<plan> HEAD>
models: {a: <exact model id>, b: <exact model id>}
date: <YYYY-MM-DD>
harness: <none | docs <plugin version> | ...>   # AB_DOCS=1 image has the docs/ plugin
repeats: <N>
copilot: code review via PR, same instructions for both arms; cap <N> rounds
cost: arm API spend from separate keys; Copilot premium requests used
---
# <plan>: <model A> vs <model B>

Copy this file to `<date>-<plan>-<a>-vs-<b>.md`, and the runs' `rounds.csv` files to
`data/<date>-<plan>-<a>-vs-<b>/rounds-<model>-r<N>.csv`.

## Results

| Run | Rounds to clean | Findings per round | Arm cost | Premium requests | Notes |
|---|---|---|---|---|---|
| <plan>-<a>-r1 | | | | | |
| <plan>-<b>-r1 | | | | | |

## Verdict

## Caveats
