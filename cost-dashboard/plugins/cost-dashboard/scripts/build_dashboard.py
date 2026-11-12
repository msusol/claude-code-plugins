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
SPEED_FLAGS = set()    # non-standard speed / service tier values seen; priced at standard rates and flagged, not guessed


def price_for(model, context=0):
    """The rate entry for a model: first key that is a substring of the name; a matching tier replaces input/output by prompt size."""
    m = (model or "").lower()
    for key, val in PRICING["models"].items():
        if key in m:
            for tier in sorted(val.get("tiers", []), key=lambda t: t["over_tokens"]):
                if context > tier["over_tokens"]:
                    val = {**val, **{k: v for k, v in tier.items() if k != "over_tokens"}}
            return val
    UNPRICED.add(model or "unknown")
    return PRICING["fallback"]


def read_multiplier(pr):
    return pr.get("cache_read_multiplier", PRICING["cache_read_multiplier"])


def write_split(u):
    """(5-minute, 1-hour) cache-write tokens of one call. Without the log's breakdown every write counts as 5-minute."""
    total = u.get("cache_creation_input_tokens", 0) or 0
    cc = u.get("cache_creation")
    one_h = (cc.get("ephemeral_1h_input_tokens", 0) or 0) if isinstance(cc, dict) else 0
    one_h = min(one_h, total)
    return total - one_h, one_h


def cost_parts(model, u):
    """USD cost of one call split by token type: fresh input, output, cache write, cache read."""
    pr = price_for(model, context_tokens(u))
    inp = u.get("input_tokens", 0) or 0
    out = u.get("output_tokens", 0) or 0
    cr = u.get("cache_read_input_tokens", 0) or 0
    w5, w1 = write_split(u)
    return {"input": inp * pr["input"] / 1e6,
            "output": out * pr["output"] / 1e6,
            "cache_write": (w5 * PRICING["cache_write_multiplier"] + w1 * PRICING.get("cache_write_1h_multiplier", 2.0)) * pr["input"] / 1e6,
            "cache_read": cr * pr["input"] * read_multiplier(pr) / 1e6}


def cost_of(model, u):
    return sum(cost_parts(model, u).values())


def rate_card(model):
    """The USD per million tokens this model is priced at, for display."""
    pr = price_for(model)
    w5, w1 = PRICING["cache_write_multiplier"], PRICING.get("cache_write_1h_multiplier", 2.0)
    card = {"input": pr["input"], "output": pr["output"], "cache_write_5m": round(pr["input"] * w5, 6),
            "cache_write_1h": round(pr["input"] * w1, 6), "cache_read": round(pr["input"] * read_multiplier(pr), 6),
            "read_multiplier": read_multiplier(pr)}
    if pr.get("tiers"):
        card["tiers"] = [{"over_tokens": t["over_tokens"], "input": t.get("input", pr["input"]), "output": t.get("output", pr["output"])}
                         for t in pr["tiers"]]
    return card


def context_tokens(u):
    """Everything sent to the model on one call: fresh input plus cache writes plus cache reads."""
    return ((u.get("input_tokens", 0) or 0) + (u.get("cache_creation_input_tokens", 0) or 0)
            + (u.get("cache_read_input_tokens", 0) or 0))


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


def effort_of(e):
    """The effort level of one assistant call: the per-turn value, else the session value, else "unknown"."""
    v = e.get("perTurnEffort") or e.get("effort")
    return str(v).strip().lower() if v else "unknown"


def new_cell():
    """One model-at-one-effort tally. In = everything sent to the model (fresh input, cache writes, cache reads); out = what it wrote."""
    return {"cost": 0.0, "calls": 0, "in_tok": 0, "out_tok": 0, "in_cost": 0.0, "out_cost": 0.0}


def add_call(cell, parts, u):
    """Add one priced call (its cost_parts and usage) to a cell."""
    in_cost = parts["input"] + parts["cache_write"] + parts["cache_read"]
    cell["cost"] += in_cost + parts["output"]
    cell["calls"] += 1
    cell["in_tok"] += context_tokens(u)
    cell["out_tok"] += u.get("output_tokens", 0) or 0
    cell["in_cost"] += in_cost
    cell["out_cost"] += parts["output"]


def rounded_cell(c):
    return {"cost": round(c["cost"], 4), "calls": c["calls"], "in_tok": c["in_tok"], "out_tok": c["out_tok"],
            "in_cost": round(c["in_cost"], 4), "out_cost": round(c["out_cost"], 4)}


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
                                    "cost": 0.0, "sub_cost": 0.0, "tokens": blank_tokens(), "calls": 0,
                                    "me": {}}
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
                       "effort": effort_of(e), "speed": u.get("speed"), "tier": u.get("service_tier"),
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
            "cost": 0.0, "sub_cost": 0.0, "tokens": blank_tokens(), "models": {}, "turns": [], "calls": 0,
            "matrix": {}, "daily_me": {},
            "parts": blank_tokens(), "ctx_series": [], "cw1h": 0})
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
        m = s["models"].setdefault(rec["model"], {"cost": 0.0, "calls": 0, "ctx_tokens": 0, "ctx_cost": 0.0})
        m["cost"] += c
        m["calls"] += 1
        parts = cost_parts(rec["model"], rec["u"])
        m["ctx_tokens"] += context_tokens(rec["u"])
        m["ctx_cost"] += parts["input"] + parts["cache_write"] + parts["cache_read"]
        s["cw1h"] += write_split(rec["u"])[1]
        for k, v in parts.items():
            s["parts"][k] += v
        if not rec["sub"]:
            s["ctx_series"].append(context_tokens(rec["u"]))     # the main conversation's context; subagents carry their own
        eff = rec["effort"]
        add_call(s["matrix"].setdefault(rec["model"], {}).setdefault(eff, new_cell()), parts, rec["u"])
        for key, val, normal in (("speed", rec["speed"], "standard"), ("service_tier", rec["tier"], "standard"),
                                 ("inference_geo", rec["u"].get("inference_geo"), "global")):
            if val and val != normal:
                SPEED_FLAGS.add("%s=%s" % (key, val))
        s.setdefault("daily", {})
        if ts:
            d = ts.astimezone().strftime("%Y-%m-%d")
            s["daily"][d] = s["daily"].get(d, 0.0) + c
            day_me = s["daily_me"].setdefault(d, {}).setdefault(rec["model"], {})
            day_me[eff] = day_me.get(eff, 0.0) + c
        t = rec["turn"]
        if t is not None:
            t["cost"] += c
            t["calls"] += 1
            add_call(t["me"].setdefault(rec["model"], {}).setdefault(eff, new_cell()), parts, rec["u"])
            if rec["sub"]:
                t["sub_cost"] += c
            add_tokens(t["tokens"], rec["u"])

    # attach this file's turns to the session they belong to
    if turns_for_file:
        sid = file_session
        if sid in sessions:
            sessions[sid]["turns"].extend(t for t in turns_for_file if t["calls"] > 0)


MAX_CTX_POINTS = 240
RESET_DROP = 0.7     # a call whose context is under 70% of the previous call's is counted as a reset (/clear or compaction)


def context_summary(series):
    """Stats and a bounded series for the context-per-call chart.

    Resets are found on the full series. A longer series is shrunk to at most MAX_CTX_POINTS by keeping the largest value in each
    bucket, so peaks survive; `bucket` is the number of calls each point stands for and `reset_at` indexes the shrunk series.
    """
    n = len(series)
    if not n:
        return {"calls": 0, "avg": 0, "peak": 0, "last": 0, "resets": 0, "reset_at": [], "bucket": 1, "series": []}
    resets = [i for i in range(1, n) if series[i] < RESET_DROP * series[i - 1]]
    bucket = -(-n // MAX_CTX_POINTS)
    pts = [max(series[i:i + bucket]) for i in range(0, n, bucket)] if bucket > 1 else list(series)
    return {"calls": n, "avg": round(sum(series) / n), "peak": max(series), "last": series[-1], "resets": len(resets),
            "reset_at": sorted({i // bucket for i in resets}), "bucket": bucket, "series": pts}


def rounded_map(d):
    return {k: round(v, 4) for k, v in d.items()}


def rounded_cells(d):
    return {k: rounded_cell(v) for k, v in d.items()}


def log_files(root):
    """Every session and subagent log under root."""
    return glob.glob(os.path.join(root, "**", "*.jsonl"), recursive=True)


def newest_mtime(root):
    """Newest modification time of any log under root (0.0 if none): a cheap 'did anything change' check."""
    newest = 0.0
    for f in log_files(root):
        try:
            newest = max(newest, os.stat(f).st_mtime)
        except OSError:
            pass
    return newest


def collect(root, days=30, project="", now=None):
    """Parse the logs under root and return the dashboard data dict.

    Pure with respect to the filesystem: reads logs, writes nothing. `now` is the
    clock (a datetime) and only exists so tests can fix `generated`.
    """
    UNPRICED.clear()
    SPEED_FLAGS.clear()
    sessions = {}
    for f in log_files(root):
        process_file(f, sessions)

    cutoff = None
    if days > 0:
        cutoff = datetime.now(timezone.utc) - timedelta(days=days)
    rows = []
    for s in sessions.values():
        if cutoff and (not s["last"] or s["last"] < cutoff):
            continue
        if project and project.lower() not in (s["project"] + " " + (s["cwd"] or "")).lower():
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
            "models": {k: {"cost": round(v["cost"], 4), "calls": v["calls"], "ctx_tokens": v["ctx_tokens"], "ctx_cost": round(v["ctx_cost"], 4)}
                       for k, v in s["models"].items()},
            "cw1h": s["cw1h"],
            "daily": {k: round(v, 4) for k, v in s.get("daily", {}).items()},
            "matrix": {m: rounded_cells(e) for m, e in s["matrix"].items()},
            "daily_me": {d: {m: rounded_map(e) for m, e in v.items()} for d, v in s["daily_me"].items()},
            "parts": rounded_map(s["parts"]),
            "ctx": context_summary(s["ctx_series"]),
            "turns": [{"ts": t["ts"], "prompt": t["prompt"], "cost": round(t["cost"], 4),
                       "sub_cost": round(t["sub_cost"], 4), "calls": t["calls"], "tokens": t["tokens"],
                       "me": {m: rounded_cells(e) for m, e in t["me"].items()}}
                      for t in turns],
        })
    rows.sort(key=lambda r: r["last"] or "", reverse=True)

    seen = sorted({m for r in rows for m in r["models"]})
    return {"generated": (now or datetime.now()).isoformat(timespec="seconds"), "days": days,
            "unpriced": sorted(UNPRICED), "speed_flags": sorted(SPEED_FLAGS), "sessions": rows,
            "rates": {m: rate_card(m) for m in seen}, "rates_source": PRICING.get("source", ""), "rates_verified": PRICING.get("verified", "")}


def render(data):
    """Return the self-contained dashboard page for a data dict from collect()."""
    tpl = (PLUGIN_ROOT / "scripts" / "template.html").read_text()
    blob = json.dumps(data).replace("</", "<\\/")
    return tpl.replace("/*__DATA__*/null", blob)


def summary(data, out):
    """The short text report printed after a build."""
    rows = data["sessions"]
    total = sum(r["cost"] for r in rows)
    lines = [f"Sessions: {len(rows)}   Estimated total: ${total:,.2f}   (last {data['days'] or 'all'} days)",
             "Top sessions:"]
    for r in sorted(rows, key=lambda r: -r["cost"])[:5]:
        lines.append(f"  ${r['cost']:>8.2f}  {r['project'][:20]:<20}  {r['title'][:60]}")
    by_me = {}
    for r in rows:
        for m, efforts in r["matrix"].items():
            for e, v in efforts.items():
                x = by_me.setdefault((m, e), {"cost": 0.0, "calls": 0})
                x["cost"] += v["cost"]
                x["calls"] += v["calls"]
    if by_me:
        lines.append("By model and effort:")
        for (m, e), v in sorted(by_me.items(), key=lambda kv: -kv[1]["cost"])[:6]:
            lines.append(f"  {m} · {e}: ${v['cost']:,.2f} ({v['calls']} calls)")
    if data["speed_flags"]:
        lines.append("Non-standard speed/tier seen (priced at standard rates): " + ", ".join(data["speed_flags"]))
    if data["unpriced"]:
        lines.append("Unpriced models (used fallback rates): " + ", ".join(data["unpriced"]))
    lines.append(f"Dashboard: {out}")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.path.expanduser("~/.claude/projects"))
    ap.add_argument("--days", type=int, default=30, help="only sessions active in the last N days (0 = all)")
    ap.add_argument("--project", default="", help="substring filter on project dir / cwd")
    ap.add_argument("--out", default=os.path.expanduser("~/.claude/cost-dashboard.html"))
    args = ap.parse_args()

    if not log_files(args.root):
        print(f"No session logs found under {args.root}")
        sys.exit(1)

    data = collect(args.root, args.days, args.project)
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(render(data))
    print(summary(data, out))


if __name__ == "__main__":
    main()
