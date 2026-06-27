#!/usr/bin/env python3
"""
Idempotent manager for kaggle-guard entries in ~/.claude/settings.json.

Usage:
  python3 manage-settings.py install    # Merge hook (safe to re-run)
  python3 manage-settings.py uninstall  # Remove kaggle-guard entries only
"""

import json
import shutil
import sys
import tempfile
from pathlib import Path

SETTINGS_PATH = Path.home() / ".claude" / "settings.json"
HOOK_SCRIPT = str(Path.home() / ".claude" / "scripts" / "kaggle-guard-hook.zsh")

KAGGLE_GUARD_HOOK_ENTRY = {
    "matcher": "Bash",
    "hooks": [{"type": "command", "command": HOOK_SCRIPT}],
}


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


def _hook_already_registered(pre_tool_use_list):
    for entry in pre_tool_use_list:
        for h in entry.get("hooks", []):
            if h.get("command") == HOOK_SCRIPT:
                return True
    return False


def install():
    settings = _load_settings()
    hooks = settings.setdefault("hooks", {})
    pre_tool_use = hooks.setdefault("PreToolUse", [])

    if _hook_already_registered(pre_tool_use):
        print("✓ Hook already registered — skipping")
    else:
        pre_tool_use.append(KAGGLE_GUARD_HOOK_ENTRY)
        print(f"✓ Registered PreToolUse hook: {HOOK_SCRIPT}")

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
        print("✓ Removed kaggle-guard PreToolUse hook")
        changed = True
    if not hooks["PreToolUse"]:
        del hooks["PreToolUse"]
    if not hooks:
        settings.pop("hooks", None)

    if changed:
        _write_settings(settings)
        print(f"✓ Settings written to {SETTINGS_PATH}")
    else:
        print("No kaggle-guard entries found in settings.json")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "install"
    if cmd == "install":
        install()
    elif cmd == "uninstall":
        uninstall()
    else:
        print(f"Unknown command: {cmd}. Use 'install' or 'uninstall'.")
        sys.exit(1)
