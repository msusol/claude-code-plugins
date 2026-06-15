---
description: Staging convention for non-markdown artifacts (xlsx, csv, log, screenshot, pdf) co-located with docs/ documents
paths:
  - docs/**/*
---

# Non-markdown artifact staging rules

When any document under `docs/` has associated non-markdown artifacts (Excel files, CSVs,
log files, screenshots, PDFs, or other binary/data files), use a named subdirectory to
co-locate the anchor `.md` file with its artifacts.

Never place binary artifacts as flat siblings of unrelated `.md` files.

## Rule

- Create a kebab-case named subdirectory under the appropriate `docs/` folder.
- The anchor `.md` file lives **inside** that subdirectory alongside the artifacts.
- Subdirectory name = kebab-case feature or issue name (see per-folder conventions below).

## Per-folder conventions

### `docs/specs/`

```
docs/
  specs/
    failed-mls-drip-campaign/
      spec.md                                       ← anchor doc
      Adams_county_failed_listings_1781278047.xlsx  ← input data that defines the feature
      Denver_Failed_Listings_1781277986.xlsx
```

- Subdirectory name: kebab-case feature name.
- Anchor file: `spec.md`.
- Use this when the artifact is the input or reference that prompted the feature (e.g., a
  data file that defines the required schema, a PDF spec from a client).

### `docs/investigate/`

```
docs/
  investigate/
    2026-06-15-adams-parse-failure/
      2026-06-15-adams-parse-failure.md  ← anchor doc (date-prefixed, matches existing convention)
      etl_error.log                      ← artifact that triggered the investigation
      malformed_input.xlsx               ← input file showing the bad data
```

- Subdirectory name: date-prefix + kebab-case issue name (preserves the existing flat-file
  naming convention).
- Anchor file: same name as the subdirectory, with `.md` extension.
- Use this when an artifact (log, screenshot, CSV, export) triggered or is central to the
  investigation.

### `docs/plans/`

Plans stay flat. A plan references spec artifacts by relative path rather than owning
copies. Only use a subdirectory if a plan genuinely needs its own artifacts that are not
already anchored under `docs/specs/`.

### `docs/process/`

Process docs stay flat. Use a subdirectory only if a process document is tightly coupled
to binary artifacts it must distribute (e.g., a template file or sample config).

## Migration: flat doc gains artifacts

If a flat spec or investigate doc later gains associated artifacts:

1. Create the subdirectory: `docs/<folder>/<name>/`.
2. Move the `.md` into it, renaming as required by the per-folder convention above.
3. Move or add artifacts alongside it.
4. Update any links in `docs/index.md`, plan files, or other referencing docs.
