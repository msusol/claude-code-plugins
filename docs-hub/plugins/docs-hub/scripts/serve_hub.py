#!/usr/bin/env python3
"""Serve docs/ locally and rebuild the hub whenever a markdown file changed.

    serve_hub.py [DOCS_DIR] [--host 127.0.0.1] [--port 8765]

Open http://HOST:PORT/ . Markdown files are served as plain text.
"""
import argparse
import functools
import sys
import threading
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_hub  # noqa: E402

LOCK = threading.Lock()
STATE = {"seen": -1.0}


def refresh(root):
    with LOCK:
        cur = build_hub.newest_mtime(root)
        if cur != STATE["seen"] or not (Path(root) / ".hub" / "index.html").exists():
            STATE["seen"] = cur
            data, path = build_hub.build(root)
            print(build_hub.summary(data, path), flush=True)


class Handler(SimpleHTTPRequestHandler):
    root = "docs"

    def do_GET(self):
        if self.path in ("", "/"):
            self.send_response(302)
            self.send_header("Location", "/.hub/index.html")
            self.end_headers()
            return
        if self.path.startswith("/.hub/"):
            refresh(self.root)
        super().do_GET()

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
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8765)
    args = ap.parse_args()
    root = Path(args.docs).resolve()
    if not root.is_dir():
        sys.exit("not a directory: %s" % root)
    Handler.root = str(root)
    refresh(root)
    handler = functools.partial(Handler, directory=str(root))
    server = ThreadingHTTPServer((args.host, args.port), handler)
    print("serving %s at http://%s:%d/" % (root, args.host, args.port), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
