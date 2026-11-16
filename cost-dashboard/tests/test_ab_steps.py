"""Tests for the A/B section: joining <run>.reviews/steps.csv to the Claude logs in <run>.session, and the A/B tab.

Run from the plugin repo root:  python3 -m unittest discover -s cost-dashboard/tests -v

Same fixed rate table and hand calculations as test_build_dashboard.py: one OPUS_USAGE call costs $0.75.
"""
import json
import re
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_build_dashboard import (FIXED_PRICING, OPUS_COST, OPUS_USAGE, PLUGIN, assistant, run_page, ts, user, write_log)  # noqa: E402

sys.path.insert(0, str(PLUGIN / "scripts"))
import ab_steps  # noqa: E402
import build_dashboard as b  # noqa: E402

HEADER = "start,end,type,round,model,commit,detail"
REVIEW1 = "pr=3;findings=2;status=findings;premium_requests=1;effort=balanced"
REVIEW2 = "pr=3;findings=0;status=clean;premium_requests=1;effort=balanced"


def steps_csv(rows):
    return HEADER + "\n" + "\n".join(",".join(str(c) for c in r) for r in rows) + "\n"


def standard_rows():
    """arm 0-10 min, review 1 10-11, fix 12-15, review 2 15-16."""
    return [(ts(0), ts(10), "arm", 0, "claude-opus-4-9", "abc1234", "interactive;exit=0"),
            (ts(10), ts(11), "review", 1, "copilot", "abc1234", REVIEW1),
            (ts(12), ts(15), "fix", 1, "claude-opus-4-9", "def5678", "headless;exit=0"),
            (ts(15), ts(16), "review", 2, "copilot", "def5678", REVIEW2)]


class AbBase(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.main = str(Path(self._tmp.name) / "projects")
        self.runs = str(Path(self._tmp.name) / "runs")
        write_log(self.main, "-p/s1.jsonl", [user(0, "hi"), assistant(1, "claude-opus-4-9", OPUS_USAGE)])
        p = mock.patch.object(b, "PRICING", FIXED_PRICING)
        p.start()
        self.addCleanup(p.stop)

    def make_run(self, name="r1", rows=None, calls=None, csv_text=None):
        d = Path(self.runs) / (name + ".reviews")
        d.mkdir(parents=True, exist_ok=True)
        (d / "steps.csv").write_text(csv_text if csv_text is not None else steps_csv(rows if rows is not None else standard_rows()))
        if calls is not None:
            write_log(Path(self.runs) / (name + ".session"), "-work/s1.jsonl", calls)

    def standard_calls(self):
        return [assistant(5, "claude-opus-4-9", OPUS_USAGE, "a1", "ra1"),      # inside the arm session
                assistant(13, "claude-opus-4-9", OPUS_USAGE, "f1", "rf1"),     # inside the fix session
                assistant(20, "claude-opus-4-9", OPUS_USAGE, "x1", "rx1")]     # after every step

    def ab(self, **kw):
        data = b.collect(self.main, days=0, ab_root=self.runs, **kw)
        return data.get("ab")

    def run0(self, **kw):
        ab = self.ab(**kw)
        self.assertIsNotNone(ab)
        return ab["runs"][0]


class Assignment(AbBase):
    def test_each_call_lands_in_the_step_whose_window_holds_it(self):
        self.make_run(calls=self.standard_calls())
        r = self.run0()
        cost = [s["claude"]["cost"] for s in r["steps"]]
        self.assertEqual([s["type"] for s in r["steps"]], ["arm", "review", "fix", "review"])
        self.assertAlmostEqual(cost[0], OPUS_COST)
        self.assertEqual(cost[1], 0.0, "a review step has no Claude calls")
        self.assertAlmostEqual(cost[2], OPUS_COST)
        self.assertEqual(cost[3], 0.0)
        self.assertEqual(r["steps"][0]["claude"]["calls"], 1)

    def test_a_call_outside_every_step_is_kept_separately_and_still_counted_in_the_total(self):
        self.make_run(calls=self.standard_calls())
        r = self.run0()
        self.assertAlmostEqual(r["unassigned"]["cost"], OPUS_COST)
        self.assertEqual(r["unassigned"]["calls"], 1)
        self.assertAlmostEqual(r["totals"]["claude"]["cost"], 3 * OPUS_COST)

    def test_a_few_seconds_of_slack_either_side_of_a_step(self):
        self.make_run(rows=[standard_rows()[0]], calls=[
            assistant(10 + 3 / 60, "claude-opus-4-9", OPUS_USAGE, "late", "r1"),     # 3 s after the end: still the arm
            assistant(10 + 30 / 60, "claude-opus-4-9", OPUS_USAGE, "way", "r2")])    # 30 s after: outside
        r = self.run0()
        self.assertEqual(r["steps"][0]["claude"]["calls"], 1)
        self.assertEqual(r["unassigned"]["calls"], 1)

    def test_a_call_never_belongs_to_a_review_step(self):
        # 11.5 min is inside the 10-11 min review's slack window but that is Copilot's step: it is outside every Claude step
        self.make_run(calls=[assistant(10.5, "claude-opus-4-9", OPUS_USAGE, "r", "r1")])
        r = self.run0()
        self.assertEqual([s["claude"]["calls"] for s in r["steps"]], [0, 0, 0, 0])
        self.assertEqual(r["unassigned"]["calls"], 1)

    def test_a_call_just_after_a_fix_stays_with_the_fix_not_the_next_review(self):
        # the fix ends at minute 15 and the next review starts at minute 15: a call 2 s after the fix's end is still the fix's
        self.make_run(calls=[assistant(15 + 2 / 60, "claude-opus-4-9", OPUS_USAGE, "late", "r1")])
        r = self.run0()
        self.assertEqual((r["steps"][2]["type"], r["steps"][2]["claude"]["calls"]), ("fix", 1))
        self.assertEqual(r["steps"][3]["claude"]["calls"], 0)

    def test_a_step_that_holds_the_call_wins_over_the_slack_of_a_neighbour(self):
        rows = [(ts(0), ts(10), "arm", 0, "claude-opus-4-9", "a", "interactive;exit=0"),
                (ts(10), ts(20), "resume", 1, "claude-opus-4-9", "b", "interactive;exit=0")]
        self.make_run(rows=rows, calls=[assistant(10, "claude-opus-4-9", OPUS_USAGE, "edge", "r1")])
        r = self.run0()
        self.assertEqual([s["claude"]["calls"] for s in r["steps"]], [0, 1], "a call stamped at the later step's start is that step's")

    def test_cost_uses_the_dashboards_own_rates_and_dedupes_streamed_calls(self):
        dup = assistant(5, "claude-opus-4-9", OPUS_USAGE, "same", "r1")
        self.make_run(rows=[standard_rows()[0]], calls=[dup, dict(dup)])
        self.assertAlmostEqual(self.run0()["totals"]["claude"]["cost"], OPUS_COST, msg="the same message streamed twice counts once")

    def test_in_and_out_dollars_and_tokens_are_kept(self):
        self.make_run(rows=[standard_rows()[0]], calls=[assistant(5, "claude-opus-4-9", OPUS_USAGE)])
        c = self.run0()["steps"][0]["claude"]
        self.assertEqual((c["in_tok"], c["out_tok"]), (100_000, 10_000))
        self.assertAlmostEqual(c["in_cost"], 0.50)
        self.assertAlmostEqual(c["out_cost"], 0.25)

    def test_subagent_logs_in_the_session_folder_count_too(self):
        self.make_run(rows=[standard_rows()[0]], calls=[assistant(5, "claude-opus-4-9", OPUS_USAGE, "m", "r")])
        write_log(Path(self.runs) / "r1.session", "-work/s1/subagents/agent-1.jsonl",
                  [assistant(6, "claude-opus-4-9", OPUS_USAGE, "sub", "rs", side=True)])
        self.assertAlmostEqual(self.run0()["totals"]["claude"]["cost"], 2 * OPUS_COST)

    def test_reading_a_run_leaves_the_call_sink_off(self):
        self.make_run(calls=self.standard_calls())
        self.ab()
        self.assertIsNone(b.CALL_SINK)
        self.assertEqual(len(b.collect(self.main, days=0)["sessions"]), 1, "the ordinary sessions are unaffected by the A/B read")


class Totals(AbBase):
    def test_totals_for_a_run_that_needed_one_fix(self):
        self.make_run(calls=self.standard_calls())
        t = self.run0()["totals"]
        self.assertEqual((t["reviews"], t["fixes"], t["rounds"], t["clean_round"]), (2, 1, 2, 2))
        self.assertEqual(t["findings"], [2, 0])
        self.assertEqual(t["copilot_requests"], 2)

    def test_a_run_that_never_comes_back_clean(self):
        rows = [standard_rows()[0], standard_rows()[1]]
        self.make_run(rows=rows, calls=[])
        t = self.run0()["totals"]
        self.assertIsNone(t["clean_round"])
        self.assertEqual((t["reviews"], t["rounds"]), (1, 1))

    def test_the_first_clean_round_is_the_one_reported(self):
        rows = standard_rows() + [(ts(17), ts(18), "review", 3, "copilot", "ghi", REVIEW2)]
        self.make_run(rows=rows)
        self.assertEqual(self.run0()["totals"]["clean_round"], 2)

    def test_review_rows_carry_the_copilot_fields(self):
        self.make_run()
        c = self.run0()["steps"][1]["copilot"]
        self.assertEqual(c, {"requests": 1, "findings": 2, "status": "findings", "effort": "balanced", "pr": "3"})
        self.assertIsNone(self.run0()["steps"][0]["copilot"], "only review steps have a Copilot side")

    def test_no_request_round_counts_zero(self):
        rows = [(ts(0), ts(1), "review", 1, "copilot", "a", "pr=3;findings=0;status=clean;premium_requests=0;effort=balanced")]
        self.make_run(rows=rows)
        self.assertEqual(self.run0()["totals"]["copilot_requests"], 0)

    def test_arm_model_is_the_first_claude_step_and_exit_codes_are_kept(self):
        rows = standard_rows()
        rows[2] = (ts(12), ts(15), "fix", 1, "claude-opus-4-9", "def5678", "headless;exit=1")
        self.make_run(rows=rows)
        r = self.run0()
        self.assertEqual(r["arm_model"], "claude-opus-4-9")
        self.assertEqual((r["steps"][0]["exit"], r["steps"][2]["exit"], r["steps"][0]["mode"]), (0, 1, "interactive"))

    def test_every_step_has_one_cost_whoever_incurred_it(self):
        self.make_run(calls=self.standard_calls())
        with mock.patch.object(b, "PRICING", dict(FIXED_PRICING, copilot_usd_per_review=0.04)):
            r = self.run0()
        costs = [(s["type"], s["cost"], s["cost_est"]) for s in r["steps"]]
        self.assertEqual(costs, [("arm", OPUS_COST, False), ("review", 0.04, True), ("fix", OPUS_COST, False), ("review", 0.04, True)])

    def test_the_run_total_is_claude_plus_copilot_and_flags_the_estimate(self):
        self.make_run(calls=self.standard_calls())
        with mock.patch.object(b, "PRICING", dict(FIXED_PRICING, copilot_usd_per_review=0.04)):
            t = self.run0()["totals"]
        self.assertAlmostEqual(t["cost"], 3 * OPUS_COST + 2 * 0.04, places=4)
        self.assertTrue(t["cost_est"])
        self.assertAlmostEqual(t["claude"]["cost"], 3 * OPUS_COST, msg="the Claude side stays available on its own")

    def test_without_a_rate_reviews_have_no_cost_and_the_total_is_claude_only(self):
        self.make_run(calls=self.standard_calls())
        r = self.run0()
        self.assertEqual([s["cost"] for s in r["steps"] if s["type"] == "review"], [None, None])
        self.assertAlmostEqual(r["totals"]["cost"], 3 * OPUS_COST)
        self.assertFalse(r["totals"]["cost_est"], "nothing in the total is an estimate when Copilot is not priced")

    def test_without_session_logs_claude_steps_and_the_total_have_no_cost_but_reviews_still_do(self):
        self.make_run()
        with mock.patch.object(b, "PRICING", dict(FIXED_PRICING, copilot_usd_per_review=0.04)):
            r = self.run0()
        self.assertEqual([s["cost"] for s in r["steps"]], [None, 0.04, None, 0.04])
        self.assertIsNone(r["totals"]["cost"], "a total that leaves out Claude would mislead; it is unknown")
        self.assertAlmostEqual(r["totals"]["copilot_usd"], 0.08)

    def test_wall_time_runs_from_the_first_start_to_the_last_end(self):
        self.make_run()
        self.assertEqual(self.run0()["wall_s"], 16 * 60)

    def test_copilot_dollars_appear_only_when_a_rate_is_set(self):
        self.make_run()
        self.assertIsNone(self.run0()["totals"]["copilot_usd"])
        rated = dict(FIXED_PRICING, copilot_usd_per_review=0.04)
        with mock.patch.object(b, "PRICING", rated):
            self.assertAlmostEqual(self.run0()["totals"]["copilot_usd"], 0.08)


class Robustness(AbBase):
    def test_a_run_without_session_logs_is_listed_with_its_claude_cost_marked_unknown(self):
        self.make_run()
        r = self.run0()
        self.assertFalse(r["claude_known"])
        self.assertEqual(len(r["steps"]), 4)
        self.assertEqual(r["totals"]["copilot_requests"], 2, "the Copilot side does not need session logs")

    def test_rows_with_a_bad_time_or_no_type_are_skipped(self):
        text = HEADER + "\n" + "garbage,garbage,arm,0,m,c,d\n" + ",,,,,,\n" + "%s,%s,,0,m,c,d\n" % (ts(0), ts(1)) + \
            "%s,%s,arm,0,claude-opus-4-9,c,interactive\n" % (ts(0), ts(1))
        self.make_run(csv_text=text)
        self.assertEqual(len(self.run0()["steps"]), 1)

    def test_a_steps_file_with_no_usable_rows_is_not_a_run(self):
        self.make_run(csv_text=HEADER + "\n")
        self.assertIsNone(self.ab())

    def test_missing_runs_folder_or_no_runs_means_no_ab_key(self):
        self.assertNotIn("ab", b.collect(self.main, days=0))
        self.assertNotIn("ab", b.collect(self.main, days=0, ab_root=str(Path(self._tmp.name) / "nope")))
        Path(self.runs).mkdir()
        self.assertNotIn("ab", b.collect(self.main, days=0, ab_root=self.runs))

    def test_runs_are_listed_by_name(self):
        for n in ("b-run", "a-run"):
            self.make_run(n)
        self.assertEqual([r["name"] for r in self.ab()["runs"]], ["a-run", "b-run"])

    def test_detail_parsing(self):
        self.assertEqual(ab_steps.parse_detail("pr=3;findings=1;headless"), ({"pr": "3", "findings": "1"}, ["headless"]))
        self.assertEqual(ab_steps.parse_detail(""), ({}, []))

    def test_newest_mtime_sees_steps_and_session_logs(self):
        self.assertEqual(ab_steps.newest_mtime(self.runs), 0.0)
        self.make_run(calls=self.standard_calls())
        self.assertGreater(ab_steps.newest_mtime(self.runs), 0.0)
        self.assertEqual(ab_steps.newest_mtime(None), 0.0)

    def test_summary_lists_the_runs(self):
        self.make_run(calls=self.standard_calls())
        text = b.summary(b.collect(self.main, days=0, ab_root=self.runs), "out.html")
        self.assertIn("A/B runs:", text)
        self.assertIn("r1: Claude $2.25 (Copilot not priced), 2 Copilot review(s), clean at round 2", text)

    def test_summary_gives_one_total_when_copilot_is_priced(self):
        self.make_run(calls=self.standard_calls())
        with mock.patch.object(b, "PRICING", dict(FIXED_PRICING, copilot_usd_per_review=0.04)):
            text = b.summary(b.collect(self.main, days=0, ab_root=self.runs), "out.html")
        self.assertIn("r1: $2.33 (Claude $2.25 + Copilot ~$0.08), 2 Copilot review(s), clean at round 2", text)

    def test_summary_says_when_a_run_has_no_session_logs(self):
        self.make_run()
        self.assertIn("no session logs", b.summary(b.collect(self.main, days=0, ab_root=self.runs), "out.html"))


class Page(AbBase):
    def draw(self, actions=None):
        return run_page(self, b.render(b.collect(self.main, days=0, ab_root=self.runs)), actions)

    @staticmethod
    def text(out, k):
        return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", out[k]))

    def test_the_tab_table_shows_both_runs_side_by_side(self):
        self.make_run("a-run", calls=self.standard_calls())
        self.make_run("b-run", rows=[standard_rows()[0], standard_rows()[1]], calls=[assistant(5, "claude-opus-4-9", OPUS_USAGE)])
        t = self.text(self.draw(), "ab-runs")
        self.assertIn("a-run", t)
        self.assertIn("b-run", t)
        self.assertIn("round 2", t, "a-run came back clean in round 2")
        self.assertIn("not clean after 1", t, "b-run never did")
        self.assertIn("2 → 0", t, "findings per round")
        self.assertIn("$2.25", t)

    def test_opening_a_run_lists_every_step_under_it(self):
        self.make_run(calls=self.standard_calls())
        out = self.draw([{"abToggle": "run:r1"}])
        t = self.text(out, "ab-runs")
        for want in ("Arm session", "Review 1", "Fix 1", "Review 2", "Copilot · balanced", "2 findings", "clean", "Outside any step"):
            self.assertIn(want, t)
        self.assertEqual(len(re.findall(r'<tr class="ab step[ "]', out["ab-runs"])), 5, "four steps, then the calls that fell outside every step")

    def test_each_run_opens_to_its_own_steps(self):
        self.make_run("a-run", calls=self.standard_calls())
        self.make_run("b-run", rows=[standard_rows()[0]], calls=[assistant(5, "claude-opus-4-9", OPUS_USAGE)])
        self.assertIn("Fix 1", self.text(self.draw([{"abToggle": "run:a-run"}]), "ab-runs"))
        self.assertNotIn("Fix 1", self.text(self.draw([{"abToggle": "run:b-run"}]), "ab-runs"))

    def test_unknown_claude_cost_shows_a_dash_and_a_note(self):
        self.make_run()
        out = self.draw()
        self.assertIn("unknown, not zero", out["ab-note"])
        self.assertNotIn("$0.00", self.text(out, "ab-runs"))

    def test_without_a_rate_a_run_total_is_claude_only_and_the_note_says_so(self):
        self.make_run(calls=self.standard_calls())
        out = self.draw([{"abToggle": "run:r1"}])
        self.assertIn("Claude only", out["ab-note"])
        self.assertNotIn("~$", self.text(out, "ab-runs"), "neither the run row nor its steps carry an estimate")
        self.assertIn("$2.25", self.text(out, "ab-runs"))

    def test_with_a_rate_the_note_and_the_estimates_appear(self):
        self.make_run(calls=self.standard_calls())
        with mock.patch.object(b, "PRICING", dict(FIXED_PRICING, copilot_usd_per_review=0.04)):
            out = self.draw()
        self.assertIn("reviews x $0.04", out["ab-note"])
        self.assertIn("AI credits", out["ab-note"], "the note says how GitHub actually bills it")
        self.assertIn("~$2.33", self.text(out, "ab-runs"), "Claude $2.25 + two reviews at $0.04")

    def test_there_is_one_cost_column_for_claude_and_copilot_steps(self):
        self.make_run(calls=self.standard_calls())
        with mock.patch.object(b, "PRICING", dict(FIXED_PRICING, copilot_usd_per_review=0.04)):
            out = self.draw([{"abToggle": "run:r1"}])
        head = re.findall(r"<th[^>]*>(.*?)</th>", out["ab-runs"])
        self.assertIn("Cost", head)
        self.assertNotIn("Claude $", head, "no per-vendor cost column")
        self.assertFalse([h for h in head if "Copilot $" in h])
        rows = [re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", r)).strip() for r in re.findall(r'<tr class="ab step[^"]*"[^>]*>(.*?)</tr>', out["ab-runs"], re.S)][:4]
        self.assertEqual(len(rows), 4)
        self.assertIn("$0.75", rows[0], "a Claude step's cost")
        self.assertNotIn("~", rows[0], "a Claude step is priced from its log, not estimated")
        self.assertIn("~$0.04", rows[1], "a Copilot review's cost sits in the same column, marked as an estimate")
        self.assertIn("$0.75", rows[2])
        self.assertIn("~$0.04", rows[3])

    def test_the_page_says_reviews_not_requests(self):
        self.make_run(calls=self.standard_calls())
        out = self.draw([{"abToggle": "run:r1"}])
        self.assertIn("Copilot reviews", out["ab-runs"])
        self.assertIn("2 findings", self.text(out, "ab-runs"))
        self.assertNotIn("request", self.text(out, "ab-runs") + out["ab-note"])

    def test_the_shipped_rate_is_a_positive_number_with_its_source_and_date(self):
        shipped = json.loads((PLUGIN / "pricing.json").read_text())
        self.assertGreater(shipped["copilot_usd_per_review"], 0)
        self.assertLess(shipped["copilot_usd_per_review"], 5, "a per-review rate, not a monthly total")
        self.assertIn("AI credits", shipped["copilot_rate_note"])
        self.assertRegex(shipped["copilot_rate_checked"], r"^\d{4}-\d{2}-\d{2}$")

    def test_no_ab_data_draws_nothing_and_changes_nothing_else(self):
        out = run_page(self, b.render(b.collect(self.main, days=0)))
        for k in ("ab-runs", "ab-note"):
            self.assertNotIn(k, out)

    def test_run_names_are_escaped(self):
        self.make_run('x"><b>y')
        self.assertNotIn("<b>y", self.draw()["ab-runs"])


def ab_user(minutes, text, sid):
    return dict(user(minutes, text), sessionId=sid)


class AbSessions(AbBase):
    """The A/B runs' sessions also count in the other tabs: tagged, named after the run, once."""

    def two_session_run(self, name="r1"):
        """An arm session and a fix session: one log file each, as Claude Code writes them (the file name is the session id)."""
        self.make_run(name)
        sess = Path(self.runs) / (name + ".session")
        write_log(sess, "-work/arm1.jsonl", [ab_user(0, "Implement plan 0001", "arm1"), assistant(5, "claude-opus-4-9", OPUS_USAGE, "a1", "ra1", sid="arm1")])
        write_log(sess, "-work/fix1.jsonl", [ab_user(12, "Read REVIEW-1.md", "fix1"), assistant(13, "claude-opus-4-9", OPUS_USAGE, "f1", "rf1", sid="fix1")])

    def sessions(self, **kw):
        return {s["id"]: s for s in b.collect(self.main, days=0, ab_root=self.runs, **kw)["sessions"]}

    def test_the_runs_sessions_are_listed_named_after_the_run_and_tagged(self):
        self.two_session_run()
        ses = self.sessions()
        self.assertEqual(set(ses), {"s1", "arm1", "fix1"})
        for sid in ("arm1", "fix1"):
            self.assertEqual((ses[sid]["project"], ses[sid]["ab"]), ("r1", "r1"), "the container always logs as /work; the run name is the label")
            self.assertAlmostEqual(ses[sid]["cost"], OPUS_COST)
        self.assertEqual(ses["arm1"]["title"], "Implement plan 0001")

    def test_other_sessions_carry_no_ab_key(self):
        self.two_session_run()
        self.assertNotIn("ab", self.sessions()["s1"])

    def test_the_other_tabs_include_the_cost_and_the_model(self):
        self.two_session_run()
        with_ab = b.collect(self.main, days=0, ab_root=self.runs)
        without = b.collect(self.main, days=0)
        total = lambda d: sum(s["cost"] for s in d["sessions"])
        self.assertAlmostEqual(total(with_ab) - total(without), 2 * OPUS_COST, places=4)
        calls = lambda d: sum(c["calls"] for s in d["sessions"] for e in s["matrix"].values() for c in e.values())
        self.assertEqual(calls(with_ab) - calls(without), 2, "the model x effort grid counts them too")

    def test_the_ab_tab_and_the_session_list_agree_so_nothing_is_counted_twice(self):
        self.two_session_run()
        data = b.collect(self.main, days=0, ab_root=self.runs)
        in_sessions = sum(s["cost"] for s in data["sessions"] if s.get("ab") == "r1")
        self.assertAlmostEqual(in_sessions, data["ab"]["runs"][0]["totals"]["claude"]["cost"], places=4)
        self.assertEqual(len([s for s in data["sessions"] if s.get("ab")]), 2, "each A/B session appears once")

    def test_a_root_that_contains_the_runs_folder_does_not_count_them_twice(self):
        self.two_session_run()
        inside = Path(self._tmp.name)                # the main root and the runs folder's parent
        shutil_root = str(inside)
        data = b.collect(shutil_root, days=0, ab_root=self.runs)
        self.assertEqual(sorted(s["id"] for s in data["sessions"]), ["arm1", "fix1", "s1"], "each session once, not once per scan")
        self.assertTrue(all(s.get("ab") == "r1" for s in data["sessions"] if s["id"] != "s1"))
        self.assertAlmostEqual(sum(s["cost"] for s in data["sessions"] if s.get("ab")), 2 * OPUS_COST, places=4)
        off = b.collect(shutil_root, days=0, ab_root=self.runs, ab_sessions=False)
        self.assertEqual([s["id"] for s in off["sessions"]], ["s1"], "with the flag off they are left out even when the root holds them")

    def test_the_flag_leaves_them_out_of_the_other_tabs_but_not_the_ab_tab(self):
        self.two_session_run()
        data = b.collect(self.main, days=0, ab_root=self.runs, ab_sessions=False)
        self.assertEqual([s["id"] for s in data["sessions"]], ["s1"])
        self.assertAlmostEqual(data["ab"]["runs"][0]["totals"]["claude"]["cost"], 2 * OPUS_COST, places=4)

    def test_without_an_ab_root_nothing_changes(self):
        self.two_session_run()
        plain = b.collect(self.main, days=0)
        self.assertEqual([s["id"] for s in plain["sessions"]], ["s1"])
        self.assertNotIn("ab", plain)

    def test_a_subagent_log_in_a_run_session_counts_in_that_session(self):
        self.two_session_run()
        write_log(Path(self.runs) / "r1.session", "-work/arm1/subagents/agent-1.jsonl",
                  [assistant(6, "claude-opus-4-9", OPUS_USAGE, "sub", "rs", side=True, sid="arm1")])
        self.assertAlmostEqual(self.sessions()["arm1"]["cost"], 2 * OPUS_COST)

    def test_two_runs_stay_separate(self):
        self.two_session_run("a-run")
        write_log(Path(self.runs) / "b-run.session", "-work/other.jsonl",
                  [ab_user(0, "go", "other"), assistant(1, "claude-opus-4-9", OPUS_USAGE, "o1", "ro1", sid="other")])
        (Path(self.runs) / "b-run.reviews").mkdir()
        ses = self.sessions()
        self.assertEqual((ses["arm1"]["ab"], ses["other"]["ab"]), ("a-run", "b-run"))

    def test_the_project_filter_finds_a_run_by_name(self):
        self.two_session_run("wordfreq-docs-x")
        ids = {s["id"] for s in b.collect(self.main, days=0, project="wordfreq", ab_root=self.runs)["sessions"]}
        self.assertEqual(ids, {"arm1", "fix1"})

    def test_a_runs_folder_with_session_logs_but_no_steps_still_counts_its_sessions(self):
        write_log(Path(self.runs) / "old.session", "-work/x.jsonl",
                  [ab_user(0, "go", "old1"), assistant(1, "claude-opus-4-9", OPUS_USAGE, "x1", "rx1", sid="old1")])
        self.assertEqual(self.sessions()["old1"]["ab"], "old")
        self.assertNotIn("ab", b.collect(self.main, days=0, ab_root=self.runs), "no steps.csv, so no A/B tab, but the cost is still counted")

    def test_the_session_table_tags_ab_rows_and_search_finds_them(self):
        self.two_session_run()
        html = b.render(b.collect(self.main, days=0, ab_root=self.runs))
        out = run_page(self, html)
        self.assertEqual(out["sess"].count('class="cd-tag">A/B<'), 2, "one tag per A/B session, none on the ordinary one")
        found = run_page(self, html, [{"search": "a/b"}])
        self.assertEqual(found["sess"].count('class="cd-tag">A/B<'), 2)
        self.assertNotIn("proj", re.sub(r"<[^>]+>", " ", found["sess"]), "the ordinary session is filtered out")
        self.assertIn("[A/B] r1", out["ctx-sel"], "the context picker marks them too")
        self.assertIn('class="cd-tag">A/B<', out["ctx-tbl"])


if __name__ == "__main__":
    unittest.main()
