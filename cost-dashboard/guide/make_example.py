#!/usr/bin/env python3
"""Rebuild the walkthrough's example data: a synthetic set of Claude Code session logs, the dashboard page built from them, and the chart images.

    python3 cost-dashboard/guide/make_example.py [--tables]

Writes, next to this script:
    example-dashboard.html          the full dashboard for the sample data (open it in a browser)
    images/overview-daily.svg       Overview: cost per day
    images/effort-daily.svg         Model & effort: cost per day by model and effort
    images/context-sawtooth.svg     Context: context carried per call, with a compaction

The sample is invented (projects `acme-api`, `docs-site`; made-up prompts) and seeded, so it is the same every run. Prices are the shipped
pricing.json. The images are what the page draws: they are taken from the page's own script run under node, with the page's colours filled in.
Needs node (only for the images). With --tables it also prints the page's tables as text, which is how the numbers in GUIDE.md were checked.
"""
import json
import random
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
PLUGIN = HERE.parent / "plugins" / "cost-dashboard"
sys.path.insert(0, str(PLUGIN / "scripts"))
import build_dashboard as b  # noqa: E402

ANCHOR = datetime(2026, 11, 2, 9, 0, tzinfo=timezone.utc)
PROMPTS = ["Add retry with backoff to the API client", "Why is the nightly sync test flaky?", "Split the settings module into two files",
           "Write the migration for the orders table", "Explain how the cache layer invalidates entries", "Rename the config keys and update the docs",
           "Find the slow query in the report endpoint", "Draft the release notes for 2.4", "Tidy the CI workflow and pin the runners",
           "Add pagination to the list endpoint", "Check the error handling in the upload path", "Summarise what changed in the last three commits"]


def iso(dt):
    return dt.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


class Session:
    """Builds one session log. Each call re-reads the whole context from the cache and writes only what is new, as the real API does."""

    def __init__(self, rng, root, name, cwd, start, model):
        self.rng, self.root, self.name, self.cwd, self.model = rng, Path(root), name, cwd, model
        self.t = start
        self.recs = []
        self.ctx = 0
        self.n = 0
        self.compactions = 0

    def stamp(self, seconds):
        self.t += timedelta(seconds=seconds)
        return iso(self.t)

    def prompt(self, text):
        self.recs.append({"type": "user", "sessionId": self.name, "timestamp": self.stamp(self.rng.randint(30, 600)), "cwd": self.cwd,
                          "message": {"content": text}})

    def usage(self, read, write, out):
        return {"input_tokens": 2, "output_tokens": out, "cache_read_input_tokens": read, "cache_creation_input_tokens": write,
                "cache_creation": {"ephemeral_5m_input_tokens": 0, "ephemeral_1h_input_tokens": write},
                "service_tier": "standard", "speed": "standard", "inference_geo": "global"}

    def call(self, effort, grow, out=None, side=False, read=None, write=None, gap=None):
        self.n += 1
        out = out if out is not None else int(self.rng.lognormvariate(6.4, 0.7))
        read = self.ctx if read is None else read
        write = grow if write is None else write
        self.ctx = read + write
        rec = {"type": "assistant", "sessionId": self.name, "timestamp": self.stamp(gap if gap is not None else self.rng.randint(4, 40)),
               "cwd": self.cwd, "isSidechain": side, "effort": effort, "perTurnEffort": effort, "requestId": "r%s%d" % (self.name, self.n),
               "message": {"id": "m%s%d" % (self.name, self.n), "model": self.model, "usage": self.usage(read, write, out)}}
        self.recs.append(rec)
        return rec

    def work(self, tasks, calls, effort_for, grow_mean, limit=None):
        """`tasks` prompts, about `calls` model calls each. When the context passes `limit` Claude Code compacts it: a summary of about 25k
        tokens replaces the history, and the next call has to write most of that summary to the cache again."""
        self.call(effort_for(0), 28_000, out=1200)                       # the system prompt and tools
        for k in range(tasks):
            self.prompt(self.rng.choice(PROMPTS))
            for _ in range(max(2, int(self.rng.gauss(calls, calls / 4)))):
                grow = min(int(self.rng.lognormvariate(grow_mean, 1.0)), 90_000)
                self.call(effort_for(k), grow)
                if limit and self.ctx > limit:
                    self.compactions += 1
                    self.recs.append({"type": "system", "subtype": "compact_boundary", "sessionId": self.name, "timestamp": self.stamp(80),
                                      "compactMetadata": {"trigger": "auto", "preTokens": self.ctx, "postTokens": 25_000}})
                    self.ctx = 0
                    self.call(effort_for(k), 0, read=28_000, write=85_000, out=900, gap=self.rng.randint(3600 * 3, 3600 * 9))

    def save(self):
        p = self.root / "-home-user-{}".format(self.cwd.rsplit("/", 1)[-1]) / (self.name + ".jsonl")
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text("\n".join(json.dumps(r) for r in self.recs) + "\n", encoding="utf-8")


def build_logs(root):
    rng = random.Random(7)
    day = lambda n, h=0: ANCHOR + timedelta(days=n, hours=h)
    fixed = lambda e: (lambda k: e)
    sessions = []

    s = Session(rng, root, "api-refactor", "/home/user/acme-api", day(0), "claude-sonnet-5-5")     # a long one: grows past 480k and compacts
    s.work(34, 26, fixed("medium"), 7.0, limit=480_000); sessions.append(s)

    s = Session(rng, root, "api-opus-review", "/home/user/acme-api", day(1, 3), "claude-opus-5-5")
    s.work(10, 9, fixed("medium"), 7.2); sessions.append(s)

    s = Session(rng, root, "api-opus-hard-bug", "/home/user/acme-api", day(3, 1), "claude-opus-5-5")
    s.work(6, 11, fixed("high"), 7.4); sessions.append(s)

    s = Session(rng, root, "docs-quick", "/home/user/docs-site", day(2, 5), "claude-sonnet-5-5")
    s.work(14, 5, fixed("low"), 6.4); sessions.append(s)

    s = Session(rng, root, "docs-rewrite", "/home/user/docs-site", day(4, 2), "claude-sonnet-5-5")     # effort raised half way through
    s.work(9, 9, lambda k: "medium" if k < 4 else "high", 6.9)
    sub = Session(rng, root, "docs-rewrite", "/home/user/docs-site", day(4, 3), "claude-haiku-5-5")
    sub.work(1, 5, fixed("medium"), 6.2)
    for r in sub.recs:
        r["isSidechain"] = True
    sessions.append(s)

    s = Session(rng, root, "api-small", "/home/user/acme-api", day(5, 4), "claude-sonnet-5-5")
    s.work(8, 6, fixed("medium"), 6.8); sessions.append(s)

    s = Session(rng, root, "infra-opus", "/home/user/infra", day(6, 2), "claude-opus-5-5")
    s.work(7, 8, fixed("medium"), 7.1); sessions.append(s)

    for s in sessions:
        s.save()
    p = Path(root) / "-home-user-docs-site" / "docs-rewrite" / "subagents" / "agent-1.jsonl"      # the haiku calls live in the subagent file
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text("\n".join(json.dumps(r) for r in sub.recs if r["type"] == "assistant") + "\n", encoding="utf-8")
    return sessions


LIGHT = {"var(--gold)": "#c9ad5c", "var(--bar)": "#c9ad5c", "var(--mut)": "#616161", "var(--line)": "#e7e7e7", "var(--fg)": "#111111", "var(--bar2)": "#616161"}


def hsl_to_hex(m):
    """The page writes colours as hsl(42 55% 64%); older SVG viewers only know hex."""
    import colorsys
    hue, sat, light = int(m.group(1)) / 360, int(m.group(2)) / 100, int(m.group(3)) / 100
    r, g, bl = colorsys.hls_to_rgb(hue, light, sat)
    return "#%02x%02x%02x" % (round(r * 255), round(g * 255), round(bl * 255))


def standalone_svg(inner, w, h):
    for k, v in LIGHT.items():
        inner = inner.replace(k, v)
    inner = re.sub(r"hsl\((\d+) (\d+)% (\d+)%\)", hsl_to_hex, inner)
    inner = re.sub(r' data-tip="[^"]*"', "", inner)
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" width="%d" height="%d" font-family="system-ui, sans-serif">'
            '<rect width="100%%" height="100%%" fill="#ffffff"/>%s</svg>\n' % (w, h, w, h, inner))


def run_page(html, actions=None):
    node = shutil.which("node")
    if not node:
        sys.exit("node is needed to draw the images")
    script = re.search(r"<script>(.*)</script>", html, re.S).group(1)
    with tempfile.TemporaryDirectory() as tmp:
        (Path(tmp) / "page.js").write_text(script, encoding="utf-8")
        r = subprocess.run([node, str(HERE.parent / "tests" / "dom_stub.js"), str(Path(tmp) / "page.js"), json.dumps(actions or [])],
                           capture_output=True, text=True, timeout=60)
    if r.returncode:
        sys.exit(r.stderr)
    return json.loads(r.stdout)


def text(html_fragment):
    return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", html_fragment)).strip()


def main():
    with tempfile.TemporaryDirectory() as tmp:
        build_logs(tmp)
        data = b.collect(tmp, days=0, now=datetime(2026, 11, 10, 12, 0, 0))
    page = b.render(data)
    (HERE / "example-dashboard.html").write_text(page, encoding="utf-8")
    out = run_page(page)
    (HERE / "images").mkdir(exist_ok=True)
    pick = max(data["sessions"], key=lambda s: s["ctx"]["calls"])          # the long session
    out = run_page(page, [])                                                 # the page draws the costliest session by default
    ctx_top = max((s for s in data["sessions"] if s["ctx"]["calls"]), key=lambda s: s["cost"])
    if ctx_top["id"] != pick["id"]:                                          # draw the long one: the page has no action for the selector, so redraw
        page2 = page.replace("let ctxPick = ctxSes.length ? ctxSes[0].id : null;", "let ctxPick = %s;" % json.dumps(pick["id"]))
        out = run_page(page2)
    (HERE / "images" / "overview-daily.svg").write_text(standalone_svg(out["daily"], 600, 180))
    (HERE / "images" / "effort-daily.svg").write_text(standalone_svg(out["daily-eff"], 1100, 180))
    (HERE / "images" / "context-sawtooth.svg").write_text(standalone_svg(out["ctx-chart"], 600, 240))
    if "--tables" in sys.argv:
        for k in ("tile", "kpis", "models", "mod-eff", "matrix", "task-eff", "eff-legend", "parts-tbl", "ctx-read", "rate-tbl", "rate-note", "ctx-note", "ctx-tbl", "sess", "pager"):
            print("=== %s\n%s\n" % (k, text(out.get(k, ""))))
    total = sum(s["cost"] for s in data["sessions"])
    print("wrote example-dashboard.html and images/*.svg: %d sessions, $%.2f, long session %s with %d calls, %d compaction(s) seen"
          % (len(data["sessions"]), total, pick["id"], pick["ctx"]["calls"], pick["ctx"]["resets"]))


if __name__ == "__main__":
    main()
