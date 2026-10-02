---
description: Guidelines for writing commit descriptions based on git diff and task context
globs: "**/*"
---

# Commit description guidelines

When writing commit messages, follow the Conventional Commits specification. Analyze the git diff and task context to create meaningful descriptions that explain what changed and why.

## Structure

Format:

`type(optional scope): description`

Optional body:

- bullet points explaining the main changes
- brief explanation of why the change was made

Verified (required; see `planning-commit-verification.md`):

- a `Verified:` section at the end of the body: the command(s) run, the result (pass or fail, counts), and the path of any evidence
  file committed with the change
- if the check could not be run or failed and the user chose to proceed: `Not verified: <reason>`

Optional footer:

- references to issues or PRs, for example `Closes #123`

## Analysis process

### 1. Review git diff

- New files: describe what functionality they add.
- Modified files: explain what changed and why.
- Deleted files: note what was removed and the impact.

### 2. Consider task context

- Feature implementation: focus on new capabilities.
- Bug fixes: explain the problem and the solution.
- Refactoring: describe structural improvements and standards applied.
- Documentation: highlight what guidance was added.

### 3. Categorize changes

Use the appropriate commit type:

- `feat` for new features or functionality
- `fix` for bug fixes
- `docs` for documentation changes
- `refactor` for code restructuring without functional changes
- `test` for test-related changes
- `chore` for maintenance tasks, dependencies, or configuration

## Best practices

- Be specific.
- Mention actual files, systems, or functions changed where useful.
- Explain why the change matters.
- Keep the subject concise.
- Use imperative mood.
- Reference issues when applicable.

## Examples

- `feat(queue-consumer): add OCI Queue consumer with mock client`
- `fix(probe): correct liveness probe to prevent restarts`
- `docs(argo): document Argo Workflows integration`
- `refactor(python): apply typing and code style cleanup`
