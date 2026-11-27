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


class SessionsGraphRange(Base):
    """The graph's range menu: the last 1, 3, 6 or 12 months, all time, or one calendar year. Without it the x-axis would grow forever."""

    AGES = {"a": 400, "b": 200, "c": 40, "d": 1}       # days ago; 400 is last year, 200 is about 6.6 months back, 40 is within 3 months

    def setUp(self):
        super().setUp()
        for sid, age in self.AGES.items():
            write_log(self.root, f"-p/{sid}.jsonl", [user(-age * DAY, f"{sid} work", sessionId=sid),
                                                     assistant(-age * DAY + 1, "claude-opus-4-9", OPUS_USAGE, f"m{sid}", f"r{sid}", sid=sid, per_turn="high")])
        self.data = self.build()
        self.html = b.render(self.data)
        self.day_of = {}
        for sess in self.data["sessions"]:
            self.day_of[sess["title"].split()[0]] = next(iter(sess["daily_me"]))

    def page(self, actions=None, search=""):
        return run_page(self, self.html, actions, search=search)

    def days_drawn(self, out):
        return sorted({t.split(" ")[0] for t in TIP.findall(out.get("sess-daily", ""))})

    def expect(self, out, *sids):
        self.assertEqual(self.days_drawn(out), sorted(self.day_of[x] for x in sids))

    def test_the_default_is_the_last_three_months(self):
        out = self.page([{"sessView": "graph"}])
        self.expect(out, "c", "d")
        self.assertIn("last 3 months", out["sess-graph-note"])
        self.assertIn('<option value="3m" selected>', out["sess-range"])

    def test_each_range_keeps_the_days_inside_it(self):
        for rng, sids in (("1m", ("d",)), ("3m", ("c", "d")), ("6m", ("c", "d")), ("12m", ("b", "c", "d")), ("all", ("a", "b", "c", "d"))):
            with self.subTest(range=rng):
                self.expect(self.page([{"sessView": "graph"}, {"sessRange": rng}]), *sids)

    def test_a_calendar_year_shows_only_that_year(self):
        last_year = self.day_of["a"][:4]
        out = self.page([{"sessView": "graph"}, {"sessRange": last_year}])
        self.expect(out, "a")
        self.assertIn(f"({last_year})", out["sess-graph-note"])

    def test_the_menu_lists_the_ranges_then_the_years_that_have_data_newest_first(self):
        out = self.page([{"sessView": "graph"}])
        values = re.findall(r'<option value="([^"]+)"', out["sess-range"])
        years = sorted({d[:4] for d in self.day_of.values()}, reverse=True)
        self.assertEqual(values, ["1m", "3m", "6m", "12m", "all"] + years)
        self.assertGreaterEqual(len(years), 2, "the fixture spans two calendar years")

    def test_the_note_and_legend_count_only_what_is_in_the_range(self):
        out = self.page([{"sessView": "graph"}])                      # c and d
        self.assertIn("2 sessions", out["sess-graph-note"])
        wide = self.page([{"sessView": "graph"}, {"sessRange": "all"}])
        self.assertIn("4 sessions", wide["sess-graph-note"])
        total = lambda o: float(re.search(r"\$([\d,]+\.\d{2}) across", o["sess-graph-note"]).group(1).replace(",", ""))
        self.assertGreater(total(wide), total(out))

    def test_a_range_with_no_cost_says_so_and_points_to_a_longer_one(self):
        out = self.page([{"sessView": "graph"}, {"search": "a work"}])      # only the 400-day-old session matches, outside the default range
        self.assertIn("No cost in this range", out["sess-graph-note"])
        self.assertNotIn("<rect", out.get("sess-daily", ""))

    def test_the_range_is_kept_in_the_address_and_read_back(self):
        out = self.page([{"sessView": "graph"}, {"sessRange": "6m"}])
        self.assertIn("range=6m", json.loads(out["__urls"])[-1])
        back = self.page([{"sessView": "graph"}, {"sessRange": "6m"}, {"sessRange": "3m"}])
        self.assertNotIn("range=", json.loads(back["__urls"])[-1], "3 months is the default, so the address does not carry it")
        opened = self.page(search="?view=graph&range=all")
        self.expect(opened, "a", "b", "c", "d")
        junk = self.page(search="?view=graph&range=bogus")
        self.expect(junk, "c", "d")                                        # an unknown value falls back to the default


class SessionsGraphBuiltWindow(Base):
    """A page built for the last 30 days cannot show a longer range; the graph says so instead of drawing the same bars under every choice."""

    def setUp(self):
        super().setUp()
        write_log(self.root, "-p/d.jsonl", [user(-1 * DAY, "recent work", sessionId="d"),
                                            assistant(-1 * DAY + 1, "claude-opus-4-9", OPUS_USAGE, "md", "rd", sid="d", per_turn="high")])

    def note(self, days, rng):
        html = b.render(self.build(days=days))
        out = run_page(self, html, [{"sessView": "graph"}, {"sessRange": rng}])
        return out["sess-graph-note"]

    def test_a_range_longer_than_the_built_window_carries_the_hint(self):
        for rng in ("3m", "6m", "12m", "all"):
            with self.subTest(range=rng):
                text = self.note(30, rng)
                self.assertIn("built for the last 30 days", text)
                self.assertIn("--days 0", text)

    def test_a_range_inside_the_built_window_has_no_hint(self):
        self.assertNotIn("built for the last", self.note(30, "1m"), "a month is inside 30 days plus the week of tolerance")

    def test_a_page_built_for_everything_has_no_hint(self):
        for rng in ("3m", "12m", "all"):
            with self.subTest(range=rng):
                self.assertNotIn("built for the last", self.note(0, rng))

    def test_the_hint_names_the_days_the_page_was_built_for(self):
        self.assertIn("built for the last 90 days", self.note(90, "all"))
        self.assertNotIn("built for the last", self.note(90, "3m"), "3 months is within 90 days plus a week")


if __name__ == "__main__":
    unittest.main()
