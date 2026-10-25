#!/usr/bin/env python3
"""
Idempotent manager for scratch-guard entries in ~/.claude/settings.json.

Usage:
  python3 manage-settings.py install    # Register hooks (safe to re-run)
  python3 manage-settings.py uninstall  # Remove scratch-guard entries only
"""

import json
import shutil
import sys
import tempfile
from pathlib import Path

SETTINGS_PATH = Path.home() / ".claude" / "settings.json"
HOOK_SCRIPT = str(Path.home() / ".claude" / "scripts" / "scratch-guard-hook.zsh")

# Two matcher entries, same hook script, so it sees both shell-redirected
# scratch files (Bash) and direct file creation (Write).
HOOK_ENTRIES = [
    {"matcher": "Bash", "hooks": [{"type": "command", "command": HOOK_SCRIPT}]},
    {"matcher": "Write", "hooks": [{"type": "command", "command": HOOK_SCRIPT}]},
]


def _load_settings():
    if SETTINGS_PATH.exists():
        with open(SETTINGS_PATH) as f:
            return json.load(f)
    return {}


def _write_settings(settings):
    SETTINGS_PATH.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        "w", dir=SETTINGS_PATH.parent, delete=False, suffix=".tmp"
    ) as tmp:
        json.dump(settings, tmp, indent=2)
        tmp.write("\n")
        tmp_path = tmp.name
    shutil.move(tmp_path, SETTINGS_PATH)


def _entry_registered(pre_tool_use_list, matcher):
    for entry in pre_tool_use_list:
        if entry.get("matcher") != matcher:
            continue
        for h in entry.get("hooks", []):
            if h.get("command") == HOOK_SCRIPT:
                return True
    return False


def install():
    settings = _load_settings()
    hooks = settings.setdefault("hooks", {})
    pre_tool_use = hooks.setdefault("PreToolUse", [])

    added = 0
    for entry in HOOK_ENTRIES:
        if _entry_registered(pre_tool_use, entry["matcher"]):
            continue
        pre_tool_use.append(entry)
        added += 1

    if added:
        print(f"✓ Registered {added} PreToolUse hook entr{'y' if added == 1 else 'ies'}: {HOOK_SCRIPT}")
    else:
        print("✓ Hooks already registered — skipping")

    _write_settings(settings)
    print(f"✓ Settings written to {SETTINGS_PATH}")


def uninstall():
    if not SETTINGS_PATH.exists():
        print("No settings.json found — nothing to remove")
        return

    settings = _load_settings()
    changed = False

    hooks = settings.get("hooks", {})
    pre_tool_use = hooks.get("PreToolUse", [])
    before = len(pre_tool_use)
    hooks["PreToolUse"] = [
        entry for entry in pre_tool_use
        if not any(h.get("command") == HOOK_SCRIPT for h in entry.get("hooks", []))
    ]
    if len(hooks["PreToolUse"]) < before:
        print("✓ Removed scratch-guard PreToolUse hook entries")
        changed = True
    if not hooks["PreToolUse"]:
        del hooks["PreToolUse"]
    if not hooks:
        settings.pop("hooks", None)

    if changed:
        _write_settings(settings)
        print(f"✓ Settings written to {SETTINGS_PATH}")
    else:
        print("No scratch-guard entries found in settings.json")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "install"
    if cmd == "install":
        install()
    elif cmd == "uninstall":
        uninstall()
    else:
        print(f"Unknown command: {cmd}. Use 'install' or 'uninstall'.")
        sys.exit(1)
