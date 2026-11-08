"""Unit tests for the docs hub's counting and ordering.

Run from the plugin repo root:  python3 -m unittest discover -s docs-hub/tests -v

Covers the checklist counting rule (obsolete, dropped and deferred tasks are out of the count), plan order (inserted numbers sit between their
neighbours), the archived flag, and the headline tile's math, which lives in the page template's JavaScript and is run under node.
"""
import datetime
import json
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

PLUGIN = Path(__file__).resolve().parents[1] / "plugins" / "docs-hub"
sys.path.insert(0, str(PLUGIN / "scripts"))
import build_hub as b  # noqa: E402


def write(root, rel, text):
    p = Path(root) / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding="utf-8")


TODO = """# TODO

## 0001 Alpha

Source plan: [0001-alpha.md](0001-alpha.md)

- [x] done task
- [ ] open task
- [x] ~~old idea~~ — obsolete: replaced by the new pipeline
- [ ] ~~moved task~~ — deferred to [plan 0003](0003-gamma.md)
- [x] ~~dropped task~~ — dropped for William

## 00011 Beta

Source plan: [00011-beta.md](00011-beta.md)

- [x] one
- [ ] two

## 0003 Gamma

Source plan: [0003-gamma.md](0003-gamma.md)

- [ ] moved task, now here

## 0002 Delta archived but still has a section

Source plan: [archive/0002-delta.md](archive/0002-delta.md)

- [x] finished
- [x] finished too
"""


def make_docs(root):
    write(root, "plans/TODO.md", TODO)
    for name, title in (("0001-alpha", "Alpha"), ("00011-beta", "Beta"), ("0003-gamma", "Gamma")):
        write(root, "plans/%s.md" % name, "---\nstatus: active\ndate: 2026-11-07\n---\n\n# %s Implementation Plan\n\n- [ ] x\n" % title)
    write(root, "plans/archive/0002-delta.md", "---\nstatus: archived\ndate: 2026-11-07\n---\n\n# Delta Implementation Plan\n\n- [x] a\n- [x] b\n")
    # an archived plan with no TODO section: its own checklist is what counts (one done, one struck-through obsolete, one deferred, one open)
    write(root, "plans/archive/0004-epsilon.md",
          "---\nstatus: archived\ndate: 2026-11-07\n---\n\n# Epsilon Implementation Plan\n\n"
          "- [x] real\n- [x] ~~gone~~ — obsolete: nope\n- [ ] ~~later~~ — deferred to plan 0003\n- [ ] still open\n")
    for d in ("adr", "specs", "process", "investigate"):
        (Path(root) / d).mkdir(exist_ok=True)


class SkipKind(unittest.TestCase):
    def test_a_struck_task_with_a_keyword_after_it_is_skipped(self):
        self.assertEqual(b.skip_kind("~~Task~~ — obsolete: why"), "obsolete")
        self.assertEqual(b.skip_kind("~~Task~~ — deferred to [plan 0018](x.md)"), "deferred")
        self.assertEqual(b.skip_kind("~~Task~~ — dropped for William"), "dropped")
        self.assertEqual(b.skip_kind("~~Task~~ - Obsolete"), "obsolete")                    # case and a plain hyphen

    def test_ordinary_tasks_are_not_skipped(self):
        self.assertEqual(b.skip_kind("plain task"), "")
        self.assertEqual(b.skip_kind("Done task _note: obsolete idea_"), "")                # the word without a strike-through
        self.assertEqual(b.skip_kind("~~struck only~~ no keyword"), "")                     # a strike-through without the keyword


class PlanOrder(unittest.TestCase):
    def test_inserted_numbers_sit_between_their_neighbours(self):
        ids = ["0002", "00012", "0001", "00011", "0010", "00013"]
        self.assertEqual(sorted(ids, key=b.plan_order), ["0001", "00011", "00012", "00013", "0002", "0010"])

    def test_unnumbered_plans_keep_their_order_after_the_numbered_ones(self):
        ids = ["zebra", "0002", "apple", "0001"]
        self.assertEqual(sorted(ids, key=b.plan_order), ["0001", "0002", "zebra", "apple"])


class Counting(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp()
        make_docs(cls.tmp)
        cls.data = b.collect(Path(cls.tmp))
        cls.rows = {p["id"]: p for p in cls.data["plans"]}
        cls.tasks = [w for w in cls.data["work"] if w["kind"] == "task"]

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def test_plans_are_in_number_order(self):
        self.assertEqual([p["id"] for p in self.data["plans"]], ["0001", "00011", "0002", "0003", "0004"])

    def test_obsolete_dropped_and_deferred_tasks_are_left_out_of_a_plans_count(self):
        a = self.rows["0001"]                                    # 5 items: 1 done, 1 open, 3 struck (obsolete, deferred, dropped)
        self.assertEqual((a["done"], a["open"], a["total"]), (1, 1, 2))

    def test_a_deferred_task_is_counted_only_in_the_plan_it_moved_to(self):
        self.assertEqual(self.rows["0003"]["total"], 1)           # its own open task; the deferred copy in 0001 is not counted twice

    def test_struck_tasks_are_marked_skip_and_the_rest_are_not(self):
        marks = {t["text"][:12]: t.get("skip", "") for t in self.tasks if t["plan"] == "0001"}
        self.assertEqual(sorted(v for v in marks.values() if v), ["deferred", "dropped", "obsolete"])
        self.assertEqual(len([v for v in marks.values() if not v]), 2)

    def test_an_archived_plan_with_a_todo_section_has_its_tasks_flagged(self):
        flagged = [t for t in self.tasks if t["plan"] == "0002"]
        self.assertEqual(len(flagged), 2)
        self.assertTrue(all(t.get("archived") for t in flagged))
        self.assertFalse(any(t.get("archived") for t in self.tasks if t["plan"] != "0002"))

    def test_an_archived_plan_with_no_todo_section_counts_its_own_checklist_by_the_same_rule(self):
        e = self.rows["0004"]                                    # 4 items: 1 done, 1 open, 2 struck
        self.assertEqual((e["kind"], e["done"], e["open"], e["total"]), ("archived", 1, 1, 2))

    def test_every_plan_row_carries_its_file_path_so_an_archived_plan_can_be_linked(self):
        self.assertEqual(self.rows["0004"]["path"], "plans/archive/0004-epsilon.md")
        self.assertEqual(self.rows["0001"]["path"], "plans/0001-alpha.md")


SYNC_TODO = """# TODO

## 0001 Alpha

Source plan: [0001-alpha.md](0001-alpha.md)

- [x] one
- [x] two
- [ ] three

## 0002 Beta

Source plan: [0002-beta.md](0002-beta.md)

- [x] one
- [ ] ~~two~~ — deferred to [plan 0001](0001-alpha.md)

## Next steps

### 0001-alpha.md

1. Monday 2026-11-02: check the first run.
2. On or after 2026-11-09 raise the minimum to 1.
3. Decide the owner order (no date).
4. Ran 2026-11-02, check again 2026-11-12.
"""


def make_sync_docs(root, alpha_checks):
    write(root, "plans/TODO.md", SYNC_TODO)
    write(root, "plans/0001-alpha.md", "---\nstatus: active\ndate: 2026-11-08\n---\n\n# Alpha Implementation Plan\n\n" + alpha_checks)
    write(root, "plans/0002-beta.md", "---\nstatus: active\ndate: 2026-11-08\n---\n\n# Beta Implementation Plan\n\n- [x] one\n- [ ] ~~two~~ — deferred to plan 0001\n")
    for d in ("adr", "specs", "process", "investigate"):
        (Path(root) / d).mkdir(exist_ok=True)


class Sync(unittest.TestCase):
    """plans/TODO.md mirrors each plan file; the hub says where it does not."""

    def collect(self, alpha_checks, today=datetime.date(2026, 11, 8)):
        tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, tmp, ignore_errors=True)
        make_sync_docs(tmp, alpha_checks)
        data = b.collect(Path(tmp), today=today)
        return data, {p["id"]: p for p in data["plans"]}

    def test_a_section_that_matches_its_plan_file_has_no_drift(self):
        data, rows = self.collect("- [x] one\n- [x] two\n- [ ] three\n")
        self.assertEqual(rows["0001"]["drift"], "")
        self.assertEqual(rows["0002"]["drift"], "")             # obsolete, dropped and deferred tasks are left out of both counts
        self.assertEqual(data["sync"]["drift"], [])

    def test_a_section_that_lags_the_plan_file_is_flagged_with_both_counts(self):
        data, rows = self.collect("- [x] one\n- [x] two\n- [x] three\n")        # the plan file finished a task; TODO.md did not
        self.assertEqual(rows["0001"]["drift"], "plan file 3 of 3 done, TODO.md section 2 of 3")
        self.assertEqual(data["sync"]["drift"], ["0001"])

    def test_a_task_missing_from_the_section_is_flagged(self):
        _, rows = self.collect("- [x] one\n- [x] two\n- [ ] three\n- [ ] four\n")
        self.assertIn("2 of 4", rows["0001"]["drift"])

    def test_an_archived_plan_is_not_compared(self):
        tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, tmp, ignore_errors=True)
        write(tmp, "plans/TODO.md", "# TODO\n\n## 0002 Beta\n\n_Archived 2026-11-08_\n\n- [x] kept line\n")
        write(tmp, "plans/archive/0002-beta.md", "---\nstatus: archived\ndate: 2026-11-08\n---\n\n# Beta Implementation Plan\n\n- [x] a\n- [x] b\n- [x] c\n")
        for d in ("adr", "specs", "process", "investigate"):
            (Path(tmp) / d).mkdir(exist_ok=True)
        data = b.collect(Path(tmp), today=datetime.date(2026, 11, 8))
        self.assertEqual(data["sync"]["drift"], [])

    def test_a_next_step_whose_dates_have_all_passed_is_stale(self):
        data, _ = self.collect("- [x] one\n- [x] two\n- [ ] three\n")
        stale = data["sync"]["stale_steps"]
        self.assertEqual(len(stale), 1)
        self.assertTrue(stale[0].startswith("0001-alpha.md: Monday 2026-11-02"))

    def test_a_next_step_with_a_future_date_or_none_is_not_stale(self):
        data, _ = self.collect("- [x] one\n- [x] two\n- [ ] three\n")
        text = " ".join(data["sync"]["stale_steps"])
        self.assertNotIn("2026-11-09", text)                    # still ahead
        self.assertNotIn("owner order", text)                   # no date
        self.assertNotIn("check again 2026-11-12", text)        # the latest date it names is still ahead

    def test_the_same_steps_are_not_stale_before_their_date(self):
        data, _ = self.collect("- [x] one\n- [x] two\n- [ ] three\n", today=datetime.date(2026, 11, 1))
        self.assertEqual(data["sync"]["stale_steps"], [])


@unittest.skipUnless(shutil.which("node"), "node is needed to run the page's tile math")
class TileMath(unittest.TestCase):
    """The headline tile is computed in the template's JavaScript; run that function on the real data."""

    @classmethod
    def setUpClass(cls):
        src = (PLUGIN / "assets" / "template.html").read_text(encoding="utf-8")
        m = re.search(r"(const live = .*?)\nfunction shortTitle", src, re.S)
        assert m, "totals() not found in the template"
        cls.js = m.group(1)

    def totals(self, work, plans, show_archived=False):
        prog = ("const st = {showArchived: %s}; const D = {work: %s, plans: %s, adrs: [], invs: []};\n%s\nconsole.log(JSON.stringify(totals()));"
                % ("true" if show_archived else "false", json.dumps(work), json.dumps(plans), self.js))
        out = subprocess.run(["node", "-e", prog], capture_output=True, text=True, check=True).stdout
        return json.loads(out)

    @staticmethod
    def task(plan, done, **kw):
        return dict({"kind": "task", "plan": plan, "done": done}, **kw)

    def test_the_headline_counts_active_tasks_only(self):
        work = [self.task("a", True), self.task("a", False), self.task("a", True, skip="obsolete"), self.task("a", False, skip="deferred"),
                self.task("z", True, archived=True)]
        t = self.totals(work, [])
        self.assertEqual((t["todo_done"], t["todo_total"]), (1, 2))
        self.assertAlmostEqual(t["pct_done"], 0.5)

    def test_the_second_line_adds_the_archived_plans_checklists(self):
        work = [self.task("a", True), self.task("a", False), self.task("a", False), self.task("a", False)]       # 1 of 4 active
        plans = [{"id": "z", "kind": "archived", "done": 3, "total": 4}]                                         # 3 of 4 archived
        t = self.totals(work, plans)
        self.assertAlmostEqual(t["pct_done"], 0.25)
        self.assertEqual(t["archived_n"], 1)
        self.assertAlmostEqual(t["pct_all"], 4 / 8)                                                              # (1 + 3) of (4 + 4)

    def test_the_second_line_equals_the_headline_when_nothing_is_archived(self):
        t = self.totals([self.task("a", True), self.task("a", False)], [])
        self.assertEqual(t["archived_n"], 0)
        self.assertAlmostEqual(t["pct_all"], t["pct_done"])

    def test_ticking_archived_does_not_change_the_totals(self):
        work = [self.task("a", True), self.task("a", False)]
        plans = [{"id": "z", "kind": "archived", "done": 3, "total": 4}]
        self.assertEqual(self.totals(work, plans, False)["pct_done"], self.totals(work, plans, True)["pct_done"])

    def test_no_division_by_zero_with_no_tasks(self):
        t = self.totals([], [])
        self.assertEqual((t["pct_done"], t["pct_all"]), (0, 0))


if __name__ == "__main__":
    unittest.main()
