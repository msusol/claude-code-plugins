"""Tests for nesting a run's session under the session that launched it (an orchestrator and its solver runs, or A/B arms).

Run from the plugin repo root:  python3 -m unittest discover -s cost-dashboard/tests -v

The link comes from the launcher's own log: a Bash tool call whose command is `run-ab.zsh solve <run> ...` (or run, resume,
review-loop, review-round, or the same through solver.zsh). Nothing in the run scripts has to record it.
"""
import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_ab_steps import AbBase, ab_user, steps_csv  # noqa: E402
from test_build_dashboard import HAIKU_USAGE, OPUS_USAGE, assistant, run_page, ts, user, write_log  # noqa: E402

import build_dashboard as b  # noqa: E402


def bash(minutes, command, sid="orch", msg_id="b1"):
    """An assistant call (Haiku, as the cheap orchestrator) that runs one Bash command: the orchestrator launching a run."""
    rec = assistant(minutes, "claude-haiku-4-9", HAIKU_USAGE, msg_id, "r" + msg_id, sid=sid)
    rec["message"]["content"] = [{"type": "tool_use", "id": "t" + msg_id, "name": "Bash", "input": {"command": command}}]
    return rec


def with_blocks(rec, *blocks):
    rec["message"]["content"] = list(blocks)
    return rec


def tool(name, **inp):
    return {"type": "tool_use", "id": "tu", "name": name, "input": inp}


def text(t):
    return {"type": "text", "text": t}


THINK = {"type": "thinking", "thinking": "hmm"}


def solve_rows(model="claude-opus-4-9"):
    return [(ts(1), ts(3), "solve", 0, model, "abc1234", "headless;exit=0")]


def arm_rows(model="claude-opus-4-9"):
    return [(ts(1), ts(3), "arm", 0, model, "abc1234", "interactive;exit=0")]


class NestingBase(AbBase):
    def launcher(self, *commands, sid="orch", start=0):
        """Write the launching session's log: one prompt, then one Bash call per command."""
        recs = [user(start, "hand this off")] + [bash(start + 1 + i, c, sid, "b%d" % i) for i, c in enumerate(commands)]
        write_log(self.main, "-p/%s.jsonl" % sid, [dict(r, sessionId=sid) for r in recs])

    def run_session(self, name, rows, model="claude-opus-4-9", sid=None, minute=2):
        calls = [assistant(minute, model, OPUS_USAGE, "a-" + name, "ra-" + name, sid=sid or "run-" + name)]
        self.make_run(name, rows=rows, calls=calls)

    def rows(self):
        return {r["id"]: r for r in b.collect(self.main, days=0, ab_root=self.runs)["sessions"]}


class Linking(NestingBase):
    def test_a_solve_run_nests_under_the_session_that_launched_it(self):
        self.launcher("AB_SOLVE_BUDGET_USD=2 auto-mode/ab-docker/run-ab.zsh solve fix-parser claude-fable-5-2 ~/proj main ~/b.md")
        self.run_session("fix-parser", solve_rows())
        r = self.rows()
        child = r["run-fix-parser"]
        self.assertEqual(child["parent"], "orch")
        self.assertEqual(child["kind"], "solver")
        self.assertEqual(child["ab"], "fix-parser")

    def test_an_arm_run_is_marked_a_b_and_still_nests(self):
        self.launcher("tmux send-keys -t ab-arm 'AB_DOCS=1 auto-mode/ab-docker/run-ab.zsh run arm-r1 claude-sonnet-5-5 ~/p main' Enter")
        self.run_session("arm-r1", arm_rows())
        child = self.rows()["run-arm-r1"]
        self.assertEqual((child["parent"], child["kind"]), ("orch", "A/B"))

    def test_the_same_command_through_solver_zsh_links_too(self):
        self.launcher("auto-mode/solver-docker/solver.zsh solve gen-task claude-fable-5-2 ~/p main ~/b.md")
        self.run_session("gen-task", solve_rows())
        self.assertEqual(self.rows()["run-gen-task"]["parent"], "orch")

    def test_resume_review_loop_and_review_round_link_too(self):
        for verb in ("resume", "review-loop", "review-round"):
            with self.subTest(verb=verb):
                name = "v-" + verb
                self.launcher("auto-mode/ab-docker/run-ab.zsh %s %s claude-sonnet-5-5" % (verb, name))
                self.run_session(name, arm_rows())
                self.assertEqual(self.rows()["run-" + name]["parent"], "orch")

    def test_review_summary_and_other_words_do_not_link(self):
        self.launcher("auto-mode/ab-docker/run-ab.zsh review-summary lonely-run", "echo run-ab.zsh is great lonely-run")
        self.run_session("lonely-run", arm_rows())
        self.assertNotIn("parent", self.rows()["run-lonely-run"])

    def test_the_earliest_launcher_still_in_the_data_wins(self):
        self.launcher("auto-mode/ab-docker/run-ab.zsh run shared-run m ~/p main", sid="late", start=30)
        self.launcher("auto-mode/ab-docker/run-ab.zsh run shared-run m ~/p main", sid="early", start=0)
        self.run_session("shared-run", arm_rows())
        self.assertEqual(self.rows()["run-shared-run"]["parent"], "early")

    def test_a_launcher_that_is_not_in_the_data_leaves_the_run_at_top_level(self):
        self.launcher("auto-mode/ab-docker/run-ab.zsh solve orphan-run m ~/p main ~/b.md")
        self.run_session("orphan-run", solve_rows())
        data = b.collect(self.main, days=0, ab_root=self.runs, project="no-such-launcher-project")
        self.assertEqual(data["sessions"], [], "the filter removed everything, so no parent can be named")
        data = b.collect(self.main, days=0, ab_root=self.runs, project="orphan-run")
        child = data["sessions"][0]
        self.assertNotIn("parent", child, "the launcher is filtered out, so the run is not nested under a row that is not there")
        self.assertEqual(child["kind"], "solver")

    def test_a_run_never_nests_under_itself_or_under_another_run_it_mentions(self):
        self.launcher("auto-mode/ab-docker/run-ab.zsh solve solo-run m ~/p main ~/b.md")
        # the run's own container session mentions its own launch command (for example in a transcript it read): not a launcher
        calls = [bash(2, "auto-mode/ab-docker/run-ab.zsh solve other-run m ~/p main ~/b.md", sid="run-solo-run", msg_id="x1")]
        self.make_run("solo-run", rows=solve_rows(), calls=calls)
        self.run_session("other-run", solve_rows())
        r = self.rows()
        self.assertEqual(r["run-solo-run"]["parent"], "orch")
        self.assertNotIn("parent", r["run-other-run"], "only an ordinary session can be a parent")

    def test_ordinary_sessions_carry_none_of_the_new_fields(self):
        self.launcher("auto-mode/ab-docker/run-ab.zsh solve some-run m ~/p main ~/b.md")
        self.run_session("some-run", solve_rows())
        r = self.rows()
        for sid in ("orch", "s1"):
            for key in ("parent", "kind", "ab"):
                self.assertNotIn(key, r[sid], "%s must not gain %s" % (sid, key))

    def test_the_kind_comes_from_the_step_log_not_the_run_name(self):
        self.launcher("auto-mode/ab-docker/run-ab.zsh run solve-named-arm m ~/p main")
        self.run_session("solve-named-arm", arm_rows())
        self.assertEqual(self.rows()["run-solve-named-arm"]["kind"], "A/B")

    def test_a_run_with_no_step_log_is_an_a_b_run(self):
        self.launcher("auto-mode/ab-docker/run-ab.zsh run nolog-run m ~/p main")
        calls = [assistant(2, "claude-opus-4-9", OPUS_USAGE, "a1", "ra1", sid="run-nolog-run")]
        write_log(Path(self.runs) / "nolog-run.session", "-work/s.jsonl", calls)
        self.assertEqual(self.rows()["run-nolog-run"]["kind"], "A/B")

    def test_the_models_of_the_launcher_and_the_solver_stay_separate_on_their_own_rows(self):
        self.launcher("auto-mode/ab-docker/run-ab.zsh solve split-run claude-opus-4-9 ~/p main ~/b.md")
        self.run_session("split-run", solve_rows("claude-opus-4-9"))
        r = self.rows()
        self.assertEqual(list(r["orch"]["models"]), ["claude-haiku-4-9"])
        self.assertEqual(list(r["run-split-run"]["models"]), ["claude-opus-4-9"])


class PageNesting(NestingBase):
    def setUp(self):
        super().setUp()
        self.launcher("auto-mode/ab-docker/run-ab.zsh solve run-a claude-opus-4-9 ~/p main ~/b.md",
                      "auto-mode/ab-docker/run-ab.zsh run run-b claude-opus-4-9 ~/p main")
        self.run_session("run-a", solve_rows())
        self.run_session("run-b", arm_rows())
        self.html = b.render(b.collect(self.main, days=0, ab_root=self.runs))

    def page(self, *actions):
        return run_page(self, self.html, list(actions))

    def text(self, out, key="sess"):
        return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", out[key]))

    def test_nested_rows_are_hidden_until_the_launching_row_is_opened(self):
        out = self.page()
        self.assertNotIn('class="s kid', out["sess"], "a closed row shows nothing under it")
        self.assertNotIn("run-run-a", out["sess"])
        self.assertRegex(out["sess"], r'<tr class="s" data-id="orch"', "closed: no open marker, so the caret points right")
        out = self.page({"expand": "orch"})
        self.assertEqual(out["sess"].count('class="s kid'), 2, "opened: its two runs appear")
        self.assertRegex(out["sess"], r'<tr class="s open" data-id="orch"')

    def test_opening_a_launching_row_shows_its_runs_and_not_its_own_task_list(self):
        out = self.page({"expand": "orch"})
        self.assertNotIn('<tr class="t"', out["sess"], "the runs are what opens; its own prompts would only bury them")
        self.assertNotIn("No task breakdown", out["sess"])

    def test_opening_twice_closes_it_again(self):
        out = self.page({"expand": "orch"}, {"expand": "orch"})
        self.assertNotIn('class="s kid', out["sess"])

    def test_children_sit_directly_under_their_parent_with_a_role_each(self):
        out = self.page({"expand": "orch"})
        html = out["sess"]
        self.assertEqual(html.count('class="s kid'), 2, "both runs are nested rows")
        self.assertIn(">ORCHESTRATOR<", html)
        self.assertIn(">SOLVER<", html)
        self.assertIn(">A/B<", html)
        orch, a, bb = (html.index(x) for x in ('data-id="orch"', 'data-id="run-run-a"', 'data-id="run-run-b"'))
        self.assertLess(orch, a, "a child follows its parent")
        self.assertLess(a, bb, "children are in the order they started")

    def test_only_top_level_sessions_are_counted_and_paged(self):
        out = self.page()
        self.assertEqual(html_rows(out["sess"], "s"), 2, "closed: the orchestrator and the unrelated session")
        out = self.page({"expand": "orch"})
        self.assertEqual(html_rows(out["sess"], "s"), 4, "opened: the orchestrator, the unrelated session and the two nested rows")
        self.assertIn("1–2 of 2", self.text(out, "pager"), "two top-level sessions: the orchestrator and the unrelated one")
        self.assertIn("nested sessions sit under their launcher", self.text(out, "pager"))

    def row_cells(self, out, sid):
        tr = re.search(r'<tr class="s[^"]*" data-id="%s".*?</tr>' % re.escape(sid), out["sess"], re.S).group(0)
        return [re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", c)).strip() for c in re.findall(r"<td[^>]*>(.*?)</td>", tr, re.S)]

    def test_the_orchestrator_row_shows_only_its_own_model_and_no_summary_of_what_is_nested(self):
        out = self.page()
        cells = self.row_cells(out, "orch")
        self.assertIn("haiku-4-9", cells[2], "the Model column is the orchestrator's own model")
        self.assertNotIn("opus-4-9", cells[2], "not the models of the runs nested under it")
        txt = self.text(out)
        for gone in ("nested:", "solver ·", "1 solver", "A/B ·"):
            self.assertNotIn(gone, txt, "the count and the nested-models line are not drawn")
        self.assertIn("ORCHESTRATOR", cells[1], "the role tag stays")

    def test_each_nested_row_still_shows_its_own_model(self):
        out = self.page({"expand": "orch"})
        for sid in ("run-run-a", "run-run-b"):
            self.assertIn("opus-4-9", self.row_cells(out, sid)[2])

    def test_the_orchestrator_cost_is_only_its_own_with_no_roll_up_of_what_is_nested(self):
        out = self.page()
        cells = self.row_cells(out, "orch")
        self.assertRegex(cells[-1], r"^\$[\d.,]+$", "just its own cost, nothing added under it")
        self.assertNotIn("nested", cells[-1])
        self.assertNotIn("+$", self.text(out))

    def test_a_search_for_a_nested_run_keeps_its_parent_and_hides_the_rest(self):
        # the search covers the role, so "solver" finds only the solver run
        out = self.page({"search": "solver"})
        html = out["sess"]
        self.assertIn('data-id="orch"', html)
        self.assertIn('data-id="run-run-a"', html)
        self.assertNotIn('data-id="run-run-b"', html, "the A/B arm does not match 'solver'")
        self.assertNotIn('data-id="s1"', html, "the unrelated session does not match either")

    def test_a_search_that_matches_only_the_parent_does_not_open_it(self):
        out = self.page({"search": "orchestrator"})
        self.assertIn('data-id="orch"', out["sess"])
        self.assertNotIn('data-id="run-run-a"', out["sess"], "matching the parent is not a reason to unfold 23 rows")
        out = self.page({"search": "orchestrator"}, {"expand": "orch"})
        self.assertIn('data-id="run-run-a"', out["sess"])
        self.assertIn('data-id="run-run-b"', out["sess"], "opened, a parent that matches shows all its runs")

    def test_without_any_run_the_page_has_no_nesting(self):
        html = b.render(b.collect(self.main, days=0, ab_root=str(Path(self.runs) / "none")))
        out = run_page(self, html, [])
        self.assertNotIn(" kid", out["sess"])
        self.assertNotIn("ORCHESTRATOR", out["sess"])
        self.assertNotIn("nested", self.text(out, "pager"))


def html_rows(html, cls):
    return len(re.findall(r'<tr class="%s[ "]' % cls, html))


class NestedOrder(NestingBase):
    """Nested rows follow the table's sort key and direction, like the top level: the same arrow means the same order everywhere."""
    def setUp(self):
        super().setUp()
        self.launcher(*["auto-mode/ab-docker/run-ab.zsh solve %s m ~/p main ~/b.md" % n for n in ("t-early", "t-mid", "t-late")])
        # started and ended at different times, and costing different amounts (one call of 100k in and 10k out each)
        for name, minute, model in (("t-early", 2, "claude-sonnet-5-5"), ("t-mid", 12, "claude-opus-4-9"), ("t-late", 22, "claude-haiku-4-5")):
            self.run_session(name, [(ts(minute - 1), ts(minute + 1), "solve", 0, model, "abc1234", "headless;exit=0")], model=model, minute=minute)
        self.html = b.render(b.collect(self.main, days=0, ab_root=self.runs))

    def kids(self, *actions):
        h = run_page(self, self.html, [{"expand": "orch"}, *actions])["sess"]   # the runs show once their launcher is opened
        return [m.replace("run-", "") for m in re.findall(r'<tr class="s kid[^"]*" data-id="(run-t-[a-z]+)"', h)], h

    def test_a_nested_list_follows_the_cost_sort_in_both_directions(self):
        order, _ = self.kids({"sort": "cost"})
        self.assertEqual(order, ["t-mid", "t-early", "t-late"], "a first click on Cost sorts descending: $0.75, $0.45, $0.15")
        order, _ = self.kids({"sort": "cost"}, {"sort": "cost"})
        self.assertEqual(order, ["t-late", "t-early", "t-mid"], "a second click flips it, nested rows included")

    def test_a_nested_list_follows_last_active_in_both_directions(self):
        order, _ = self.kids()
        self.assertEqual(order, ["t-late", "t-mid", "t-early"], "the default is Last active, descending: newest first, nested rows too")
        order, _ = self.kids({"sort": "last"})
        self.assertEqual(order, ["t-early", "t-mid", "t-late"], "clicking the header flips it to ascending: oldest first")

    def test_the_default_sort_is_last_active_newest_first_not_cost(self):
        # a cheap session that ran after the expensive orchestrator
        write_log(self.main, "-p/newest.jsonl", [dict(user(50, "later"), sessionId="newest"),
                                                  assistant(51, "claude-opus-4-9", {"input_tokens": 1000, "output_tokens": 100}, "n1", "rn1", sid="newest")])
        html = b.render(b.collect(self.main, days=0, ab_root=self.runs))
        def tops(*actions):
            h = run_page(self, html, list(actions))["sess"]
            return [m for m in re.findall(r'<tr class="s[^"]*" data-id="([^"]+)"', h) if m in ("newest", "orch", "s1")]
        self.assertEqual(tops()[0], "newest", "newest first by default, although it is the cheapest")
        self.assertEqual(tops({"sort": "cost"})[0], "orch", "sorting by Cost is still one click away")
        out = run_page(self, html, [])
        self.assertRegex(out["sess"], r'<th data-k="last"[^>]*aria-sort="descending"', "the Last active header carries the descending arrow")
        self.assertNotRegex(out["sess"], r'<th data-k="cost"[^>]*aria-sort')

    def test_the_orchestrator_stays_above_its_nested_rows_in_every_order(self):
        for actions in ([], [{"sort": "cost"}], [{"sort": "last"}], [{"sort": "last"}, {"sort": "last"}]):
            with self.subTest(actions=actions):
                order, h = self.kids(*actions)
                self.assertLess(h.index('data-id="orch"'), h.index('data-id="run-t-%s"' % order[0].split("t-")[1]))
                self.assertEqual(len(order), 3)

    def test_runs_with_the_same_value_keep_the_order_they_started(self):
        self.launcher(*["auto-mode/ab-docker/run-ab.zsh solve %s m ~/p main ~/b.md" % n for n in ("u-a", "u-b")], sid="orch2", start=40)
        for name, minute in (("u-a", 45), ("u-b", 50)):
            self.run_session(name, [(ts(minute - 1), ts(minute + 1), "solve", 0, "claude-opus-4-9", "abc1234", "headless;exit=0")], minute=minute)
        html = b.render(b.collect(self.main, days=0, ab_root=self.runs))
        h = run_page(self, html, [{"expand": "orch2"}, {"sort": "cost"}, {"sort": "cost"}])["sess"]
        kids = re.findall(r'<tr class="s kid[^"]*" data-id="run-(u-[ab])"', h)
        self.assertEqual(kids, ["u-a", "u-b"], "equal cost either way, so a tie is not shuffled by the direction")


class RunSessions(NestingBase):
    """A run's session is nearly always one prompt, which would only repeat its row, so it shows no task count and opens to the
    individual model calls it made instead. One with several tasks keeps its count and opens to them."""
    def setUp(self):
        super().setUp()
        self.launcher(*["auto-mode/ab-docker/run-ab.zsh solve %s m ~/p main ~/b.md" % n for n in ("no-task", "one-task", "three-tasks", "many-calls")])
        window = [(ts(0), ts(40), "solve", 0, "claude-opus-4-9", "abc1234", "headless;exit=0")]

        def log(name, recs):
            # a real session log is named after its session id, which is how a log's tasks find their session
            self.make_run(name, rows=window)
            write_log(Path(self.runs) / (name + ".session"), "-work/run-%s.jsonl" % name, recs)
        log("no-task", [assistant(5, "claude-opus-4-9", OPUS_USAGE, "n1", "rn1", sid="run-no-task")])
        log("one-task", [ab_user(5, "do the thing", "run-one-task"),
                         assistant(6, "claude-opus-4-9", OPUS_USAGE, "o1", "ro1", sid="run-one-task")])
        recs = []
        for k, m in enumerate((5, 15, 25)):
            recs += [ab_user(m, "task %d" % (k + 1), "run-three-tasks"), assistant(m + 1, "claude-opus-4-9", OPUS_USAGE, "t%d" % k, "rt%d" % k, sid="run-three-tasks")]
        log("three-tasks", recs)
        # one prompt, three calls: two on opus ($0.75 each) and one on sonnet ($0.45), the middle one a subagent's
        def a(minute, model, mid, *blocks, **kw):
            return with_blocks(assistant(minute, model, OPUS_USAGE, mid, "r" + mid, sid="run-many-calls", **kw), *blocks)
        log("many-calls", [ab_user(5, "go", "run-many-calls"),
                           a(6, "claude-opus-4-9", "m1", THINK), a(6, "claude-opus-4-9", "m1", tool("Bash", command="python -m pytest -q")),
                           a(6, "claude-opus-4-9", "m1", tool("Write", file_path="a.py")),
                           a(8, "claude-sonnet-5-5", "m2", text("checking the plan"), side=True),
                           a(9, "claude-opus-4-9", "m3", tool("Read", file_path="docs/plans/0001-wordfreq.md"))])
        self.data = b.collect(self.main, days=0, ab_root=self.runs)
        self.html = b.render(self.data)

    def page(self, *actions):
        return run_page(self, self.html, [{"expand": "orch"}, *actions])["sess"]   # the runs show once their launcher is opened

    def row(self, h, sid):
        tr = re.search(r'<tr class="s[^"]*" data-id="%s".*?</tr>' % re.escape(sid), h, re.S).group(0)
        return tr, [re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", c)).strip() for c in re.findall(r"<td[^>]*>(.*?)</td>", tr, re.S)]

    def calls(self, h):
        return [[re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", c)).strip() for c in re.findall(r"<td[^>]*>(.*?)</td>", tr, re.S)]
                for tr in re.findall(r'<tr class="t call"[^>]*>.*?</tr>', h, re.S)]

    def test_a_run_session_with_no_task_or_one_task_shows_no_count_but_still_opens(self):
        h = self.page()
        for sid in ("run-no-task", "run-one-task", "run-many-calls"):
            tr, cells = self.row(h, sid)
            self.assertEqual(cells[3], "", sid + ": the Tasks cell is blank, not 1 or 0")
            self.assertIn("tabindex", tr.split(">")[0], "it opens, so it is a control")
        self.assertEqual(self.row(h, "run-many-calls")[1][4], "3", "the Calls count is shown, and now there is something to open to")

    def test_such_a_row_opens_to_its_calls_not_to_a_task_row(self):
        h = self.page({"expand": "run-one-task"})
        self.assertEqual(h.count('<tr class="t"'), 0, "no task row: it would only repeat the session")
        calls = self.calls(h)
        self.assertEqual(len(calls), 1)
        c = calls[0]
        self.assertRegex(c[0], r"^\d\d:\d\d:\d\d$", "the time of the call, to the second")
        self.assertEqual(c[1], "↳ reply", "no tool call and no text: the plain label, never a call number")
        self.assertIn("opus-4-9", c[2])
        self.assertEqual(c[5:9], ["100.0k", "10.0k", "$0.50", "$0.25"], "tokens in and out, and dollars in and out")
        self.assertEqual(c[-1], "$0.75")

    def test_a_session_with_no_user_prompt_opens_to_its_calls_too(self):
        h = self.page({"expand": "run-no-task"})
        self.assertEqual(len(self.calls(h)), 1)
        self.assertNotIn("No task breakdown", h)

    def test_each_call_says_what_it_did_and_a_call_spread_over_lines_is_one_row(self):
        calls = self.calls(self.page({"expand": "run-many-calls", }, {"sort": "last"}))   # one click on Last active: oldest first
        self.assertEqual(len(calls), 3, "the thinking, Bash and Write lines of one call are one row, not three")
        labels = [c[1] for c in calls]
        self.assertEqual(labels, ["↳ Bash: python -m pytest -q (+1 more)", "↳ [subagent] reply: checking the plan", "↳ Read: docs/plans/0001-wordfreq.md"])
        for l in labels:
            self.assertNotRegex(l, r"call \d")

    def test_the_label_carries_the_full_text_as_a_tooltip(self):
        h = self.page({"expand": "run-many-calls"})
        self.assertIn('title="Bash: python -m pytest -q (+1 more)"', h)

    def test_the_calls_follow_the_tables_sort_like_every_other_level(self):
        order = lambda *acts: [c[1] for c in self.calls(self.page({"expand": "run-many-calls"}, *acts))]
        bash, sub, read = "↳ Bash: python -m pytest -q (+1 more)", "↳ [subagent] reply: checking the plan", "↳ Read: docs/plans/0001-wordfreq.md"
        self.assertEqual(order(), [read, sub, bash], "the default is Last active, descending: newest call first")
        self.assertEqual(order({"sort": "last"}), [bash, sub, read], "the arrow flips it: oldest first")
        self.assertEqual(order({"sort": "cost"}), [bash, read, sub], "Cost, descending; equal costs keep the order they were made")
        self.assertEqual(order({"sort": "cost"}, {"sort": "cost"}), [sub, bash, read], "and ascending")

    def test_the_calls_add_up_to_the_session(self):
        h = self.page({"expand": "run-many-calls"})
        calls = self.calls(h)
        self.assertEqual(sorted(c[-1] for c in calls), ["$0.45", "$0.75", "$0.75"])
        _, cells = self.row(h, "run-many-calls")
        self.assertEqual(cells[-1], "$1.95", "the session's cost is the sum of its calls")
        sub = next(c for c in calls if "[subagent]" in c[1])
        self.assertEqual(sub[-2], "$0.45", "a subagent call's cost also sits in the Subagent column")
        self.assertEqual(next(c for c in calls if "Read:" in c[1])[-2], "$0.00")
        self.assertIn("sonnet-5-5", sub[2], "each call keeps its own model")

    def test_a_run_session_with_several_tasks_still_shows_its_count_and_opens_to_them(self):
        h = self.page({"expand": "run-three-tasks"})
        tr, cells = self.row(h, "run-three-tasks")
        self.assertEqual(cells[3], "3")
        self.assertIn(" open", tr.split(">")[0])
        self.assertEqual(h.count('<tr class="t"'), 3, "one row per task")
        self.assertEqual(h.count('<tr class="t call"'), 0, "tasks, not calls")

    def test_an_ordinary_session_with_one_task_is_unchanged(self):
        h = self.page({"expand": "s1"})
        tr, cells = self.row(h, "s1")
        self.assertEqual(cells[3], "1", "the count and the task row stay for sessions that are not runs")
        self.assertIn(" open", tr.split(">")[0])
        self.assertEqual(h.count('<tr class="t"'), 1)
        self.assertEqual(h.count('<tr class="t call"'), 0)

    def test_the_time_on_a_call_or_task_row_is_right_aligned_under_the_dates(self):
        h = self.page({"expand": "run-one-task"}, {"expand": "run-three-tasks"})
        call = re.search(r'<tr class="t call"[^>]*><td class="([^"]*)"', h)
        self.assertIsNotNone(call)
        self.assertIn("r", call.group(1).split(), "a call row's time cell is marked right-aligned")
        task = re.search(r'<tr class="t"><td class="([^"]*)"', h)
        self.assertIn("r", task.group(1).split(), "so is a task row's, so both kinds line up the same way")
        self.assertRegex(self.html, r"\.cd-table td\.n, \.cd-table th\.n, \.cd-table td\.r \{ text-align: right; \}")
        date = re.search(r'<tr class="s kid[^"]*" data-id="run-one-task"[^>]*><td class="([^"]*)"', h).group(1)
        self.assertNotIn("r", date.split(), "the dates above stay as they were: only the time rows move")

    def raw_page(self, *actions):
        return run_page(self, b.render({**self.data, "raw": True}), [{"expand": "orch"}, *actions])["sess"]   # as the server renders it

    def test_a_served_page_links_each_run_session_to_its_raw_log(self):
        h = self.raw_page({"expand": "run-one-task"})
        tr, cells = self.row(h, "run-one-task")
        self.assertRegex(tr, r'<a class="cd-raw" href="/raw/run-one-task" target="_blank" rel="noopener" title="[^"]*masked[^"]*">raw ↗</a>')
        call = re.search(r'<tr class="t call"[^>]*><td[^>]*><a class="cd-rawt" href="/raw/([^"]+)" target="_blank" rel="noopener"[^>]*>(\d\d:\d\d:\d\d)</a>', h)
        self.assertIsNotNone(call, "the time on a call row is the link")
        self.assertEqual(call.group(1), "run-one-task", "to that call's own session")

    def test_a_saved_page_and_ordinary_sessions_have_no_raw_links(self):
        self.assertNotIn("/raw/", self.page({"expand": "run-one-task"}), "a saved snapshot has no server to link to")
        h = self.raw_page({"expand": "s1"})
        self.assertNotIn("/raw/s1", h, "only run sessions have a raw log to serve")
        self.assertNotIn("/raw/orch", h)

    def test_clicking_a_link_does_not_open_or_close_the_row(self):
        h = self.raw_page({"clickLink": "run-one-task"})
        self.assertNotRegex(h, r'<tr class="s kid open" data-id="run-one-task"', "a link opens the log, not the row")
        h = self.raw_page({"expand": "run-one-task"})
        self.assertRegex(h, r'<tr class="s kid open" data-id="run-one-task"', "(a click elsewhere on the row still does)")
        h = self.raw_page({"expand": "run-one-task"}, {"clickLink": "run-one-task"})
        self.assertRegex(h, r'<tr class="s kid open" data-id="run-one-task"', "and a link click does not close it")

    def test_call_lists_are_in_the_data_for_run_sessions_only(self):
        rows = {r["id"]: r for r in self.data["sessions"]}
        for sid in ("run-no-task", "run-one-task", "run-three-tasks", "run-many-calls"):
            r = rows[sid]
            self.assertEqual(len(r["call_list"]), r["calls"], "one entry per call")
            self.assertAlmostEqual(sum(c["cost"] for c in r["call_list"]), r["cost"], places=3)
            self.assertEqual([c["ts"] for c in r["call_list"]], sorted(c["ts"] for c in r["call_list"]))
        for sid in ("orch", "s1"):
            self.assertNotIn("call_list", rows[sid], "ordinary sessions are not given a call list: it would more than double the page")
        first = rows["run-many-calls"]["call_list"][0]
        self.assertEqual(sorted(first), ["cost", "effort", "in_cost", "in_tok", "model", "out_cost", "out_tok", "sub", "ts", "what"])
        self.assertEqual((first["in_tok"], first["out_tok"], first["cost"]), (100000, 10000, 0.75))
        self.assertEqual(first["what"], "Bash: python -m pytest -q (+1 more)")


class CallLabels(NestingBase):
    """What a call did, derived from the content blocks of the log lines that make up that call."""
    def label(self, *blocks, split=False):
        self.launcher("auto-mode/ab-docker/run-ab.zsh solve lab-run m ~/p main ~/b.md")
        recs = [ab_user(5, "go", "run-lab-run")]
        chunks = [[b] for b in blocks] if split else [list(blocks)]
        for blk in chunks:
            recs.append(with_blocks(assistant(6, "claude-opus-4-9", OPUS_USAGE, "l1", "rl1", sid="run-lab-run"), *blk))
        self.make_run("lab-run", rows=[(ts(0), ts(40), "solve", 0, "claude-opus-4-9", "abc1234", "headless;exit=0")])
        write_log(Path(self.runs) / "lab-run.session", "-work/run-lab-run.jsonl", recs)
        rows = {r["id"]: r for r in b.collect(self.main, days=0, ab_root=self.runs)["sessions"]}
        self.assertEqual(len(rows["run-lab-run"]["call_list"]), 1, "however many lines it took, one call")
        return rows["run-lab-run"]["call_list"][0]["what"]

    def test_a_tool_call_is_its_name_and_its_main_argument(self):
        self.assertEqual(self.label(tool("Bash", command="git status --short")), "Bash: git status --short")
        self.assertEqual(self.label(tool("Read", file_path="docs/plans/0001-wordfreq.md")), "Read: docs/plans/0001-wordfreq.md")
        self.assertEqual(self.label(tool("Edit", file_path="wordfreq.py", old_string="a", new_string="b")), "Edit: wordfreq.py")
        self.assertEqual(self.label(tool("Grep", pattern="def top_words")), "Grep: def top_words")

    def test_a_tool_with_no_known_argument_is_just_its_name(self):
        self.assertEqual(self.label(tool("TodoWrite", todos=[1, 2])), "TodoWrite")

    def test_several_tools_in_one_call_show_the_first_and_count_the_rest(self):
        self.assertEqual(self.label(tool("Bash", command="ls"), tool("Write", file_path="a"), tool("Write", file_path="b")), "Bash: ls (+2 more)")

    def test_lines_of_one_call_are_merged_so_a_tool_that_follows_thinking_is_not_lost(self):
        self.assertEqual(self.label(THINK, tool("Bash", command="pytest -q"), split=True), "Bash: pytest -q")

    def test_a_reply_with_no_tool_shows_the_start_of_its_text(self):
        self.assertEqual(self.label(text("All three findings are fixed.")), "reply: All three findings are fixed.")

    def test_a_call_that_only_thought_says_so(self):
        self.assertEqual(self.label(THINK), "thinking")

    def test_a_tool_wins_over_text_in_the_same_call(self):
        self.assertEqual(self.label(text("Let me check."), tool("Bash", command="ls")), "Bash: ls")

    def test_a_long_command_is_cut_to_one_line_and_newlines_are_flattened(self):
        w = self.label(tool("Bash", command="python3 - <<'EOF'\nimport re\n" + "x" * 200))
        self.assertNotIn("\n", w)
        self.assertTrue(w.startswith("Bash: python3 - <<'EOF' import re"))
        self.assertLessEqual(len(w), len("Bash: ") + 70)
        self.assertTrue(w.endswith("…"))

    def test_a_secret_in_a_command_never_reaches_the_page(self):
        w = self.label(tool("Bash", command="ANTHROPIC_API_KEY=sk-ant-api03-ABCDEF123456 python run.py"))
        self.assertNotIn("sk-ant", w)
        self.assertIn("[secret]", w)
        w = self.label(tool("Bash", command="curl -H 'Authorization: token ghp_abcdefghijklmnopqrstuvwxyz0123' x"))
        self.assertNotIn("ghp_", w)


if __name__ == "__main__":
    unittest.main()
