#!/usr/bin/env python3
"""
Idempotent manager for git-guard entries in ~/.claude/settings.json.

Usage:
  python3 manage-settings.py install    # Merge hooks + deny rules (safe to re-run)
  python3 manage-settings.py uninstall  # Remove git-guard entries only
"""

import json
import os
import platform
import shutil
import sys
import tempfile
from pathlib import Path

SETTINGS_PATH = Path.home() / ".claude" / "settings.json"
HOOK_SCRIPT = str(Path.home() / ".claude" / "scripts" / "git-guard-hook.zsh")

# Deny rules that apply everywhere (relative paths work in both global and project settings)
DENY_RULES_COMMON = [
    "Read(./node_modules/**)",
    "Read(./vendor/**)",
    "Read(./.venv/**)",
    "Read(./env/**)",
    "Read(./venv/**)",
    "Read(./dist/**)",
    "Read(./build/**)",
    "Read(./.next/**)",
    "Read(./out/**)",
    "Read(./**/*.sqlite)",
    "Read(./**/*.db)",
    "Read(./data/raw/**)",
    "Read(./**/*.jsonl)",
    "Read(./.env)",
    "Read(./.env.*)",
    "Read(./**/*.pem)",
    "Read(./**/*.key)",
    "Read(./secrets/**)",
    "Read(./logs/**)",
    "Read(./**/*.log)",
    "Read(./tmp/**)",
    "Read(./**/.DS_Store)",
    "Read(./.idea/**)",
    "Read(./.vscode/**)",
    "Bash(git init*)",
    "Bash(gh repo create*)",
    "Bash(git push*)",
    "Bash(rm -rf *)",
]

def _platform_deny_rules():
    """Returns OS-specific deny rules for shell configs and SSH keys."""
    if platform.system() == "Darwin":
        home_glob = "/Users/**"
    else:
        home_glob = "/home/**"
    return [
        f"Read({home_glob}/.zshrc)",
        f"Read({home_glob}/.zprofile)",
        f"Read({home_glob}/.bash_profile)",
        f"Read({home_glob}/.bashrc)",
        f"Read({home_glob}/.ssh/**)",
    ]

ALL_DENY_RULES = DENY_RULES_COMMON + _platform_deny_rules()

GIT_GUARD_HOOK_ENTRY = {
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
    # Atomic write via temp file
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

    # --- Hooks ---
    hooks = settings.setdefault("hooks", {})
    pre_tool_use = hooks.setdefault("PreToolUse", [])

    if _hook_already_registered(pre_tool_use):
        print("✓ Hook already registered — skipping")
    else:
        pre_tool_use.append(GIT_GUARD_HOOK_ENTRY)
        print(f"✓ Registered PreToolUse hook: {HOOK_SCRIPT}")

    # --- Deny rules ---
    permissions = settings.setdefault("permissions", {})
    deny = permissions.setdefault("deny", [])

    added = 0
    for rule in ALL_DENY_RULES:
        if rule not in deny:
            deny.append(rule)
            added += 1

    if added:
        print(f"✓ Added {added} deny rule(s) to permissions.deny")
    else:
        print("✓ All deny rules already present — skipping")

    _write_settings(settings)
    print(f"✓ Settings written to {SETTINGS_PATH}")


def uninstall():
    if not SETTINGS_PATH.exists():
        print("No settings.json found — nothing to remove")
        return

    settings = _load_settings()
    changed = False

    # --- Remove hook ---
    hooks = settings.get("hooks", {})
    pre_tool_use = hooks.get("PreToolUse", [])
    before = len(pre_tool_use)
    hooks["PreToolUse"] = [
        entry for entry in pre_tool_use
        if not any(h.get("command") == HOOK_SCRIPT for h in entry.get("hooks", []))
    ]
    if len(hooks["PreToolUse"]) < before:
        print("✓ Removed git-guard PreToolUse hook")
        changed = True
    if not hooks["PreToolUse"]:
        del hooks["PreToolUse"]
    if not hooks:
        settings.pop("hooks", None)

    # --- Remove deny rules ---
    guard_rules = set(ALL_DENY_RULES)
    deny = settings.get("permissions", {}).get("deny", [])
    before = len(deny)
    remaining = [r for r in deny if r not in guard_rules]
    removed = before - len(remaining)
    if removed:
        settings.setdefault("permissions", {})["deny"] = remaining
        if not settings["permissions"]["deny"]:
            del settings["permissions"]["deny"]
        if not settings.get("permissions"):
            settings.pop("permissions", None)
        print(f"✓ Removed {removed} deny rule(s)")
        changed = True

    if changed:
        _write_settings(settings)
        print(f"✓ Settings written to {SETTINGS_PATH}")
    else:
        print("No git-guard entries found in settings.json")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "install"
    if cmd == "install":
        install()
    elif cmd == "uninstall":
        uninstall()
    else:
        print(f"Unknown command: {cmd}. Use 'install' or 'uninstall'.")
        sys.exit(1)
