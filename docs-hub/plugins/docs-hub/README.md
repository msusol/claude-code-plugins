# docs-hub

`/docs-hub:hub` builds `docs/.hub/index.html`: a hub for a repo that uses the planning-docs layout
(`adr/`, `plans/` with `TODO.md`, `investigate/`). Links open the local files.

## Use

```bash
python3 scripts/build_hub.py docs            # build once
python3 scripts/build_hub.py docs --watch    # rebuild on change
python3 scripts/serve_hub.py docs            # http://127.0.0.1:8765/<project>/.hub/index.html, rebuilt on request
python3 scripts/serve_hub.py --root ~/Projects --port 8766   # every <project>/docs under one port
```

In Claude Code: `/docs-hub:hub`, `/docs-hub:hub serve`, `/docs-hub:hub serve re-lead-pipeline` (a project name is found below your home directory), or `/docs-hub:hub serve all ~/Projects --port 8766`. `build_hub.py` warns when `.hub/` is not git-ignored, and the command adds the line to `.gitignore` for you (it never commits it).

With `--root`, each project is at `/<project>/.hub/index.html` and `/` lists them. Served pages are built in memory, so serving writes nothing into the project and needs no `.gitignore` entry (`build_hub.py` still writes `docs/.hub/`).

A `file://` page does not auto-reload; the served page polls `hub.json` and re-renders in place.
Open a tab directly with `index.html#open` (`plans`, `adrs`, `inv`, `open`).

## How the numbers are counted

Everything comes from the checkboxes in `plans/TODO.md` (one section per plan). A plan with no TODO section falls back to the checklist in its own file.

| Task | Counts as |
|---|---|
| `- [x] Task` | done |
| `- [ ] Task` | open |
| `- [x] ~~Task~~ — obsolete: why` or `— dropped …` | not counted (neither done nor open) |
| `- [ ] ~~Task~~ — deferred to plan 0018` | not counted here; counted in the plan it moved to |

A struck-through task needs the keyword (`obsolete`, `dropped` or `deferred`) after the strike-through; one without it counts normally.

- **Headline tile:** done ÷ (done + open) over the active plans' tasks. Plans in `plans/archive/`, and any of their tasks still listed in `TODO.md`, are left out. Archiving a mostly-finished plan therefore lowers the figure, because the work that was finished leaves both sides of the fraction.
- **Second line:** the same fraction with each archived plan's own checklist added (counted by the same rules), so it only grows as plans are finished: "41% of all work, with 1 archived plan". It is hidden when no plan is archived.
- **Plan progress chart:** one row per plan, in plan-number order (an inserted number such as `00011` sits between `0001` and `0002`). Archived plans appear only when the **Archived** box is ticked; ticking it never changes the tile.
- **Open work tab:** lists open tasks; obsolete, dropped and deferred ones appear only with "Include done".

## Tests

```bash
python3 -m unittest discover -s docs-hub/tests -v     # from the plugin repo root; the tile math needs node
```
