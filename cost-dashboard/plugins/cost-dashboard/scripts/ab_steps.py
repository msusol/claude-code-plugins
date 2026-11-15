"""A/B experiment steps for the cost dashboard.

auto-mode's ab-docker scripts write two things per run, next to the run folder (default ~/experiments/runs):

    <run>.reviews/steps.csv   start,end,type,round,model,commit,detail   one row per step
    <run>.session/            the Claude Code session logs of every container the run used

type is arm (the first interactive session), resume, fix (a headless fix session) or review (a Copilot review round).
Times are UTC. detail is ;-separated key=value pairs plus bare words; a review row carries pr, findings, status,
premium_requests and effort.

collect_ab() prices every Claude call in <run>.session with the dashboard's own rate table (so it matches the other tabs),
assigns each call to the step whose time window it falls in, and adds up the Copilot side as a request count. Copilot has
no per-review price in any API, so dollars appear only if pricing.json sets copilot_usd_per_request.
"""
import csv
import glob
import os
from datetime import datetime, timedelta
from pathlib import Path

SLACK_BEFORE = 2.0     # seconds a call may be stamped before its step's recorded start
SLACK_AFTER = 5.0      # ...and after its recorded end (the host logs the end just after the container exits)
CLAUDE_TYPES = ("arm", "resume", "fix")


def _ts(s):
    try:
        return datetime.fromisoformat((s or "").strip().replace("Z", "+00:00"))
    except ValueError:
        return None


def parse_detail(text):
    """'pr=3;findings=1;headless' -> ({'pr': '3', 'findings': '1'}, ['headless'])."""
    pairs, words = {}, []
    for part in (text or "").split(";"):
        part = part.strip()
        if not part:
            continue
        if "=" in part:
            k, v = part.split("=", 1)
            pairs[k.strip()] = v.strip()
        else:
            words.append(part)
    return pairs, words


def load_steps(path):
    """The rows of a steps.csv in time order. A row with an unreadable time or no type is skipped, not fatal."""
    rows = []
    try:
        fh = open(path, newline="", encoding="utf-8", errors="replace")
    except OSError:
        return rows
    with fh:
        for r in csv.DictReader(fh):
            start, end = _ts(r.get("start")), _ts(r.get("end"))
            if not start or not end or not (r.get("type") or "").strip():
                continue
            pairs, words = parse_detail(r.get("detail"))
            try:
                rnd = int(r.get("round") or 0)
            except ValueError:
                rnd = 0
            rows.append({"type": r["type"].strip(), "round": rnd, "model": (r.get("model") or "").strip(),
                         "commit": (r.get("commit") or "").strip(), "start": start, "end": end,
                         "pairs": pairs, "words": words})
    rows.sort(key=lambda s: s["start"])
    return rows


def discover(runs_dir):
    """[(run name, steps.csv path)] for every run that logged steps, sorted by name."""
    out = []
    for p in sorted(glob.glob(os.path.join(runs_dir, "*.reviews", "steps.csv"))):
        out.append((Path(p).parent.name[: -len(".reviews")], p))
    return out


def newest_mtime(runs_dir):
    """Newest modification time of any steps.csv or session log under runs_dir (0.0 if none): the 'did anything change' check."""
    newest = 0.0
    if not runs_dir:
        return newest
    pats = (os.path.join(runs_dir, "*.reviews", "steps.csv"), os.path.join(runs_dir, "*.session", "**", "*.jsonl"))
    for pat in pats:
        for f in glob.glob(pat, recursive=True):
            try:
                newest = max(newest, os.stat(f).st_mtime)
            except OSError:
                pass
    return newest


def read_calls(session_dir, bd):
    """Every priced Claude call in a session folder, using build_dashboard's own parsing, de-duplication and rates."""
    sink = []
    bd.CALL_SINK = sink
    try:
        sessions = {}
        for f in bd.log_files(str(session_dir)):
            bd.process_file(f, sessions)
    finally:
        bd.CALL_SINK = None
    return sink


def _cell(bd, calls):
    cell = bd.new_cell()
    for c in calls:
        cell["cost"] += c["cost"]
        cell["calls"] += 1
        cell["in_tok"] += c["in_tok"]
        cell["out_tok"] += c["out_tok"]
        cell["in_cost"] += c["in_cost"]
        cell["out_cost"] += c["out_cost"]
    return cell


SLACK_BEFORE_TD = timedelta(seconds=SLACK_BEFORE)
SLACK_AFTER_TD = timedelta(seconds=SLACK_AFTER)


def _step_index(steps, when):
    hit = None
    for i, s in enumerate(steps):
        if s["start"] - SLACK_BEFORE_TD <= when <= s["end"] + SLACK_AFTER_TD:
            hit = i
    return hit


def _int(v, default=0):
    try:
        return int(v)
    except (TypeError, ValueError):
        return default


def collect_ab(runs_dir, bd, usd_per_request=None):
    """The dashboard's A/B section: one entry per run with its steps and totals, or None when no run logged steps."""
    runs = []
    for name, csv_path in discover(runs_dir):
        steps = load_steps(csv_path)
        if not steps:
            continue
        sess_dir = Path(runs_dir) / (name + ".session")
        have_logs = sess_dir.is_dir() and bool(bd.log_files(str(sess_dir)))
        calls = read_calls(sess_dir, bd) if have_logs else []
        per_step = [[] for _ in steps]
        loose = []
        for c in sorted(calls, key=lambda c: c["ts"]):
            i = _step_index(steps, c["ts"])
            (per_step[i] if i is not None else loose).append(c)

        out_steps, requests, findings, clean_round = [], 0, {}, None
        for s, cs in zip(steps, per_step):
            row = {"type": s["type"], "round": s["round"], "model": s["model"], "commit": s["commit"],
                   "start": s["start"].isoformat(), "end": s["end"].isoformat(),
                   "dur_s": int((s["end"] - s["start"]).total_seconds()),
                   "mode": s["words"][0] if s["words"] else "",
                   "exit": _int(s["pairs"].get("exit"), None) if "exit" in s["pairs"] else None,
                   "claude": bd.rounded_cell(_cell(bd, cs)), "copilot": None}
            if s["type"] == "review":
                n = _int(s["pairs"].get("premium_requests"), 1)
                requests += n
                status = s["pairs"].get("status", "")
                findings[s["round"]] = _int(s["pairs"].get("findings"))
                if status == "clean" and clean_round is None:
                    clean_round = s["round"]
                row["copilot"] = {"requests": n, "findings": _int(s["pairs"].get("findings")), "status": status,
                                  "effort": s["pairs"].get("effort", ""), "pr": s["pairs"].get("pr", "")}
            out_steps.append(row)

        claude = _cell(bd, calls)
        arm_model = next((s["model"] for s in steps if s["type"] in CLAUDE_TYPES and s["model"]), "")
        reviews = [s for s in steps if s["type"] == "review"]
        runs.append({
            "name": name, "arm_model": arm_model, "claude_known": have_logs,
            "start": steps[0]["start"].isoformat(), "end": steps[-1]["end"].isoformat(),
            "wall_s": int((steps[-1]["end"] - steps[0]["start"]).total_seconds()),
            "steps": out_steps, "unassigned": bd.rounded_cell(_cell(bd, loose)),
            "totals": {"claude": bd.rounded_cell(claude), "copilot_requests": requests,
                       "copilot_usd": round(requests * usd_per_request, 4) if usd_per_request else None,
                       "reviews": len(reviews), "fixes": sum(1 for s in steps if s["type"] == "fix"),
                       "rounds": max((s["round"] for s in reviews), default=0), "clean_round": clean_round,
                       "findings": [findings[k] for k in sorted(findings)]},
        })
    if not runs:
        return None
    return {"copilot_usd_per_request": usd_per_request, "runs": runs}
