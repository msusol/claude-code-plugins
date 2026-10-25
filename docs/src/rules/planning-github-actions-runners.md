# GitHub Actions runner-image pinning

`runs-on: ubuntu-latest` (and `windows-latest`/`macos-latest`) silently
retargets to a new OS major version on GitHub's own schedule — found live
2026-09-21: `ubuntu-latest` migrates to Ubuntu 26 starting 2026-10-19
(https://github.com/actions/runner-images/issues/14748), which would have
landed under a repo's CI workflows with no PR, no review, no
warning beyond a deprecation notice easy to miss in a run log.

## Rule

- Never write a new workflow with `runs-on: ubuntu-latest` (or the
  `windows-latest`/`macos-latest` equivalents). Pin an explicit version
  (`ubuntu-24.04`, `windows-2022`, `macos-14`, etc.) instead.
- When editing an existing workflow for an unrelated reason and it uses
  a `*-latest` runner label, pin it in the same change — don't leave it
  for a separate cleanup pass.
- Add a one-line comment next to the pin recording *why* it's pinned
  (the migration date/issue link) and a note to bump deliberately once
  the new image is verified compatible — so the pin doesn't look like an
  arbitrary/stale choice to a future reader, and so someone eventually
  revisits it instead of it calcifying forever.
- If you notice `##[warning]` runner-image deprecation text in a workflow
  run's own log (GitHub surfaces these directly in Actions output, not
  just via the linked runner-images issue), treat it as an immediate,
  low-effort fix to make — pin the label right then rather than letting
  it linger across future runs.

## Why pin instead of tracking the migration manually

`*-latest` labels are convenient until the day they change under you —
a new OS major can shift preinstalled tool versions, package managers,
or default shells in ways that break a workflow with no code change on
your side. Pinning trades a small amount of manual-bump maintenance for
never being surprised by an upstream runner change landing silently.

## Example

```yaml
jobs:
  my-job:
    # Pinned rather than `ubuntu-latest` (2026-09-21) -- ubuntu-latest
    # migrates to Ubuntu 26 starting 2026-10-19
    # (https://github.com/actions/runner-images/issues/14748). Bump
    # deliberately once Ubuntu 26 is verified compatible.
    runs-on: ubuntu-24.04
```
