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

## Investigations tab

One row per note in `investigate/`. **Plans** lists every plan that links the note (in the plan file or on a `TODO.md` line) and every plan the note names in its own optional front matter, `plans: [0003, 0018]`; **Tickets** shows `tickets: [PROJ-123]`. **TODO item** and **Status** show the checklist line that cites a note and its box. A column with no value in any row is hidden (Tickets until a note has one; TODO item and Status, and the Done tile, until a `TODO.md` line links a note), so a project whose `TODO.md` lines carry no links does not see empty columns. A `plans:` id that matches no plan is left out of the table and listed in `hub.json` under `sync.unknown_note_plans`.

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
- **Open work tab:** lists open tasks; obsolete, dropped and deferred ones appear only with "Include done". Choose an archived plan (with **Archived** ticked) and the tab says it has no open work, with its name as a link: a click shows the plan rendered in place below, and Ctrl or Cmd click, or "Open the file" in that view, opens the raw markdown.

## The TODO sync check

`plans/TODO.md` should mirror each plan file task for task (the plan file is the source of truth). The hub checks it:

- **Drift.** For every active plan with a TODO section, the done and open counts of the plan file and of its section are compared under the counting rule above. If they differ, the plan's row in the **Plan progress** chart ends in ⚠ and its tooltip says how: "plan file 23 of 30 done, TODO.md section 5 of 9". A line under the chart lists the plans. Archived plans keep a one-line note instead of a checklist, so they are not compared, and a plan file with no checklist has nothing to compare with.
- **Stale Next steps.** An item under `## Next steps` that names a date (`YYYY-MM-DD`) is flagged once the latest date it names is in the past. It is either done (remove it) or late (say so). Items with no date, or a date still ahead, are not flagged.
- Both are also in `hub.json` as `sync: {drift: [plan ids], stale_steps: [...]}`, and each plan row has a `drift` text.

## Tests

```bash
python3 -m unittest discover -s docs-hub/tests -v     # from the plugin repo root; the tile math needs node; includes the sync check
```
