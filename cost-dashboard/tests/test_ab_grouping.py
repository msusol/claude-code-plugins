"""Tests for the A/B tab's grouping: runs named <plan>-<model>-r<N> sit under their plan and round, group rows carry totals, and
every row opens down to the steps (arm session, each Copilot review round, each fix).

Run from the plugin repo root:  python3 -m unittest discover -s cost-dashboard/tests -v
"""
import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_ab_steps import AbBase, REVIEW1, REVIEW2  # noqa: E402
from test_build_dashboard import OPUS_USAGE, assistant, run_page, ts  # noqa: E402

import build_dashboard as b  # noqa: E402

OPUS, SONNET = "claude-opus-4-9", "claude-sonnet-5-5"


def rows_for(model):
    """arm 0-10 min, review 1 (2 findings), fix, review 2 (clean): two Copilot reviews, one fix."""
    return [(ts(0), ts(10), "arm", 0, model, "abc1234", "interactive;exit=0"),
            (ts(10), ts(11), "review", 1, "copilot", "abc1234", REVIEW1),
            (ts(12), ts(15), "fix", 1, model, "def5678", "headless;exit=0"),
            (ts(15), ts(16), "review", 2, "copilot", "def5678", REVIEW2)]


class GroupBase(AbBase):
    def add(self, name, model=OPUS, logged=True):
        calls = [assistant(5, model, OPUS_USAGE, "a-" + name, "ra-" + name, sid="s-" + name),
                 assistant(13, model, OPUS_USAGE, "f-" + name, "rf-" + name, sid="s-" + name)] if logged else None
        self.make_run(name, rows=rows_for(model), calls=calls)

    def setUp(self):
        super().setUp()
        self.add("leave-engine-docs-sonnet-r1", SONNET)                                        # a round with one arm: collapses to the run
        for n in (2, 3):                                                                       # two rounds of two arms
            self.add("leave-engine-docs-fable-r%d" % n, OPUS)
            self.add("leave-engine-docs-sonnet-r%d" % n, SONNET)
        self.add("solo-check-r1", SONNET)                                                      # a plan with a single run
        self.add("wordfreq-docs-fable-loop-r1", OPUS)                                          # "-fable-loop" is a model, not part of the plan
        self.add("wordfreq-docs-sonnet-r1", SONNET)
        self.data = b.collect(self.main, days=0, ab_root=self.runs)
        self.html = b.render(self.data)

    def page(self, *actions):
        return run_page(self, self.html, list(actions))["ab-runs"]

    def text(self, html):
        return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", html)).strip()

    def runs_of(self, prefix=""):
        return [r for r in self.data["ab"]["runs"] if r["name"].startswith(prefix)]


class PilotAndSearch(GroupBase):
    def setUp(self):
        super().setUp()
        for arm in "abc":
            self.add("pilot-p1-" + arm, SONNET)
        self.add("pilot-p2-c", SONNET)
        self.data = b.collect(self.main, days=0, ab_root=self.runs)
        self.html = b.render(self.data)

    def test_a_pilots_three_arms_are_one_group(self):
        h = self.text(self.page())
        self.assertIn("pilot-p1 3 runs", h)
        self.assertNotIn("pilot-p1-r0", h)
        self.assertEqual(self.page().count('data-key="run:pilot-p1-a"'), 0, "the arms sit inside the closed group")
        self.assertEqual(self.page({"abToggle": "round:pilot-p1"}).count('data-key="run:pilot-p1-'), 3)

    def test_a_pilot_with_one_arm_is_a_plain_run(self):
        self.assertEqual(self.page().count('data-key="run:pilot-p2-c"'), 1)

    def test_search_keeps_only_runs_that_match(self):
        h = self.page({"abSearch": "pilot-p1"})
        self.assertIn("pilot-p1 3 runs", self.text(h))
        self.assertNotIn("leave-engine", h)
        self.assertNotIn("solo-check", h)

    def test_search_matches_the_model_too_and_empty_search_shows_all(self):
        self.assertIn("solo-check-r1", self.page({"abSearch": "sonnet"}))
        self.assertNotIn("leave-engine-docs-fable-r2", self.page({"abSearch": "sonnet"}))
        self.assertIn("solo-check-r1", self.page({"abSearch": "x"}, {"abSearch": ""}))


class Collapsed(GroupBase):
    def test_each_plan_is_one_row_and_lone_runs_stay_plain_rows(self):
        h = self.page()
        self.assertEqual(h.count('class="ab grp x"'), 2, "the leave-engine-docs plan and the wordfreq-docs round")
        self.assertEqual(h.count('class="ab run x"'), 1, "solo-check-r1 is a plain run row")
        self.assertIn("solo-check-r1", h)
        self.assertNotIn("leave-engine-docs-fable-r2", h, "runs inside a collapsed group are not drawn")
        self.assertNotIn("class=\"ab step\"", h)

    def test_a_group_with_one_round_collapses_into_that_round(self):
        h = self.text(self.page())
        self.assertIn("wordfreq-docs-r1 2 runs", h, "plan wordfreq-docs has one round, so the round row stands for it")
        self.assertNotIn("wordfreq-docs 2 runs", h)

    def test_the_plan_row_counts_every_run_under_it(self):
        self.assertIn("leave-engine-docs 5 runs", self.text(self.page()))

    def test_a_plan_row_sums_cost_tokens_reviews_and_fixes_of_its_runs(self):
        runs = self.runs_of("leave-engine-docs")
        cost = sum(r["totals"]["cost"] for r in runs)
        h = self.page()
        plan = re.search(r'<tr class="ab grp x"[^>]*><td>leave-engine-docs.*?</tr>', h, re.S).group(0)
        t = self.text(plan)
        est = any(r["totals"]["cost_est"] for r in runs)
        self.assertIn(("~" if est else "") + "$%.2f" % cost, t, "the sum of the runs' costs, ~ only when a run's cost includes Copilot's average")
        self.assertEqual(re.findall(r'<td class="n">(\d+)</td>', plan),
                         [str(sum(r["totals"]["claude"]["calls"] for r in runs)), str(sum(r["totals"]["copilot_requests"] for r in runs)), "5"],
                         "10 Claude calls, 10 Copilot reviews and 5 fixes")
        self.assertIn("5 of 5 clean", t)
        self.assertIn("opus-4-9, sonnet-5-5", t, "the models used across the plan")

    def test_a_group_with_an_unlogged_run_is_marked_as_a_lower_bound(self):
        self.add("part-fable-r1", OPUS, logged=False)
        self.add("part-sonnet-r1", SONNET)
        self.data = b.collect(self.main, days=0, ab_root=self.runs)
        self.html = b.render(self.data)
        row = re.search(r'<tr class="ab grp x"[^>]*><td>part-r1.*?</tr>', self.page(), re.S).group(0)
        self.assertIn("≥", self.text(row), "a run with no session logs has unknown Claude cost, so the total is at least this")


class Expanding(GroupBase):
    def test_opening_the_plan_shows_its_rounds_and_lone_runs(self):
        h = self.page({"abToggle": "plan:leave-engine-docs"})
        self.assertIn("leave-engine-docs-sonnet-r1", h, "the one-arm round is a run row")
        self.assertIn("leave-engine-docs-r2 2 runs", self.text(h))
        self.assertIn("leave-engine-docs-r3 2 runs", self.text(h))
        self.assertNotIn("leave-engine-docs-fable-r2", h, "the arms of a round are still hidden")

    def test_opening_a_round_shows_both_arms_side_by_side(self):
        h = self.page({"abToggle": "plan:leave-engine-docs"}, {"abToggle": "round:leave-engine-docs-r2"})
        self.assertIn("leave-engine-docs-fable-r2", h)
        self.assertIn("leave-engine-docs-sonnet-r2", h)
        self.assertLess(h.index("leave-engine-docs-fable-r2"), h.index("leave-engine-docs-sonnet-r2"))
        self.assertNotIn("leave-engine-docs-fable-r3", h, "round 3 stays closed")

    def test_opening_a_run_shows_each_step_and_its_review_round(self):
        h = self.page({"abToggle": "plan:leave-engine-docs"}, {"abToggle": "round:leave-engine-docs-r2"},
                      {"abToggle": "run:leave-engine-docs-fable-r2"})
        steps = re.findall(r'<tr class="ab step[^"]*"[^>]*>(.*?)</tr>', h, re.S)
        labels = [self.text(s).split(" ")[0] + " " + self.text(s).split(" ")[1] for s in steps]
        self.assertEqual(labels, ["Arm session", "Review 1", "Fix 1", "Review 2"])
        txt = self.text(h)
        self.assertIn("Review 1 Copilot", txt)
        self.assertIn("2 findings", txt, "review round 1 found two")
        self.assertIn("clean", txt, "review round 2 came back clean")

    def test_clicking_an_open_row_closes_it_again(self):
        h = self.page({"abToggle": "plan:leave-engine-docs"}, {"abToggle": "plan:leave-engine-docs"})
        self.assertNotIn("leave-engine-docs-sonnet-r1", h)

    def test_expand_all_opens_every_group_run_and_step_and_collapse_all_undoes_it(self):
        h = self.page({"abAll": True})
        self.assertEqual(h.count('class="ab run x open'), 8, "every run is drawn and open (the selected one also carries sel)")
        self.assertEqual(len(re.findall(r'<tr class="ab step[ "]', h)), 8 * 4, "four steps per run")
        self.assertEqual(h.count('<tr class="ab call"'), 8 * 2, "and Expand all opens the steps too: two calls per run in these runs")
        h = self.page({"abAll": True}, {"abAll": False})
        self.assertNotIn("leave-engine-docs-fable-r2", h)
        self.assertEqual(h.count('class="ab grp x"'), 2)


class Unchanged(GroupBase):
    def test_there_is_no_separate_steps_table_any_more(self):
        for gone in ("ab-steps", "ab-sel", "ab-jump", "details ↓"):
            self.assertNotIn(gone, self.html, "the steps open under each run instead, so %s is gone" % gone)

    def test_an_unnamed_pattern_run_is_not_grouped(self):
        names = [r["name"] for r in self.data["ab"]["runs"]]
        self.assertIn("solo-check-r1", names)
        h = self.text(self.page())
        self.assertIn("solo-check-r1", h)
        self.assertNotIn("solo-check 1 runs", h)


class SolveRuns(GroupBase):
    """A run made by `solve` has one headless Claude step: its model, cost and calls belong to that step."""
    def test_a_solve_step_is_a_claude_step_with_its_model_and_cost(self):
        rows = [(ts(0), ts(10), "solve", 0, SONNET, "abc1234", "headless;exit=0")]
        calls = [assistant(5, SONNET, OPUS_USAGE, "a-solo", "ra-solo", sid="s-solo")]
        self.make_run("task-sonnet-r1", rows=rows, calls=calls)
        run = next(r for r in b.collect(self.main, days=0, ab_root=self.runs)["ab"]["runs"] if r["name"] == "task-sonnet-r1")
        self.assertEqual(run["arm_model"], SONNET, "the Model column shows the solver's model, not a dash")
        self.assertEqual(run["steps"][0]["type"], "solve")
        self.assertAlmostEqual(run["steps"][0]["cost"], 0.45, places=4, msg="100k in at $3 + 10k out at $15 per million")
        self.assertEqual(run["unassigned"]["calls"], 0, "the call belongs to the solve step, not to 'outside any step'")
        self.assertEqual(run["totals"]["fixes"], 0)

    def test_a_solve_step_is_labelled_solve_on_the_page(self):
        rows = [(ts(0), ts(10), "solve", 0, SONNET, "abc1234", "headless;exit=0")]
        self.make_run("task-sonnet-r1", rows=rows, calls=[assistant(5, SONNET, OPUS_USAGE, "a-solo", "ra-solo", sid="s-solo")])
        html = b.render(b.collect(self.main, days=0, ab_root=self.runs))
        h = run_page(self, html, [{"abToggle": "run:task-sonnet-r1"}])["ab-runs"]
        self.assertIn(">Solve<", h.replace("\n", ""))


class NoWrap(GroupBase):
    def test_no_cell_of_the_a_b_tables_wraps(self):
        m = re.search(r"([^{}]*#ab-runs[^{}]*)\{([^}]*white-space: nowrap[^}]*)\}", self.html)
        self.assertIsNotNone(m, "a rule for the A/B tables")
        self.assertIn("white-space: nowrap", m.group(2))
        for sel in ("#ab-runs th", "#ab-runs td", "#ab-runs .cd-kids"):
            self.assertIn(sel, m.group(1), sel + " is covered, so the group label and the model list stay on one line")

    def test_the_table_box_scrolls_sideways_instead_of_spilling(self):
        self.assertRegex(self.html, r"\.cd-box\s*\{[^}]*overflow-x:\s*auto")


def cells(tr):
    return [re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", c)).strip() for c in re.findall(r"<t[dh][^>]*>(.*?)</t[dh]>", tr, re.S)]


class Columns(GroupBase):
    """The columns the old Steps table had that the main table lacked: Calls (and the steps now carry it)."""
    def row(self, h, needle):
        return cells(re.search(r'<tr class="ab[^"]*"[^>]*>(?:(?!</tr>).)*?%s.*?</tr>' % re.escape(needle), h, re.S).group(0))

    def test_calls_is_a_column_between_model_and_the_tokens(self):
        head = cells(re.search(r"<thead>.*?</thead>", self.page(), re.S).group(0))
        self.assertEqual(head[:5], ["Run", "Model", "Calls", "Claude in", "Claude out"])
        self.assertEqual(len(head), 11)

    def test_a_run_row_shows_its_claude_calls(self):
        h = self.page({"abAll": True})
        run = next(r for r in self.data["ab"]["runs"] if r["name"] == "leave-engine-docs-fable-r2")
        row = self.row(h, ">leave-engine-docs-fable-r2")
        self.assertEqual(row[2], str(run["totals"]["claude"]["calls"]))
        self.assertEqual(row[2], "2", "the fixture logs two calls per run")

    def test_a_group_row_sums_the_calls_of_its_runs(self):
        h = self.page({"abToggle": "plan:leave-engine-docs"})
        self.assertEqual(self.row(h, ">leave-engine-docs ")[2], "10", "five runs, two calls each")
        self.assertEqual(self.row(h, ">leave-engine-docs-r2 ")[2], "4")

    def test_a_group_with_an_unlogged_run_marks_calls_as_a_lower_bound_too(self):
        self.add("part-fable-r1", OPUS, logged=False)
        self.add("part-sonnet-r1", SONNET)
        self.data = b.collect(self.main, days=0, ab_root=self.runs)
        self.html = b.render(self.data)
        self.assertEqual(self.row(self.page(), ">part-r1 ")[2], "≥2")

    def test_every_step_row_has_a_cell_for_every_column(self):
        h = self.page({"abToggle": "plan:leave-engine-docs"}, {"abToggle": "round:leave-engine-docs-r2"}, {"abToggle": "run:leave-engine-docs-fable-r2"})
        steps = re.findall(r'<tr class="ab step[^"]*"[^>]*>.*?</tr>', h, re.S)
        self.assertEqual(len(steps), 4)
        for tr in steps:
            self.assertEqual(len(cells(tr)), 11, "a step row lines up under the 11 headers")
        arm = cells(steps[0])
        self.assertEqual(arm[0], "Arm session")
        self.assertEqual(arm[2], "1", "the arm step made one call")
        self.assertEqual(cells(steps[1])[2], "–", "a Copilot review has no Claude calls")

    def test_the_run_name_column_is_pinned_while_the_table_scrolls_sideways(self):
        m = re.search(r"#ab-runs th:first-child, #ab-runs td:first-child \{([^}]*)\}", self.html)
        self.assertIsNotNone(m)
        self.assertIn("position: sticky", m.group(1))
        self.assertIn("left: 0", m.group(1))
        self.assertIn("var(--ab-bg, var(--panel))", m.group(1), "an opaque background, so cells do not show through it")
        self.assertRegex(self.html, r"#ab-runs tr\.ab\.step, #ab-runs tr\.ab\.call \{ --ab-bg: var\(--tint\)")


def blk(rec, *blocks):
    rec["message"]["content"] = list(blocks)
    return rec


class StepCalls(AbBase):
    """Each Claude step opens to the individual calls inside it, with what each did, like a run session does in the Sessions tab."""
    def setUp(self):
        super().setUp()
        def call(minute, mid, *blocks, side=False):
            return blk(assistant(minute, OPUS, OPUS_USAGE, mid, "r" + mid, sid="s-calls", side=side), *blocks)
        bash = lambda c: {"type": "tool_use", "id": "t", "name": "Bash", "input": {"command": c}}
        self.make_run("calls-run", rows=rows_for(OPUS), calls=[
            call(3, "c1", {"type": "thinking", "thinking": "x"}), call(3, "c1", bash("pytest -q")),                       # one call, two lines
            call(5, "c2", {"type": "text", "text": "tests pass, committing"}),
            call(13, "c3", {"type": "tool_use", "id": "t", "name": "Edit", "input": {"file_path": "wordfreq.py"}}, side=True),
            call(20, "c4", bash("git status"))])                                                                           # after every step
        self.data = b.collect(self.main, days=0, ab_root=self.runs)
        self.html = b.render(self.data)
        self.run = self.data["ab"]["runs"][0]

    def page(self, *actions):
        return run_page(self, self.html, list(actions))["ab-runs"]

    def cells(self, tr):
        return [re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", c)).strip() for c in re.findall(r"<td[^>]*>(.*?)</td>", tr, re.S)]

    def test_each_claude_step_carries_the_calls_assigned_to_it_with_what_they_did(self):
        arm, review1, fix, review2 = self.run["steps"]
        self.assertEqual([c["what"] for c in arm["call_list"]], ["Bash: pytest -q", "reply: tests pass, committing"])
        self.assertEqual(len(arm["call_list"]), arm["claude"]["calls"], "the list is as long as the step's Calls figure")
        self.assertAlmostEqual(sum(c["cost"] for c in arm["call_list"]), arm["cost"], places=3)
        self.assertEqual([c["what"] for c in fix["call_list"]], ["Edit: wordfreq.py"])
        self.assertTrue(fix["call_list"][0]["sub"])
        self.assertEqual(review1["call_list"], [], "a Copilot review made no Claude calls")
        self.assertEqual(review2["call_list"], [])
        self.assertEqual([c["what"] for c in self.run["loose_calls"]], ["Bash: git status"], "the call outside every step is kept too")
        self.assertEqual([c["ts"] for c in arm["call_list"]], sorted(c["ts"] for c in arm["call_list"]), "oldest first")

    def test_only_steps_with_calls_can_be_opened(self):
        h = self.page({"abToggle": "run:calls-run"})
        steps = re.findall(r'<tr class="ab step[^"]*"[^>]*>', h)
        self.assertEqual(len(steps), 5, "four steps and the calls outside any step")
        openable = [t for t in steps if " x" in t.split(">")[0].split("style")[0]]
        self.assertEqual(len(openable), 3, "the arm session, the fix and 'outside any step'; not the two reviews")
        self.assertNotIn('class="ab call"', h, "closed: no call rows yet")

    def test_opening_a_step_lists_its_calls_under_it(self):
        h = self.page({"abToggle": "run:calls-run"}, {"abToggle": "step:calls-run:0"})
        calls = re.findall(r'<tr class="ab call"[^>]*>.*?</tr>', h, re.S)
        self.assertEqual(len(calls), 2, "the arm session's two calls")
        first, second = (self.cells(c) for c in calls)
        self.assertRegex(first[0], r"^\d\d:\d\d:\d\d Bash: pytest -q$", "the time, then what it did")
        self.assertIn("reply: tests pass, committing", second[0])
        self.assertEqual(first[1], "opus-4-9 · unknown")
        self.assertEqual((first[3], first[4], first[5]), ("100.0k", "10.0k", "$0.75"), "tokens in and out, and the cost")
        self.assertEqual(len(first), 11, "a call row lines up under the 11 headers")
        self.assertLess(h.index("Arm session"), h.index("Bash: pytest -q"), "under its step")
        self.assertLess(h.index("Bash: pytest -q"), h.index("Review 1"), "and above the next step")
        self.assertRegex(h, r'<tr class="ab step x open"[^>]*data-key="step:calls-run:0"')

    def test_a_subagent_call_is_marked_and_the_tooltip_has_the_full_text(self):
        h = self.page({"abToggle": "run:calls-run"}, {"abToggle": "step:calls-run:2"})
        self.assertIn("[subagent] Edit: wordfreq.py", h)
        self.assertIn('title="[subagent] Edit: wordfreq.py"', h)

    def raw_page(self, *actions):
        return run_page(self, b.render({**self.data, "raw": True}), list(actions))["ab-runs"]

    def test_every_call_carries_the_id_of_the_session_it_came_from(self):
        calls = [c for st in self.run["steps"] for c in st["call_list"]] + self.run["loose_calls"]
        self.assertEqual(len(calls), 4)
        self.assertEqual({c["sid"] for c in calls}, {"s-calls"})

    def test_a_served_page_links_each_calls_time_to_its_raw_log(self):
        h = self.raw_page({"abToggle": "run:calls-run"}, {"abToggle": "step:calls-run:0"})
        links = re.findall(r'<a class="cd-rawt" href="/raw/([^"]+)" target="_blank" rel="noopener"[^>]*>(\d\d:\d\d:\d\d)</a>', h)
        self.assertEqual(len(links), 2, "one per call row")
        self.assertEqual({sid for sid, _ in links}, {"s-calls"})

    def test_a_saved_page_has_no_links(self):
        self.assertNotIn("/raw/", self.page({"abToggle": "run:calls-run"}, {"abToggle": "step:calls-run:0"}))

    def test_clicking_a_link_does_not_open_or_close_a_step(self):
        h = self.raw_page({"abToggle": "run:calls-run"}, {"abLink": "step:calls-run:0"})
        self.assertNotIn('class="ab call"', h, "a link click is not a click on the step")
        h = self.raw_page({"abToggle": "run:calls-run"}, {"abToggle": "step:calls-run:0"}, {"abLink": "step:calls-run:0"})
        self.assertIn('class="ab call"', h, "and does not close it")

    def test_the_calls_outside_any_step_open_too(self):
        h = self.page({"abToggle": "run:calls-run"}, {"abToggle": "step:calls-run:loose"})
        self.assertIn("Bash: git status", h)
        self.assertEqual(h.count('<tr class="ab call"'), 1)

    def test_opening_twice_closes_it(self):
        h = self.page({"abToggle": "run:calls-run"}, {"abToggle": "step:calls-run:0"}, {"abToggle": "step:calls-run:0"})
        self.assertNotIn('class="ab call"', h)

    def test_expand_all_opens_every_step_and_collapse_all_closes_them(self):
        self.assertEqual(self.page({"abAll": True}).count('<tr class="ab call"'), 4, "two in the arm session, one in the fix, one outside")
        self.assertNotIn('class="ab call"', self.page({"abAll": True}, {"abAll": False}))

    def test_call_rows_are_not_clickable_and_do_not_shift_the_columns(self):
        h = self.page({"abAll": True})
        call = re.search(r'<tr class="ab call"[^>]*>', h).group(0)
        self.assertNotIn("data-key", call)
        self.assertNotIn("tabindex", call)
        self.assertRegex(self.html, r"\.cd-table tr\.ab\.step td, \.cd-table tr\.ab\.call td \{ background: var\(--tint\)")


if __name__ == "__main__":
    unittest.main()
