"""Tests for the dashboard server: what it serves, when it rebuilds, and what it refuses.

Run from the plugin repo root:  python3 -m unittest discover -s cost-dashboard/tests -v

Each test starts a real server on a free localhost port in a thread, over synthetic logs in a temporary directory.
"""
import http.client
import json
import os
import subprocess
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from unittest import mock

PLUGIN = Path(__file__).resolve().parents[1] / "plugins" / "cost-dashboard"
sys.path.insert(0, str(PLUGIN / "scripts"))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_dashboard as b  # noqa: E402
import serve_dashboard as sd  # noqa: E402
from test_build_dashboard import (FIXED_PRICING, OPUS_COST, OPUS_USAGE, HAIKU_USAGE, assistant, user,  # noqa: E402
                                  write_log)


class ServerCase(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = self._tmp.name
        patcher = mock.patch.object(b, "PRICING", FIXED_PRICING)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.log = write_log(self.root, "-p/s1.jsonl", [user(0, "go"), assistant(1, "claude-opus-4-9", OPUS_USAGE, "m1", "r1")])
        os.utime(self.log, (1_000, 1_000))
        self.server = sd.make_server(self.root, days=0, port=0)
        self.port = self.server.server_address[1]
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.addCleanup(self.stop)

    def stop(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(5)

    def get(self, path="/", method="GET", host=None, body=None):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=10)
        headers = {"Host": host} if host else {}
        conn.request(method, path, body=body, headers=headers)
        resp = conn.getresponse()
        data = resp.read()
        conn.close()
        return resp, data

    def total(self):
        resp, data = self.get("/data.json")
        self.assertEqual(resp.status, 200)
        return sum(s["cost"] for s in json.loads(data)["sessions"])


class Serving(ServerCase):
    def test_page_is_html(self):
        resp, data = self.get("/")
        self.assertEqual(resp.status, 200)
        self.assertTrue(resp.getheader("Content-Type").startswith("text/html"))
        self.assertIn(b"<html", data[:300].lower())
        self.assertNotIn(b"/*__DATA__*/", data)

    def test_data_json_is_valid_and_matches_the_logs(self):
        resp, data = self.get("/data.json")
        self.assertEqual(resp.status, 200)
        self.assertEqual(resp.getheader("Content-Type"), "application/json")
        payload = json.loads(data)
        self.assertEqual(sorted(payload), ["days", "generated", "rates", "rates_source", "rates_verified", "sessions", "speed_flags", "unpriced"])
        self.assertAlmostEqual(payload["sessions"][0]["cost"], OPUS_COST, places=4)

    def test_page_and_json_agree(self):
        _, page = self.get("/")
        _, data = self.get("/data.json")
        cost = json.loads(data)["sessions"][0]["cost"]
        self.assertIn(('"cost": %s' % cost).encode(), page)

    def test_query_string_is_ignored(self):
        resp, _ = self.get("/?x=1")
        self.assertEqual(resp.status, 200)

    def test_head_returns_headers_and_no_body(self):
        resp, data = self.get("/", method="HEAD")
        self.assertEqual(resp.status, 200)
        self.assertEqual(data, b"")
        self.assertGreater(int(resp.getheader("Content-Length")), 0)

    def test_every_response_is_no_store(self):
        for path in ("/", "/data.json", "/nope"):
            resp, _ = self.get(path)
            self.assertEqual(resp.getheader("Cache-Control"), "no-store", path)


class Rebuilding(ServerCase):
    def test_no_change_means_no_second_build(self):
        self.get("/")
        self.get("/data.json")
        self.get("/")
        self.assertEqual(self.server.state.builds, 1)

    def test_a_changed_log_is_picked_up(self):
        before = self.total()
        with open(self.log, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(assistant(2, "claude-opus-4-9", OPUS_USAGE, "m2", "r2")) + "\n")
        os.utime(self.log, (2_000, 2_000))
        self.assertAlmostEqual(self.total(), before + OPUS_COST, places=4)
        self.assertEqual(self.server.state.builds, 2)

    def test_a_new_log_file_is_picked_up(self):
        before = self.total()
        other = write_log(self.root, "-q/s2.jsonl", [user(0, "other"), assistant(1, "claude-haiku-4-5", HAIKU_USAGE, "h1", "hr1", sid="s2")])
        os.utime(other, (3_000, 3_000))
        self.assertAlmostEqual(self.total(), before + 6.0, places=4)

    def test_concurrent_requests_after_a_change_build_once(self):
        self.get("/")
        os.utime(self.log, (5_000, 5_000))
        results = []
        threads = [threading.Thread(target=lambda: results.append(self.get("/data.json")[0].status)) for _ in range(8)]
        for t in threads:
            t.start()
        for t in threads:
            t.join(10)
        self.assertEqual(results, [200] * 8)
        self.assertEqual(self.server.state.builds, 2)

    def test_changed_plugin_files_reload_the_generator(self):
        self.get("/")
        with mock.patch.object(sd, "code_mtime", return_value=sd.code_mtime() + 100), \
                mock.patch.object(sd.importlib, "reload") as reload_mock:
            self.get("/")
        reload_mock.assert_called_once_with(sd.build_dashboard)
        self.assertEqual(self.server.state.builds, 2)

    def test_a_failed_build_returns_500_and_the_server_keeps_serving(self):
        with mock.patch.object(b, "collect", side_effect=RuntimeError("boom")):
            resp, data = self.get("/data.json")
        self.assertEqual(resp.status, 500)
        self.assertIn(b"boom", data)
        resp, _ = self.get("/data.json")
        self.assertEqual(resp.status, 200)


class Refusing(ServerCase):
    def test_nothing_but_the_two_paths_is_served(self):
        for path in ("/../etc/passwd", "/%2e%2e/etc/passwd", "/..%2f..%2fetc/passwd", "/index.html", "/data.json/",
                     "/-p/s1.jsonl", "/" + Path(self.log).name, "//etc/passwd", "/.hub/index.html", "/static/x"):
            resp, _ = self.get(path)
            self.assertEqual(resp.status, 404, path)

    def test_log_content_is_never_served_as_a_file(self):
        _, data = self.get(self.log.as_posix())
        self.assertNotIn(b"claude-opus-4-9", data)

    def test_other_methods_are_refused(self):
        for method in ("POST", "PUT", "DELETE"):
            resp, _ = self.get("/", method=method, body="x")
            self.assertIn(resp.status, (405, 501), method)

    def test_foreign_host_header_is_forbidden(self):
        for host in ("evil.example.com", "evil.example.com:8766", "127.0.0.1.evil.com", "10.0.0.5"):
            resp, _ = self.get("/data.json", host=host)
            self.assertEqual(resp.status, 403, host)
        self.assertEqual(self.server.state.builds, 0, "a refused request must not trigger a build")

    def test_loopback_host_names_are_allowed(self):
        for host in ("127.0.0.1:%d" % self.port, "localhost:%d" % self.port, "localhost", "[::1]:%d" % self.port):
            resp, _ = self.get("/data.json", host=host)
            self.assertEqual(resp.status, 200, host)


class Binding(unittest.TestCase):
    def test_default_bind_address_is_loopback(self):
        with tempfile.TemporaryDirectory() as tmp:
            write_log(tmp, "-p/s1.jsonl", [user(0, "go"), assistant(1, "claude-opus-4-9", OPUS_USAGE)])
            server = sd.make_server(tmp, port=0)
            try:
                self.assertEqual(server.server_address[0], "127.0.0.1")
            finally:
                server.server_close()

    def test_cli_defaults_are_loopback_port_8766_and_30_days(self):
        fake = mock.Mock()
        fake.server_address = ("127.0.0.1", 8766)
        fake.serve_forever.side_effect = KeyboardInterrupt
        with tempfile.TemporaryDirectory() as tmp:
            write_log(tmp, "-p/s1.jsonl", [user(0, "go"), assistant(1, "claude-opus-4-9", OPUS_USAGE)])
            with mock.patch.object(sd, "make_server", return_value=fake) as made, \
                    mock.patch.object(sys, "argv", ["serve_dashboard.py", "--root", tmp]):
                sd.main()
        self.assertEqual(made.call_args.args, (tmp, 30, "", "127.0.0.1", 8766))
        fake.server_close.assert_called_once()

    def test_host_header_rules(self):
        self.assertTrue(sd.host_allowed("localhost:8766", "127.0.0.1"))
        self.assertTrue(sd.host_allowed("[::1]:8766", "127.0.0.1"))
        self.assertFalse(sd.host_allowed("", "127.0.0.1"))
        self.assertFalse(sd.host_allowed(None, "127.0.0.1"))
        self.assertFalse(sd.host_allowed("evil.com", "127.0.0.1"))
        self.assertTrue(sd.host_allowed("100.64.0.5:8766", "100.64.0.5"), "an explicit --host is allowed as given")
        self.assertFalse(sd.host_allowed("localhost", "100.64.0.5"), "a non-loopback bind does not also open loopback names")


class CommandLine(unittest.TestCase):
    def run_cli(self, *args, timeout=30):
        return subprocess.run([sys.executable, "-I", str(PLUGIN / "scripts" / "serve_dashboard.py"), *args],
                              capture_output=True, text=True, timeout=timeout)

    def test_no_logs_exits_with_a_message(self):
        with tempfile.TemporaryDirectory() as tmp:
            r = self.run_cli("--root", tmp)
            self.assertNotEqual(r.returncode, 0)
            self.assertIn("No session logs found", r.stderr)

    def test_port_in_use_exits_with_a_clear_message(self):
        with tempfile.TemporaryDirectory() as tmp:
            write_log(tmp, "-p/s1.jsonl", [user(0, "go"), assistant(1, "claude-opus-4-9", OPUS_USAGE)])
            busy = sd.make_server(tmp, port=0)
            try:
                port = busy.server_address[1]
                r = self.run_cli("--root", tmp, "--port", str(port))
            finally:
                busy.server_close()
            self.assertNotEqual(r.returncode, 0)
            self.assertIn("cannot listen on", r.stderr)
            self.assertIn("--port", r.stderr)
            self.assertNotIn("Traceback", r.stderr)

    def test_starts_prints_the_url_and_stops_on_interrupt(self):
        with tempfile.TemporaryDirectory() as tmp:
            write_log(tmp, "-p/s1.jsonl", [user(0, "go"), assistant(1, "claude-opus-4-9", OPUS_USAGE)])
            probe = sd.make_server(tmp, port=0)
            port = probe.server_address[1]
            probe.server_close()
            before = sorted(os.listdir(tmp))
            proc = subprocess.Popen([sys.executable, "-I", str(PLUGIN / "scripts" / "serve_dashboard.py"),
                                     "--root", tmp, "--days", "0", "--port", str(port)],
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            try:
                line = proc.stdout.readline()
                self.assertIn("http://127.0.0.1:%d/" % port, line)
                conn = http.client.HTTPConnection("127.0.0.1", port, timeout=10)
                conn.request("GET", "/data.json")
                self.assertEqual(conn.getresponse().status, 200)
                conn.close()
            finally:
                proc.send_signal(2)           # SIGINT, like Ctrl-C
                out, err = proc.communicate(timeout=15)
            self.assertEqual(proc.returncode, 0, err)
            self.assertNotIn("Traceback", err)
            self.assertEqual(sorted(os.listdir(tmp)), before, "serving must not write into the logs folder")


if __name__ == "__main__":
    unittest.main()
