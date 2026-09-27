---
description: Keep sibling-directory listings in a CLAUDE.md (project trees, in/out-of-scope lists) in sync when directories are added, removed, or renamed
globs: "**/*"
---

# Keep directory listings in CLAUDE.md files current

Some `CLAUDE.md` files enumerate their own sibling directories — a project
tree, an "in scope" / "out of scope" list, or an equivalent enumeration —
so a session working elsewhere in the tree (or a person reading it) can
tell at a glance what that file's instructions do and don't cover.

These enumerations go stale the moment a sibling directory is added,
removed, or renamed. Nothing else in the repo or filesystem points back at
them to keep them honest — it's on whoever changes the directory structure.

## Rule

Whenever you create, delete, or rename a top-level directory inside a
folder that has its own `CLAUDE.md`, check whether that `CLAUDE.md`
contains a directory listing (a tree diagram, an "in scope" / "out of
scope" list, or an equivalent enumeration of its siblings). If it does,
update the listing in the same turn, before finishing the work that
changed the directory — don't leave it for a later pass.

This applies regardless of whether the new, removed, or renamed directory
is itself relevant to that `CLAUDE.md`'s subject matter. The point is
keeping the enumeration accurate, not judging relevance — an out-of-scope
list that's missing a real sibling folder is just as broken as one that's
missing an in-scope one.

If you're unsure whether an ancestor `CLAUDE.md` contains such a listing,
check for one before assuming there's nothing to update — don't skip the
check just because the directory change felt unrelated to that file's
stated purpose.
