#!/usr/bin/env python3
"""Serve the docs hub locally, rebuilding whenever a markdown file changed.

One project:

    serve_hub.py [DOCS_DIR] [--host 127.0.0.1] [--port 8765]

    Open http://HOST:PORT/<project>/.hub/index.html (the project is the folder
    that holds docs/). Pages are built in memory, nothing is written.

Many projects under one port:

    serve_hub.py --find NAME         # print NAME's docs dir, searched from here upward
    serve_hub.py --root PROJECTS_DIR [--port 8766]

    Finds every <project>/docs (up to two levels below PROJECTS_DIR) and serves
    http://HOST:PORT/<project>/.hub/index.html. http://HOST:PORT/ lists them.
    Pages are built in memory; nothing is written into the projects.

Markdown files are served as plain text. Only files inside a docs/ folder are served.
"""
import argparse
import html
import posixpath
import sys
import threading
import urllib.parse
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_hub  # noqa: E402

LAYOUT = ("adr", "plans", "specs", "process", "investigate")
LOCK = threading.Lock()
PROJECTS = {}   # name -> {"docs": Path, "seen": float, "data": dict, "json": str, "page": str}


# ---------- many projects (in memory) ----------
def discover(base, depth=2):
    """Map project name -> docs dir for every <project>/docs below base."""
    found = []

    def walk(d, level):
        docs = d / "docs"
        try:
            has_docs = docs.is_dir() and any((docs / n).is_dir() for n in LAYOUT)
        except OSError:
            has_docs = False
        if has_docs:
            found.append((d, docs))
        if level >= depth:
            return
        try:
            kids = sorted(k for k in d.iterdir() if k.is_dir() and not k.name.startswith("."))
        except OSError:
            return
        for k in kids:
            if k.name in ("node_modules", "venv", "env", "docs") or k.is_symlink():
                continue
            walk(k, level + 1)

    walk(base, 0)
    names = {}
    for proj, docs in found:
        name = proj.name if proj != base else base.name
        if name in names:
            name = proj.parent.name + "-" + name
        names[name] = docs
    return names


def find_docs(name, start):
    """Docs dir for project NAME: look under each ancestor of START, nearest first."""
    here = Path(start).resolve()
    home = Path.home().resolve()
    for base in [here, *here.parents]:
        if base != home and home not in base.parents:
            break          # never scan above the home directory
        hit = discover(base).get(name)
        if hit:
            return hit
    return None


def project_refresh(name):
    with LOCK:
        p = PROJECTS[name]
        cur = build_hub.newest_mtime(p["docs"])
        if cur != p["seen"] or p["page"] is None:
            data = build_hub.collect(p["docs"])
            p["json"], p["page"] = build_hub.render(data)
            p["data"], p["seen"] = data, cur
            print("built %s: %d plans, %d ADRs, %d investigations" % (
                name, len(data["plans"]), len(data["adrs"]), len(data["invs"])), flush=True)
        return p


def index_page():
    rows = []
    for name in sorted(PROJECTS):
        d = project_refresh(name)["data"]
        t = [r for r in d["work"] if r["kind"] == "task"]
        done = sum(1 for r in t if r["done"])
        pct = round(100 * done / len(t)) if t else 0
        rows.append(
            '<tr><td><a href="/%s/.hub/index.html">%s</a></td><td>%d%%</td><td>%d / %d</td>'
            "<td>%d</td><td>%d</td><td>%d</td></tr>" % (
                urllib.parse.quote(name), html.escape(d["project"] or name), pct, done, len(t),
                len(d["plans"]), len(d["adrs"]), len(d["invs"])))
    return """<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>Docs Hub</title>
<style>
:root { --bg:#fafafa; --fg:#141413; --mut:#6b6b66; --line:#e3e3df; --gold:#c9ad5c; --panel:#fff; }
@media (prefers-color-scheme: dark) { :root { --bg:#1d1d1b; --fg:#f0f0ec; --mut:#a4a49c; --line:#3a3a36; --panel:#262624; } }
body { margin:0; background:var(--bg); color:var(--fg); font:16px/1.5 system-ui,sans-serif; }
main { max-width:60rem; margin:0 auto; padding:2rem 1rem; }
.eyebrow { color:var(--mut); margin:0; }
h1 { margin:.25rem 0 1.5rem; text-transform:uppercase; }
h1::after { content:''; display:block; width:2.25rem; height:3px; background:var(--gold); margin-top:.75rem; }
table { width:100%; border-collapse:collapse; background:var(--panel); border:1px solid var(--line); }
th, td { text-align:left; padding:.5rem .75rem; border-bottom:1px solid var(--line); }
th { color:var(--mut); font-weight:500; }
a { color:var(--fg); text-decoration:underline; text-decoration-color:var(--gold); text-decoration-thickness:2px; text-underline-offset:3px; }
a:hover { color:var(--mut); }
</style></head><body><main>
<p class="eyebrow">Docs Hub</p><h1>Projects</h1>
<table><thead><tr><th>Project</th><th>Done</th><th>TODO items</th><th>Plans</th><th>ADRs</th><th>Investigations</th></tr></thead>
<tbody>__ROWS__</tbody></table></main></body></html>""".replace("__ROWS__", "".join(rows))


class MultiHandler(SimpleHTTPRequestHandler):
    def _send(self, body, ctype):
        raw = body.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(raw)

    def do_GET(self):
        path = urllib.parse.urlsplit(self.path).path
        parts = [urllib.parse.unquote(x) for x in path.split("/") if x]
        if not parts:
            if len(PROJECTS) == 1:
                self.send_response(302)
                self.send_header("Location", "/%s/.hub/index.html" % urllib.parse.quote(next(iter(PROJECTS))))
                self.end_headers()
                return
            return self._send(index_page(), "text/html; charset=utf-8")
        name = parts[0]
        if name not in PROJECTS:
            return self.send_error(404, "unknown project")
        if len(parts) == 1:
            self.send_response(302)
            self.send_header("Location", "/%s/.hub/index.html" % urllib.parse.quote(name))
            self.end_headers()
            return
        if parts[1] == ".hub":
            p = project_refresh(name)
            if parts[2:] == ["index.html"]:
                return self._send(p["page"], "text/html; charset=utf-8")
            if parts[2:] == ["hub.json"]:
                return self._send(p["json"], "application/json")
            return self.send_error(404)
        docs = PROJECTS[name]["docs"].resolve()
        target = (docs / posixpath.join(*parts[1:])).resolve()
        if docs != target and docs not in target.parents:
            return self.send_error(403)
        self.path = "/" + "/".join(urllib.parse.quote(x) for x in parts[1:])
        self.directory = str(docs)
        super().do_GET()

    do_HEAD = do_GET

    def guess_type(self, path):
        if str(path).endswith(".md"):
            return "text/plain; charset=utf-8"
        return super().guess_type(path)

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, fmt, *args):
        pass


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("docs", nargs="?", default="docs")
    ap.add_argument("--root", help="serve every <project>/docs found under this folder")
    ap.add_argument("--find", metavar="NAME", help="print the docs dir of project NAME (searched from the current directory upward) and exit")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8765)
    args = ap.parse_args()
    if args.find:
        hit = find_docs(args.find, Path.cwd())
        if not hit:
            sys.exit("no project named %r with a docs/ folder found above %s" % (args.find, Path.cwd()))
        print(hit)
        return
    if args.root:
        base = Path(args.root).resolve()
        if not base.is_dir():
            sys.exit("not a directory: %s" % base)
        for name, docs in discover(base).items():
            PROJECTS[name] = {"docs": docs, "seen": -1.0, "data": None, "json": "", "page": None}
        if not PROJECTS:
            sys.exit("no <project>/docs folders with adr/, plans/, specs/, process/ or investigate/ under %s" % base)
        server = ThreadingHTTPServer((args.host, args.port), MultiHandler)
        print("serving %d projects from %s at http://%s:%d/" % (len(PROJECTS), base, args.host, args.port), flush=True)
        for name in sorted(PROJECTS):
            print("  /%s/  <- %s" % (name, PROJECTS[name]["docs"]), flush=True)
    else:
        root = Path(args.docs).resolve()
        if not root.is_dir():
            sys.exit("not a directory: %s" % root)
        if root.name != "docs" and (root / "docs").is_dir():
            root = root / "docs"
        name = root.parent.name if root.name == "docs" else root.name
        PROJECTS[name] = {"docs": root, "seen": -1.0, "data": None, "json": "", "page": None}
        server = ThreadingHTTPServer((args.host, args.port), MultiHandler)
        print("serving %s at http://%s:%d/%s/.hub/index.html" % (root, args.host, args.port, urllib.parse.quote(name)), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
