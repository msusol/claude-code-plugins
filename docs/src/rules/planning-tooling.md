 # Tooling and package manager preferences

- Never use Homebrew (`brew`) for any installation or package management task.
- Use `pip` for Python packages.
- Use MacPorts (`port`) for system-level CLI tools.
- When suggesting an install command for the user to run, use `sudo port install <tool>` (not `brew install`).

## GitHub CLI

The GitHub CLI installed via MacPorts is at `/opt/local/bin/gh`.

A Python shim named `gh` (v0.0.4) is earlier in PATH and does not support `gh pr`, `gh issue`, or any GitHub CLI subcommands.

- Always invoke the GitHub CLI as `/opt/local/bin/gh`, never as bare `gh`.