---
description: Shell preferences when editing or suggesting shell scripts (zsh shebang, zsh invocations)
globs: ["**/*.sh", "**/*.zsh"]
---

# Shell preferences

- Use `zsh` as the default shell for all scripts and run commands.
- Script shebangs must be `#!/usr/bin/env zsh`, not `#!/bin/bash` or `#!/bin/sh`.
- When suggesting a command for the user to run, write it as a `zsh` invocation (e.g. `./script.sh` or `zsh script.sh`, not `bash script.sh`).