---
name: docs-plan-handoff
description: Use for vibe planning away from the Spark or outside a repo, on any topic: drafts a docs_TOPIC folder, zips it, stages it in Downloads, and prints the full process: scp, unzip, and the merge prompt for Claude Code.
---

# Docs plan handoff

For any planning done where the repo is not reachable: a new feature, a design decision, a roadmap, an investigation, or a rewrite of existing docs. Draft the docs here, deliver them as a folder named `docs_<topic>/` that will sit next to the target repo's `docs/`, and walk the user through the full process of getting them into the repo.

`<topic>` is a short kebab-case or single-word slug for the subject at hand (for example `docs_wiki` for an external wiki plan). Take it from the arguments if given, otherwise from the conversation.

## Before drafting

- Identify the target repo. If it is unknown and the docs would differ by repo, ask one short question. Otherwise use placeholders.
- If the plan spans several repos, produce one `docs_<topic>/` per repo.
- If the user supplies existing docs to change, edit them in place and keep their structure.

## Drafting

1. Follow the planning-docs conventions: `adr/`, `specs/`, `plans/` (with `plans/TODO.md`), `roadmap/`, `process/`, `investigate/`, and `index.md`. Start minimal and expand only when content earns it.
2. Name the top-level folder `docs_<topic>/`, not `docs/`.
3. Use only relative links between files. Do not refer to the `docs/` path inside the content, so the folder can be merged or renamed without edits.
4. This session cannot see live state (code, database, installed versions, running services). Treat anything from memory or earlier AI sessions as a hypothesis. Put verification tasks in the plan for the session in the repo to run, instead of stating those facts as settled.
5. Check that every relative link resolves before delivering.

## Delivery

1. Zip as `docs_<topic>.zip` with `docs_<topic>/` as the single top-level folder, so it cannot be confused with an existing `docs.zip`.
2. Send the zip to the user.
3. If the session has a working shell and bridge to the user's computer, stage the zip in `~/Downloads/`: request access to that folder if it is not connected, wait for approval, then write the zip there. If the bridge is unavailable or access is declined, skip this and tell the user to download the zip from the chat.
4. Do not try to run `scp` or `ssh` from the desktop link. Its shell is an isolated sandbox with none of the user's SSH setup, so the `spark-db62` alias is not defined there. Print the commands for the user to run instead.
5. Finish by printing the full process below, filled in for this topic.

## The full process to print

The user reaches the Spark through the SSH host alias `spark-db62` (defined in their `~/.ssh/config`). Only the repo path on the Spark needs to be known. Ask once if it has not been confirmed; never guess it. Print these steps, in order:

1. **Get the zip** into `~/Downloads/` on the user's computer (already staged if step 3 of Delivery worked).
2. **Copy it** from the user's terminal:

```bash
scp ~/Downloads/docs_<topic>.zip spark-db62:<repo-path>/
```

3. **Unzip it** on the Spark. `-n` never overwrites existing files, and the zip is left in place until the merge is done:

```bash
ssh spark-db62 \
  'cd <repo-path> \
   && unzip -n docs_<topic>.zip'
```

4. **Merge it.** In a Claude Code session in the repo, paste:

```text
Merge docs_<topic>/ into docs/ in this repo, then delete docs_<topic>/. Follow the planning-docs conventions. Do not start any of the work described in the plan.

1. Read everything in docs_<topic>/ and the current docs/ first. If docs/ does not exist, rename docs_<topic>/ to docs/ and stop.
2. index.md: merge the entries into docs/index.md. Do not overwrite it.
3. plans/TODO.md: merge the sections into docs/plans/TODO.md. Do not overwrite it. Keep "## Next steps" as the last section.
4. ADRs: renumber each ADR in docs_<topic>/adr/ to the next unused number in docs/adr/. Do not reuse numbers. Update every link to a renumbered file in all the merged docs.
5. Specs and plans: if a file with the same name already exists in docs/, compare the two and merge them instead of overwriting.
6. Update docs/index.md with links to everything added.
7. Before deleting anything, check that every relative link in docs/ resolves and that nothing still refers to docs_<topic>/.
8. Only after that check passes, delete docs_<topic>/ and docs_<topic>.zip if it is still in the repo.
9. Report what was added, what was merged with existing files, any ADRs that were renumbered, and anything you could not resolve.
```

If the user would rather review before anything is deleted, change step 8 to: list what would be deleted and wait for approval.

5. **Verify first.** As a separate step in the same repo, paste:

```text
Run only the verification tasks in docs/plans/<plan-file>.md. Check each one against the live setup (code, database, installed versions, running services). Record each result in the plan as confirmed or not reproduced. Do not build anything yet, and report any claim that did not hold.
```

6. **Clean up.** The user deletes `~/Downloads/docs_<topic>.zip` on their computer, and `docs_<topic>.zip` on the Spark if the merge session left it there. `scp` copies and does not move, and this session cannot delete files in their folders.