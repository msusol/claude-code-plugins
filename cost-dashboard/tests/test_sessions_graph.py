"""The Sessions tab's Table / Graph toggle: cost per calendar day, stacked by model.

Run from the plugin repo root:  python3 -m unittest discover -s cost-dashboard/tests -v

The graph is drawn from each session's per-day model nest (`daily_me`), over every session the search box lets through (not only the page the
table shows). These tests run the page's own script under node with the stub DOM in dom_stub.js, like test_build_dashboard.py.
"""
import json
import re
import sys
import unittest
from datetime import date, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_build_dashboard import OPUS_USAGE, Base, assistant, b, run_page, user, write_log  # noqa: E402

DAY = 24 * 60     # minutes
TIP = re.compile(r'data-tip="([^"]+)"')


class SessionsGraph(Base):
    def setUp(self):
        super().setUp()
        # three days ago: one opus session; yesterday: a sonnet session and a second opus session (so that day has two models stacked).
        # Nothing happens two days ago, so that day is a gap in the range.
        write_log(self.root, "-p/a.jsonl", [user(-3 * DAY, "old opus work", sessionId="a"),
                                            assistant(-3 * DAY + 1, "claude-opus-4-9", OPUS_USAGE, "ma", "ra", sid="a", per_turn="high")])
        write_log(self.root, "-p/b.jsonl", [user(-1 * DAY, "sonnet work", sessionId="b"),
                                            assistant(-1 * DAY + 1, "claude-sonnet-5-5", OPUS_USAGE, "mb", "rb", sid="b", per_turn="low")])
        write_log(self.root, "-p/c.jsonl", [user(-1 * DAY + 5, "more opus work", sessionId="c"),
                                            assistant(-1 * DAY + 6, "claude-opus-4-9", OPUS_USAGE, "mc", "rc", sid="c", per_turn="high")])
        self.data = self.build()
        self.html = b.render(self.data)

    def page(self, actions=None, search=""):
        return run_page(self, self.html, actions, search=search)

    def tips(self, out):
        return [t for t in TIP.findall(out["sess-daily"])]

    def test_the_table_is_the_default_view_and_the_graph_is_hidden(self):
        out = self.page()
        self.assertTrue(out.get("sess-graph-wrap:hidden"))
        self.assertNotIn("sess-table-wrap:hidden", out)

    def test_the_graph_button_swaps_the_two_views_and_back(self):
        out = self.page([{"sessView": "graph"}])
        self.assertTrue(out.get("sess-table-wrap:hidden"))
        self.assertNotIn("sess-graph-wrap:hidden", out)
        back = self.page([{"sessView": "graph"}, {"sessView": "table"}])
        self.assertTrue(back.get("sess-graph-wrap:hidden"))
        self.assertNotIn("sess-table-wrap:hidden", back)

    def test_one_bar_segment_per_day_and_model_and_the_dollars_add_up_to_the_total(self):
        out = self.page([{"sessView": "graph"}])
        days = {}
        for s in self.data["sessions"]:
            for d, nest in s["daily_me"].items():
                for m, efforts in nest.items():
                    days.setdefault(d, set()).add(m)
        expected = sum(len(models) for models in days.values())
        self.assertEqual(out["sess-daily"].count("<rect"), expected, "one rect per day and model that has cost")
        total = sum(s["cost"] for s in self.data["sessions"])
        shown = sum(float(m.group(1).replace(",", "")) for t in self.tips(out) for m in [re.search(r": \$([\d,]+\.\d{2}) \(day total", t)])
        self.assertAlmostEqual(shown, total, places=1, msg="the segments add up to what the sessions cost")
        self.assertIn(f"${total:,.2f}", out["sess-graph-note"], "the note states the same total")

    def test_a_quiet_day_keeps_its_slot_in_the_range(self):
        out = self.page([{"sessView": "graph"}])
        keys = sorted({d for s in self.data["sessions"] for d in s["daily_me"]})
        first, last = date.fromisoformat(keys[0]), date.fromisoformat(keys[-1])
        gap = first + timedelta(days=1)
        self.assertEqual((last - first).days, 2, "three days ago to yesterday spans three calendar days")
        self.assertNotIn(gap.isoformat(), keys, "nothing ran on the middle day")
        self.assertIn(f">{gap.isoformat()[5:]}<", out["sess-daily"], "the empty day still has its label on the axis")
        self.assertIn("3 days", out["sess-graph-note"])

    def test_the_legend_names_each_model_with_its_total(self):
        out = self.page([{"sessView": "graph"}])
        text = re.sub(r"<[^>]+>", " ", out["sess-legend"])
        self.assertEqual(out["sess-legend"].count("cd-sw"), 2)
        self.assertRegex(text, r"opus-4-9 · \$\d")
        self.assertRegex(text, r"sonnet-5-5 · \$\d")

    def test_the_graph_follows_the_search_over_all_sessions(self):
        out = self.page([{"sessView": "graph"}, {"search": "sonnet"}])
        tips = self.tips(out)
        self.assertTrue(tips)
        self.assertTrue(all("sonnet-5-5" in t for t in tips), tips)
        self.assertEqual(out["sess-legend"].count("cd-sw"), 1)
        self.assertIn("1 session ", out["sess-graph-note"])

    def test_a_search_with_no_match_says_so_and_draws_nothing(self):
        out = self.page([{"sessView": "graph"}, {"search": "zzzz-no-such-session"}])
        self.assertEqual(out["sess-graph-note"], "No sessions match.")
        self.assertEqual(out.get("sess-daily", ""), "")
        self.assertEqual(out["sess-legend"], "")

    def test_the_view_is_kept_in_the_address_and_read_back(self):
        out = self.page([{"sessView": "graph"}])
        self.assertIn("view=graph", json.loads(out["__urls"])[-1])
        back = self.page([{"sessView": "graph"}, {"sessView": "table"}])
        self.assertNotIn("view=", json.loads(back["__urls"])[-1], "the table is the default, so the address does not carry it")
        opened = self.page(search="?view=graph")
        self.assertTrue(opened.get("sess-table-wrap:hidden"), "an address with view=graph opens on the graph")

    def test_the_toggle_buttons_are_in_the_page_with_their_state(self):
        self.assertIn('id="sess-view-table" data-view="table" aria-pressed="true"', self.html)
        self.assertIn('id="sess-view-graph" data-view="graph" aria-pressed="false"', self.html)


if __name__ == "__main__":
    unittest.main()
