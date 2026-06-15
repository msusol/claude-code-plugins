# usage-statusline

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**Author:** Mark Susol

Status line for Claude Code showing model name, context window usage, and subscription rate limits.

![usage-statusline plugin in action](../usage-statusline.png)

Shows in the Claude Code status bar:

```
Claude Sonnet 4.6 | ctx:12% | 5h:34% 7d:8%
```

- **Model** — active model name
- **ctx** — context window used this turn
- **5h / 7d** — subscription rate limits used (appear after first API response)

## Install

```zsh
./deploy.zsh
```

## Uninstall

```zsh
./uninstall.zsh
```

## Known Limitations

The `statusLine` command renders per-conversation context, not at CLI startup. It will appear after the first message or `/new` — not at the initial prompt. This is a Claude Code CLI limitation.

A feature request for a `Startup` hook event has been filed:
[anthropics/claude-code#64018 — add startup/session-init hook event to settings.json hooks](https://github.com/anthropics/claude-code/issues/64018)
