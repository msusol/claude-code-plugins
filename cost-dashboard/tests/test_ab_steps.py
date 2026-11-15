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

    def test_wall_time_runs_from_the_first_start_to_the_last_end(self):
        self.make_run()
        self.assertEqual(self.run0()["wall_s"], 16 * 60)

    def test_copilot_dollars_appear_only_when_a_rate_is_set(self):
        self.make_run()
        self.assertIsNone(self.run0()["totals"]["copilot_usd"])
        rated = dict(FIXED_PRICING, copilot_usd_per_request=0.04)
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
        self.assertIn("r1: Claude $2.25, 2 Copilot request(s), clean at round 2", text)

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

    def test_the_steps_table_lists_every_step_with_totals(self):
        self.make_run(calls=self.standard_calls())
        out = self.draw()
        t = self.text(out, "ab-steps")
        for want in ("Arm session", "Review 1", "Fix 1", "Review 2", "Copilot · balanced", "2 findings · findings", "0 findings · clean", "Outside any step", "Total"):
            self.assertIn(want, t)
        self.assertEqual(out["ab-steps"].count('<tr class="tot"'), 1)

    def test_picking_another_run_redraws_the_steps(self):
        self.make_run("a-run", calls=self.standard_calls())
        self.make_run("b-run", rows=[standard_rows()[0]], calls=[assistant(5, "claude-opus-4-9", OPUS_USAGE)])
        self.assertIn("Fix 1", self.text(self.draw(), "ab-steps"))
        self.assertNotIn("Fix 1", self.text(self.draw([{"abPick": "b-run"}]), "ab-steps"))

    def test_unknown_claude_cost_shows_a_dash_and_a_note(self):
        self.make_run()
        out = self.draw()
        self.assertIn("unknown, not zero", out["ab-note"])
        self.assertNotIn("$0.00", self.text(out, "ab-runs"))

    def test_the_note_says_copilot_is_a_request_count_unless_a_rate_is_set(self):
        self.make_run(calls=self.standard_calls())
        self.assertIn("request count", self.draw()["ab-note"])
        with mock.patch.object(b, "PRICING", dict(FIXED_PRICING, copilot_usd_per_request=0.04)):
            out = self.draw()
        self.assertIn("requests x $0.04", out["ab-note"])
        self.assertIn("($0.08)", self.text(out, "ab-runs"))

    def test_no_ab_data_draws_nothing_and_changes_nothing_else(self):
        out = run_page(self, b.render(b.collect(self.main, days=0)))
        for k in ("ab-runs", "ab-steps", "ab-note"):
            self.assertNotIn(k, out)

    def test_run_names_are_escaped(self):
        self.make_run('x"><b>y')
        self.assertNotIn("<b>y", self.draw()["ab-runs"])


if __name__ == "__main__":
    unittest.main()
