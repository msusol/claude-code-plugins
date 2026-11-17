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
import re
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
LAUNCHES = {}          # run name -> [(timestamp, session id)] of the ordinary sessions whose Bash calls started that run (see launched_runs)


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


# A run is started by `run-ab.zsh run|resume|solve|review-loop|review-round <name>` (or the same through solver.zsh). The session that ran
# that Bash command is the run's parent: an orchestrator that handed a task to a solver, or the session that drove an A/B arm.
LAUNCH_RE = re.compile(r"(?:run-ab\.zsh|solver\.zsh)\s+(?:run|resume|solve|review-loop|review-round)\s+([a-z0-9]+(?:-[a-z0-9]+)*)")
# `run-pilot.zsh start <label> --go` starts one run per arm, named pilot-<label>-<arm> (a, b and c, or the arms in PILOT_ARMS="c"). Without --go it
# is a dry run that starts nothing, so it links nothing.
PILOT_RE = re.compile(r"run-pilot\.zsh\s+start\s+([a-z0-9]+(?:-[a-z0-9]+)*)([^|;&]*)")
PILOT_ARMS_RE = re.compile(r"PILOT_ARMS=[\"']?([abc](?: [abc])*)")


def pilot_runs(cmd):
    """Names of the arm runs one `run-pilot.zsh start <label> --go` command starts (none for a dry run)."""
    out = []
    for label, rest in PILOT_RE.findall(cmd):
        if "--go" in rest.split():
            m = PILOT_ARMS_RE.search(cmd)
            out.extend("pilot-%s-%s" % (label, arm) for arm in (m.group(1).split() if m else ["a", "b", "c"]))
    return out


def launched_runs(msg):
    """Names of the runs started by the Bash tool calls in one assistant message."""
    out = []
    c = msg.get("content")
    if isinstance(c, list):
        for blk in c:
            if isinstance(blk, dict) and blk.get("type") == "tool_use" and blk.get("name") == "Bash":
                cmd = (blk.get("input") or {}).get("command")
                if isinstance(cmd, str):
                    out.extend(LAUNCH_RE.findall(cmd))
                    out.extend(pilot_runs(cmd))
    return out


SECRET_RE = re.compile(r"(sk-ant-[A-Za-z0-9_-]{6,}|gh[pousr]_[A-Za-z0-9]{16,}|github_pat_[A-Za-z0-9_]{16,}|AKIA[0-9A-Z]{12,})")


def _short(text, n):
    t = SECRET_RE.sub("[secret]", " ".join(str(text).split()))
    return t if len(t) <= n else t[: n - 1] + "…"


def call_blocks(msg):
    """One (kind, text) pair per content block of an assistant message: a tool call (`Bash: pytest -q`, `Read: docs/plan.md`), a text reply, or thinking."""
    out = []
    c = msg.get("content")
    if not isinstance(c, list):
        return out
    for blk in c:
        if not isinstance(blk, dict):
            continue
        kind = blk.get("type")
        if kind == "tool_use":
            name, inp = blk.get("name") or "tool", blk.get("input") or {}
            arg = (inp.get("command") or inp.get("file_path") or inp.get("path") or inp.get("pattern") or inp.get("url")
                   or inp.get("description") or inp.get("prompt") or inp.get("query") or "") if isinstance(inp, dict) else ""
            out.append(("tool", name + (": " + _short(arg, 70) if arg else "")))
        elif kind == "text" and (blk.get("text") or "").strip():
            out.append(("text", _short(blk["text"], 70)))
        elif kind == "thinking":
            out.append(("think", "thinking"))
    return out


def call_summary(blocks):
    """What one model call did, in a line: its first tool call (and how many more), else the start of its reply, else thinking."""
    tools = [t for k, t in blocks if k == "tool"]
    if tools:
        return tools[0] + (" (+%d more)" % (len(tools) - 1) if len(tools) > 1 else "")
    texts = [t for k, t in blocks if k == "text"]
    if texts:
        return "reply: " + texts[0]
    return "thinking" if blocks else ""


def run_kind(ab_root, run):
    """"solver" for a run made by `solve`, otherwise "A/B" (an arm), read from the run's step log."""
    try:
        with open(os.path.join(ab_root, run + ".reviews", "steps.csv"), encoding="utf-8") as fh:
            types = {ln.split(",")[2] for ln in fh.read().splitlines()[1:] if ln.count(",") >= 2}
    except OSError:
        return "A/B"
    return "solver" if "solve" in types else "A/B"


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


TOOL_TURN = {}      # id of an Agent/Task tool call -> the turn (task) that made it, so a subagent's cost can land on that task
SUBAGENT_TOOLS = ("Agent", "Task")


CALL_SINK = None    # ab_steps sets this to a list to receive every priced call (ts, model, cost, tokens); None in normal builds


def process_file(path, sessions, project_name=None, ab=None):
    """Parse one log into `sessions`. project_name and ab (a run name) label the sessions of an A/B run, whose container always logs as /work."""
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
    if project_name:
        project = project_name

    sub_launch, sub_type = None, None
    if is_sub_file:
        # <session>/subagents/agent-X.jsonl has agent-X.meta.json beside it, naming the tool call that launched it and its agent type
        try:
            with open(str(p)[: -len(".jsonl")] + ".meta.json", "r", encoding="utf-8") as mf:
                meta = json.load(mf)
            sub_launch, sub_type = meta.get("toolUseId"), meta.get("agentType")
        except (OSError, ValueError, AttributeError):
            pass
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
                if not is_sub_file and not e.get("isSidechain") and current_turn is not None and isinstance(msg.get("content"), list):
                    for blk in msg["content"]:
                        if isinstance(blk, dict) and blk.get("type") == "tool_use" and blk.get("name") in SUBAGENT_TOOLS and blk.get("id"):
                            TOOL_TURN[blk["id"]] = current_turn
                if ab is None:      # a run's own container session never counts as its parent
                    for run in launched_runs(msg):
                        LAUNCHES.setdefault(run, []).append((e.get("timestamp") or "", sid))
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
                       "turn": TOOL_TURN.get(sub_launch) if is_sub_file else current_turn,
                       "agent": sub_type or "subagent" if is_sub_file else None,
                       "launches": [blk["id"] for blk in (msg.get("content") if isinstance(msg.get("content"), list) else [])
                                    if isinstance(blk, dict) and blk.get("type") == "tool_use" and blk.get("name") in SUBAGENT_TOOLS and blk.get("id")],
                       "launch": sub_launch if is_sub_file else None,
                       "blocks": call_blocks(msg) if (ab or CALL_SINK is not None) else []}
                if key and key in seen:
                    merged = seen[key].get("blocks", []) + rec["blocks"]    # a call is spread over several lines, one per content block
                    merged_launches = seen[key].get("launches", []) + rec["launches"]
                    seen[key].update(rec)   # keep the last (final usage) record
                    seen[key]["blocks"] = merged
                    seen[key]["launches"] = merged_launches
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
            "parts": blank_tokens(), "ctx_series": [], "cw1h": 0, "stamps": []})
        if ab:
            s["ab"] = ab
        if cwd and not s["cwd"]:
            s["cwd"] = cwd
        c = cost_of(rec["model"], rec["u"])
        ts = parse_ts(rec["ts"])
        if ts:
            s["stamps"].append(ts)
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
        if CALL_SINK is not None and ts:
            CALL_SINK.append({"ts": ts, "model": rec["model"], "cost": c, "in_tok": context_tokens(rec["u"]),
                              "out_tok": rec["u"].get("output_tokens", 0) or 0,
                              "in_cost": parts["input"] + parts["cache_write"] + parts["cache_read"], "out_cost": parts["output"],
                              "effort": rec["effort"], "sub": bool(rec["sub"]), "what": call_summary(rec.get("blocks", [])), "sid": rec["sid"],
                              "launches": rec.get("launches") or [], "launch": rec.get("launch"), "agent": rec.get("agent")})
        m["ctx_tokens"] += context_tokens(rec["u"])
        m["ctx_cost"] += parts["input"] + parts["cache_write"] + parts["cache_read"]
        if ab:   # a run's session keeps its individual calls (a few hundred over all runs), so the page can list them; ordinary sessions do not
            entry = {
                "ts": rec["ts"], "model": rec["model"], "effort": rec["effort"], "sub": bool(rec["sub"]),
                "in_tok": context_tokens(rec["u"]), "out_tok": rec["u"].get("output_tokens", 0) or 0, "what": call_summary(rec.get("blocks", [])),
                "in_cost": round(parts["input"] + parts["cache_write"] + parts["cache_read"], 4), "out_cost": round(parts["output"], 4), "cost": round(c, 4),
                "turn": (rec["turn"] or {}).get("ts")}      # the task (turn) it belongs to; a subagent's calls belong to the task that launched it
            if rec.get("launches"):
                entry["launches"] = rec["launches"]         # ids of the Agent/Task tool calls this call made, so the page can nest the subagents' calls under it
            if rec.get("launch"):
                entry["launch"] = rec["launch"]             # a subagent's call: the id of the tool call that launched its agent
                entry["agent"] = rec.get("agent")
            s.setdefault("call_list", []).append(entry)
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
            if rec.get("agent"):
                k = (rec["agent"], rec["model"])
                subs = t.setdefault("subs", {})
                subs[k] = subs.get(k, 0.0) + c
            add_tokens(t["tokens"], rec["u"])

    # attach this file's turns to the session they belong to
    if turns_for_file:
        sid = file_session
        if sid in sessions:
            sessions[sid]["turns"].extend(t for t in turns_for_file if t["calls"] > 0)


MAX_CTX_POINTS = 240
IDLE_SECONDS = 600     # a gap between two calls longer than this is you being away, not the model working


def active_seconds(stamps):
    """Time the session was busy: the sum of the gaps between consecutive calls that are no longer than IDLE_SECONDS."""
    ordered = sorted(stamps)
    return round(sum(g for g in ((b - a).total_seconds() for a, b in zip(ordered, ordered[1:])) if g <= IDLE_SECONDS))

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
    files = glob.glob(os.path.join(root, "**", "*.jsonl"), recursive=True)
    return sorted(files, key=lambda f: ("subagents" in Path(f).parts, f))    # main logs first: a subagent's cost needs the turn that launched it


def newest_mtime(root):
    """Newest modification time of any log under root (0.0 if none): a cheap 'did anything change' check."""
    newest = 0.0
    for f in log_files(root):
        try:
            newest = max(newest, os.stat(f).st_mtime)
        except OSError:
            pass
    return newest


def collect(root, days=30, project="", now=None, ab_root=None, ab_sessions=True):
    """Parse the logs under root and return the dashboard data dict.

    ab_root is the folder of A/B runs (<run>.reviews/steps.csv and <run>.session); when it holds any, the data gets an "ab" section, and
    (unless ab_sessions is False) each run's session logs also count as ordinary sessions, tagged "ab" and named after the run, so every
    tab includes what the A/B runs cost. Their containers are not under `root`, which is why they need reading from here.

    Pure with respect to the filesystem: reads logs, writes nothing. `now` is the
    clock (a datetime) and only exists so tests can fix `generated`.
    """
    UNPRICED.clear()
    SPEED_FLAGS.clear()
    LAUNCHES.clear()
    TOOL_TURN.clear()
    sessions = {}
    ab_dirs = sorted(glob.glob(os.path.join(ab_root, "*.session"))) if ab_root and os.path.isdir(ab_root) else []
    ab_real = [os.path.realpath(d) + os.sep for d in ab_dirs]
    for f in log_files(root):
        if ab_real and os.path.realpath(f).startswith(tuple(ab_real)):
            continue    # --root happens to contain the runs folder: read those below, tagged, or not at all, never twice
        process_file(f, sessions)
    if ab_sessions:
        for d in ab_dirs:
            run = os.path.basename(d)[: -len(".session")]
            for f in log_files(d):
                process_file(f, sessions, project_name=run, ab=run)

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
            "id": s["id"], "project": s.get("ab") or os.path.basename(s["cwd"] or "") or s["project"],
            "title": first_prompt,
            "first": s["first"].isoformat() if s["first"] else None,
            "last": s["last"].isoformat() if s["last"] else None,
            "cost": round(s["cost"], 4), "sub_cost": round(s["sub_cost"], 4),
            "calls": s["calls"], "tokens": s["tokens"],
            "models": {k: {"cost": round(v["cost"], 4), "calls": v["calls"], "ctx_tokens": v["ctx_tokens"], "ctx_cost": round(v["ctx_cost"], 4)}
                       for k, v in s["models"].items()},
            "cw1h": s["cw1h"],
            "active_s": active_seconds(s["stamps"]),
            "daily": {k: round(v, 4) for k, v in s.get("daily", {}).items()},
            "matrix": {m: rounded_cells(e) for m, e in s["matrix"].items()},
            "daily_me": {d: {m: rounded_map(e) for m, e in v.items()} for d, v in s["daily_me"].items()},
            "parts": rounded_map(s["parts"]),
            "ctx": context_summary(s["ctx_series"]),
            "turns": [{"ts": t["ts"], "prompt": t["prompt"], "cost": round(t["cost"], 4),
                       "sub_cost": round(t["sub_cost"], 4), "calls": t["calls"], "tokens": t["tokens"],
                       "subs": [{"agent": a, "model": m, "cost": round(v, 4)} for (a, m), v in sorted(t.get("subs", {}).items())],
                       "me": {m: rounded_cells(e) for m, e in t["me"].items()}}
                      for t in turns],
        })
        if s.get("ab"):
            rows[-1]["ab"] = s["ab"]     # only A/B sessions carry this, so the data is unchanged for everyone else
            rows[-1]["call_list"] = sorted(s.get("call_list", []), key=lambda c: c["ts"] or "")   # likewise: one entry per model call, oldest first
    rows.sort(key=lambda r: r["last"] or "", reverse=True)

    # Link each run's session to the ordinary session that launched it (earliest launcher still in the data), and say what kind of run it is:
    # a "solver" (made by `solve`) or an "A/B" arm. Only A/B-tagged rows get these fields, so the data is unchanged for everyone else.
    row_ids = {r["id"] for r in rows}
    for r in rows:
        run = r.get("ab")
        if not run:
            continue
        r["kind"] = run_kind(ab_root, run) if ab_root else "A/B"
        launchers = sorted(c for c in LAUNCHES.get(run, []) if c[1] in row_ids and c[1] != r["id"])
        if launchers:
            r["parent"] = launchers[0][1]

    ab = None
    if ab_root and os.path.isdir(ab_root):
        sys.path.insert(0, str(Path(__file__).resolve().parent))    # `python3 -I script.py` leaves the script's folder off the path
        import ab_steps
        ab = ab_steps.collect_ab(ab_root, sys.modules[__name__], PRICING.get("copilot_usd_per_review"))

    seen = sorted({m for r in rows for m in r["models"]})
    data = {"generated": (now or datetime.now()).isoformat(timespec="seconds"), "days": days,
            "unpriced": sorted(UNPRICED), "speed_flags": sorted(SPEED_FLAGS), "sessions": rows,
            "rates": {m: rate_card(m) for m in seen}, "rates_source": PRICING.get("source", ""), "rates_verified": PRICING.get("verified", "")}
    if ab:
        data["ab"] = ab     # only present when there are A/B runs, so the data is unchanged for everyone else
    return data


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
    if data.get("ab"):
        lines.append("A/B runs:")
        for r in data["ab"]["runs"]:
            t = r["totals"]
            clean = "round %d" % t["clean_round"] if t["clean_round"] else "not clean"
            if not r["claude_known"]:
                cost = "no session logs, so no cost"
            elif t["copilot_usd"] is not None:
                cost = "$%.2f (Claude $%.2f + Copilot ~$%.2f)" % (t["cost"], t["claude"]["cost"], t["copilot_usd"])
            else:
                cost = "Claude $%.2f (Copilot not priced)" % t["claude"]["cost"]
            lines.append(f"  {r['name']}: {cost}, {t['copilot_requests']} Copilot review(s), clean at {clean}")
    if data["speed_flags"]:
        lines.append("Non-standard speed/tier seen (priced at standard rates): " + ", ".join(data["speed_flags"]))
    if data["unpriced"]:
        lines.append("Unpriced models (used fallback rates): " + ", ".join(data["unpriced"]))
    lines.append(f"Dashboard: {out}")
    return "\n".join(lines)


def default_ab_root():
    return os.environ.get("AB_RUNS_DIR") or os.path.expanduser("~/experiments/runs")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.path.expanduser("~/.claude/projects"))
    ap.add_argument("--days", type=int, default=30, help="only sessions active in the last N days (0 = all)")
    ap.add_argument("--project", default="", help="substring filter on project dir / cwd")
    ap.add_argument("--ab-root", default=default_ab_root(),
                    help="folder of A/B runs (<run>.reviews/steps.csv, <run>.session); default $AB_RUNS_DIR or ~/experiments/runs; shows an A/B tab when it has any")
    ap.add_argument("--no-ab-sessions", action="store_true", help="do not count the A/B runs' sessions in the other tabs (the A/B tab still shows them)")
    ap.add_argument("--out", default=os.path.expanduser("~/.claude/cost-dashboard.html"))
    args = ap.parse_args()

    if not log_files(args.root):
        print(f"No session logs found under {args.root}")
        sys.exit(1)

    data = collect(args.root, args.days, args.project, ab_root=args.ab_root, ab_sessions=not args.no_ab_sessions)
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(render(data))
    print(summary(data, out))


if __name__ == "__main__":
    main()
