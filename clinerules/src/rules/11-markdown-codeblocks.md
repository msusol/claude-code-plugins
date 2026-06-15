---
description: Formatting rules for multi-flag bash commands inside markdown code blocks
globs: ["**/*.md", "**/*.ipynb"]
---

# Markdown code block formatting

When writing bash commands inside markdown code blocks, format each flag or argument on its own line using line continuations.

## Rules

- Put one flag or argument per line.
- Use `\` line continuations at the end of each line except the last.
- Indent continuation lines by two spaces.
- Apply this formatting to bash commands with more than two arguments.
- For commands the user will run repeatedly, create a script in `scripts/` and reference it instead of inlining the full command.
- Long `curl` commands with JSON bodies must always go in a script and should not be inlined in chat or docs.

## Example

Bad:

```bash
docker run --rm --gpus all --ipc=host --ulimit memlock=-1 -v "$PWD":/workspace -w /workspace mineral-hr-llm-gb10 python train.py --model foo --epochs 3
```

Good:

```bash
docker run \
  --rm \
  --gpus all \
  --ipc=host \
  --ulimit memlock=-1 \
  -v "$PWD":/workspace \
  -w /workspace \
  mineral-hr-llm-gb10 \
  python train.py \
    --model foo \
    --epochs 3
```
