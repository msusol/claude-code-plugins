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

In Claude Code: `/docs-hub:hub`, `/docs-hub:hub serve`, `/docs-hub:hub serve re-lead-pipeline` (a project name is found below your home directory), or `/docs-hub:hub serve all ~/Projects --port 8766`. Add `.hub/` to the repo's `.gitignore`.

With `--root`, each project is at `/<project>/.hub/index.html` and `/` lists them. Served pages are built in memory, so serving writes nothing into the project and needs no `.gitignore` entry (`build_hub.py` still writes `docs/.hub/`).

A `file://` page does not auto-reload; the served page polls `hub.json` and re-renders in place.
Open a tab directly with `index.html#open` (`plans`, `adrs`, `inv`, `open`).
