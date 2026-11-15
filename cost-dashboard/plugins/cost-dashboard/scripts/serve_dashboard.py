#!/usr/bin/env python3
"""Serve the cost dashboard locally, rebuilding whenever a session log changed.

    serve_dashboard.py [--root ~/.claude/projects] [--days 30] [--project SUBSTR] [--ab-root DIR]
                       [--host 127.0.0.1] [--port 8780]

    Open http://HOST:PORT/ for the page and http://HOST:PORT/data.json for the data
    behind it. The page is built in memory; nothing is written to disk.

Only those two paths are served, so no file on disk can be reached through the server.
The data holds prompts, project paths and spend, so it binds to localhost by default and
refuses requests whose Host header is not the address it was started on (a web page
cannot reach it through DNS rebinding). For another machine use an SSH tunnel.
"""
import argparse
import importlib
import json
import sys
import threading
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_dashboard  # noqa: E402

LOOPBACK_NAMES = {"localhost", "127.0.0.1", "::1"}


def code_files():
    """The plugin files whose change must reach a running server: the generator, the A/B reader, the page template and the rates."""
    scripts = Path(build_dashboard.__file__).parent
    return (Path(build_dashboard.__file__), scripts / "ab_steps.py", build_dashboard.PLUGIN_ROOT / "scripts" / "template.html",
            build_dashboard.PLUGIN_ROOT / "pricing.json")


def code_mtime():
    """When the generator, page template or rates last changed: a reload must pick up a new plugin version without restarting."""
    newest = 0.0
    for f in code_files():
        try:
            newest = max(newest, f.stat().st_mtime)
        except OSError:
            pass
    return newest


class State:
    """What the handlers share: the settings, the last build, and the lock around rebuilding."""

    def __init__(self, root, days, project, ab_root=None, ab_sessions=True):
        self.root, self.days, self.project, self.ab_root, self.ab_sessions = root, days, project, ab_root, ab_sessions
        self.lock = threading.Lock()
        self.seen = None          # (newest log mtime, code mtime) of the last build
        self.code_seen = None
        self.page = None
        self.json = None
        self.builds = 0           # how many times collect() ran: the tests watch this

    def _ab_mtime(self):
        if not self.ab_root:
            return 0.0
        import ab_steps
        return ab_steps.newest_mtime(self.ab_root)

    def refresh(self):
        """Return (page, json), rebuilding first when a log or the plugin files changed. Concurrent callers build once."""
        with self.lock:
            code = code_mtime()
            if self.code_seen is not None and code != self.code_seen:
                importlib.reload(build_dashboard)    # a changed script, template or rate table applies on the next load
                if "ab_steps" in sys.modules:        # imported lazily by collect(), so it is not reloaded with build_dashboard
                    importlib.reload(sys.modules["ab_steps"])
                print("reloaded build_dashboard (plugin files changed)", flush=True)
            self.code_seen = code
            cur = (build_dashboard.newest_mtime(self.root), self._ab_mtime(), code)
            if cur != self.seen or self.page is None:
                data = build_dashboard.collect(self.root, self.days, self.project, ab_root=self.ab_root, ab_sessions=self.ab_sessions)
                page = build_dashboard.render(data)
                self.page, self.json = page, json.dumps(data)
                self.seen = cur
                self.builds += 1
                total = sum(s["cost"] for s in data["sessions"])
                print("built: %d sessions, $%.2f" % (len(data["sessions"]), total), flush=True)
            return self.page, self.json


def host_allowed(header, bound_host):
    """True when the request's Host header names the address the server was started on (or a loopback name on a loopback bind)."""
    if not header:
        return False
    host = header.strip()
    if host.startswith("["):                       # [::1]:8780
        name = host[1:].split("]", 1)[0]
    else:
        name = host.rsplit(":", 1)[0] if host.count(":") == 1 else host
    name = name.lower()
    allowed = {bound_host.lower()}
    if bound_host in LOOPBACK_NAMES or bound_host.startswith("127."):
        allowed |= LOOPBACK_NAMES
    return name in allowed


class Handler(BaseHTTPRequestHandler):
    server_version = "cost-dashboard"
    sys_version = ""

    def _reply(self, status, body, ctype):
        raw = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(raw)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(raw)

    def do_GET(self):
        if not host_allowed(self.headers.get("Host"), self.server.bound_host):
            return self._reply(403, "forbidden host\n", "text/plain; charset=utf-8")
        path = urllib.parse.urlsplit(self.path).path
        if path not in ("/", "/data.json"):
            return self._reply(404, "not found\n", "text/plain; charset=utf-8")
        try:
            page, data = self.server.state.refresh()
        except Exception as exc:                  # keep serving: the next request retries the build
            print("build failed: %r" % (exc,), flush=True)
            return self._reply(500, "build failed: %s\n" % exc, "text/plain; charset=utf-8")
        if path == "/":
            return self._reply(200, page, "text/html; charset=utf-8")
        return self._reply(200, data, "application/json")

    do_HEAD = do_GET

    def log_message(self, fmt, *args):
        pass


def make_server(root, days=30, project="", host="127.0.0.1", port=8780, ab_root=None, ab_sessions=True):
    """Create (not start) the server. port=0 picks a free port; read it from server.server_address."""
    server = ThreadingHTTPServer((host, port), Handler)
    server.daemon_threads = True
    server.bound_host = host
    server.state = State(root, days, project, ab_root, ab_sessions)
    return server


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", default=str(Path.home() / ".claude" / "projects"))
    ap.add_argument("--days", type=int, default=30, help="only sessions active in the last N days (0 = all)")
    ap.add_argument("--project", default="", help="substring filter on project dir / cwd")
    ap.add_argument("--ab-root", default=build_dashboard.default_ab_root(), help="folder of A/B runs; default $AB_RUNS_DIR or ~/experiments/runs")
    ap.add_argument("--no-ab-sessions", action="store_true", help="do not count the A/B runs' sessions in the other tabs")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8780)
    args = ap.parse_args()

    if not build_dashboard.log_files(args.root):
        sys.exit("No session logs found under %s" % args.root)
    try:
        server = make_server(args.root, args.days, args.project, args.host, args.port, args.ab_root, ab_sessions=not args.no_ab_sessions)
    except OSError as exc:
        sys.exit("cannot listen on %s:%d (%s); pick another port with --port" % (args.host, args.port, exc.strerror or exc))
    host, port = server.server_address[:2]
    shown = "[%s]" % host if ":" in host else host
    print("serving the cost dashboard at http://%s:%d/  (logs: %s, last %s days)" % (
        shown, port, args.root, args.days or "all"), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
