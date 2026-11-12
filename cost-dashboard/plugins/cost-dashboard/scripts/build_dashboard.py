#!/usr/bin/env python3
"""Build a self-contained HTML cost dashboard from Claude Code session logs.

Reads ~/.claude/projects/**/*.jsonl, estimates cost from token usage, and
aggregates per session, per task (user prompt turn), per model, per day, and
subagent vs. main-thread.
"""
import argparse
import glob
import json
import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

PLUGIN_ROOT = Path(__file__).resolve().parent.parent


def load_pricing():
    p = PLUGIN_ROOT / "pricing.json"
    try:
        return json.loads(p.read_text())
    except Exception:
        return {"cache_write_multiplier": 1.25, "cache_read_multiplier": 0.1,
                "models": {"opus": {"input": 5, "output": 25}, "sonnet": {"input": 3, "output": 15},
                           "haiku": {"input": 1, "output": 5}},
                "fallback": {"input": 3, "output": 15}}


PRICING = load_pricing()
UNPRICED = set()


def price_for(model):
    m = (model or "").lower()
    for key, val in PRICING["models"].items():
        if key in m:
            return val
    UNPRICED.add(model or "unknown")
    return PRICING["fallback"]


def cost_of(model, u):
    pr = price_for(model)
    inp = u.get("input_tokens", 0) or 0
    out = u.get("output_tokens", 0) or 0
    cw = u.get("cache_creation_input_tokens", 0) or 0
    cr = u.get("cache_read_input_tokens", 0) or 0
    return (inp * pr["input"]
            + out * pr["output"]
            + cw * pr["input"] * PRICING["cache_write_multiplier"]
            + cr * pr["input"] * PRICING["cache_read_multiplier"]) / 1e6


def parse_ts(s):
    if not s:
        return None
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except Exception:
        return None


def prompt_text(msg):
    """Return user prompt text if this is a real human prompt, else None."""
    c = msg.get("content")
    if isinstance(c, str):
        t = c.strip()
    elif isinstance(c, list):
        if any(isinstance(b, dict) and b.get("type") == "tool_result" for b in c):
            return None
        t = " ".join(b.get("text", "") for b in c if isinstance(b, dict) and b.get("type") == "text").strip()
    else:
        return None
    if not t or t.startswith("<command-") or t.startswith("<local-command") or t.startswith("Caveat:"):
        return None
    return t


def blank_tokens():
    return {"input": 0, "output": 0, "cache_write": 0, "cache_read": 0}


def add_tokens(t, u):
    t["input"] += u.get("input_tokens", 0) or 0
    t["output"] += u.get("output_tokens", 0) or 0
    t["cache_write"] += u.get("cache_creation_input_tokens", 0) or 0
    t["cache_read"] += u.get("cache_read_input_tokens", 0) or 0


def process_file(path, sessions):
    p = Path(path)
    parts = p.parts
    is_sub_file = "subagents" in parts
    if is_sub_file:
        i = parts.index("subagents")
        file_session = parts[i - 1]
        project = parts[i - 2] if i >= 2 else ""
    else:
        file_session = p.stem
        project = p.parent.name

    seen = {}   # dedupe streamed duplicates: key -> record
    order = []
    current_turn = None
    turns_for_file = []
    cwd = None

    try:
        fh = open(path, "r", encoding="utf-8", errors="replace")
    except OSError:
        return
    with fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                e = json.loads(line)
            except Exception:
                continue
            cwd = cwd or e.get("cwd")
            typ = e.get("type")
            sid = e.get("sessionId") or file_session
            if is_sub_file:
                sid = file_session
            if typ == "user" and not e.get("isSidechain") and not is_sub_file and not e.get("isMeta"):
                t = prompt_text(e.get("message", {}))
                if t:
                    current_turn = {"ts": e.get("timestamp"), "prompt": t[:140].replace("\n", " "),
                                    "cost": 0.0, "sub_cost": 0.0, "tokens": blank_tokens(), "calls": 0}
                    turns_for_file.append(current_turn)
            elif typ == "assistant":
                msg = e.get("message", {})
                u = msg.get("usage")
                if not u:
                    continue
                model = msg.get("model") or "unknown"
                if model == "<synthetic>":
                    continue
                key = (msg.get("id"), e.get("requestId")) if msg.get("id") else None
                rec = {"sid": sid, "ts": e.get("timestamp"), "model": model, "u": u,
                       "sub": bool(e.get("isSidechain")) or is_sub_file,
                       "turn": current_turn}
                if key and key in seen:
                    seen[key].update(rec)   # keep the last (final usage) record
                else:
                    if key:
                        seen[key] = rec
                    order.append(rec)

    for rec in order:
        sid = rec["sid"]
        s = sessions.setdefault(sid, {
            "id": sid, "project": project, "cwd": None, "first": None, "last": None,
            "cost": 0.0, "sub_cost": 0.0, "tokens": blank_tokens(), "models": {}, "turns": [], "calls": 0})
        if cwd and not s["cwd"]:
            s["cwd"] = cwd
        c = cost_of(rec["model"], rec["u"])
        ts = parse_ts(rec["ts"])
        if ts:
            if not s["first"] or ts < s["first"]:
                s["first"] = ts
            if not s["last"] or ts > s["last"]:
                s["last"] = ts
        s["cost"] += c
        s["calls"] += 1
        if rec["sub"]:
            s["sub_cost"] += c
        add_tokens(s["tokens"], rec["u"])
        m = s["models"].setdefault(rec["model"], {"cost": 0.0, "calls": 0})
        m["cost"] += c
        m["calls"] += 1
        s.setdefault("daily", {})
        if ts:
            d = ts.astimezone().strftime("%Y-%m-%d")
            s["daily"][d] = s["daily"].get(d, 0.0) + c
        t = rec["turn"]
        if t is not None:
            t["cost"] += c
            t["calls"] += 1
            if rec["sub"]:
                t["sub_cost"] += c
            add_tokens(t["tokens"], rec["u"])

    # attach this file's turns to the session they belong to
    if turns_for_file:
        sid = file_session
        if sid in sessions:
            sessions[sid]["turns"].extend(t for t in turns_for_file if t["calls"] > 0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.path.expanduser("~/.claude/projects"))
    ap.add_argument("--days", type=int, default=30, help="only sessions active in the last N days (0 = all)")
    ap.add_argument("--project", default="", help="substring filter on project dir / cwd")
    ap.add_argument("--out", default=os.path.expanduser("~/.claude/cost-dashboard.html"))
    args = ap.parse_args()

    files = glob.glob(os.path.join(args.root, "**", "*.jsonl"), recursive=True)
    if not files:
        print(f"No session logs found under {args.root}")
        sys.exit(1)

    sessions = {}
    for f in files:
        process_file(f, sessions)

    cutoff = None
    if args.days > 0:
        cutoff = datetime.now(timezone.utc) - timedelta(days=args.days)
    rows = []
    for s in sessions.values():
        if cutoff and (not s["last"] or s["last"] < cutoff):
            continue
        if args.project and args.project.lower() not in (s["project"] + " " + (s["cwd"] or "")).lower():
            continue
        turns = sorted(s["turns"], key=lambda t: t["ts"] or "")
        first_prompt = turns[0]["prompt"] if turns else "(no prompt found)"
        rows.append({
            "id": s["id"], "project": os.path.basename(s["cwd"] or "") or s["project"],
            "title": first_prompt,
            "first": s["first"].isoformat() if s["first"] else None,
            "last": s["last"].isoformat() if s["last"] else None,
            "cost": round(s["cost"], 4), "sub_cost": round(s["sub_cost"], 4),
            "calls": s["calls"], "tokens": s["tokens"],
            "models": {k: {"cost": round(v["cost"], 4), "calls": v["calls"]} for k, v in s["models"].items()},
            "daily": {k: round(v, 4) for k, v in s.get("daily", {}).items()},
            "turns": [{"ts": t["ts"], "prompt": t["prompt"], "cost": round(t["cost"], 4),
                       "sub_cost": round(t["sub_cost"], 4), "calls": t["calls"], "tokens": t["tokens"]}
                      for t in turns],
        })
    rows.sort(key=lambda r: r["last"] or "", reverse=True)

    data = {"generated": datetime.now().isoformat(timespec="seconds"), "days": args.days,
            "unpriced": sorted(UNPRICED), "sessions": rows}
    tpl = (PLUGIN_ROOT / "scripts" / "template.html").read_text()
    blob = json.dumps(data).replace("</", "<\\/")
    html = tpl.replace("/*__DATA__*/null", blob)
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(html)

    total = sum(r["cost"] for r in rows)
    print(f"Sessions: {len(rows)}   Estimated total: ${total:,.2f}   (last {args.days or 'all'} days)")
    print("Top sessions:")
    for r in sorted(rows, key=lambda r: -r["cost"])[:5]:
        print(f"  ${r['cost']:>8.2f}  {r['project'][:20]:<20}  {r['title'][:60]}")
    if UNPRICED:
        print("Unpriced models (used fallback rates): " + ", ".join(sorted(UNPRICED)))
    print(f"Dashboard: {out}")


if __name__ == "__main__":
    main()
