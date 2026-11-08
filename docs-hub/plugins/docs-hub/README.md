# docs-hub

`/docs-hub:hub` builds `docs/.hub/index.html`: a hub for a repo that uses the planning-docs layout
(`adr/`, `plans/` with `TODO.md`, `investigate/`). Links open the local files.

## Use

```bash
python3 scripts/build_hub.py docs            # build once
python3 scripts/build_hub.py docs --watch    # rebuild on change
python3 scripts/serve_hub.py docs            # serve at http://127.0.0.1:8765/, rebuild on request
```

In Claude Code: `/docs-hub:hub` or `/docs-hub:hub serve`. Add `.hub/` to the repo's `.gitignore`.

A `file://` page does not auto-reload; the served page polls `hub.json` and re-renders in place.
Open a tab directly with `index.html#open` (`plans`, `adrs`, `inv`, `open`).
