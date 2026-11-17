"""Tests for putting a subagent's cost on the task (turn) that launched it.

Run from the plugin repo root:  python3 -m unittest discover -s cost-dashboard/tests -v

A subagent's log is its own file, <session>/subagents/agent-X.jsonl, with agent-X.meta.json beside it naming the tool call that
launched it (toolUseId) and its agent type. Before, that cost showed only on the session row; every task row said $0.00 of subagent
cost, so the rows did not add up to the session. Now the cost lands on the task whose assistant message made the Agent tool call,
and the task lists each subagent by type and model.
"""
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_build_dashboard import (  # noqa: E402
    HAIKU_COST, HAIKU_USAGE, OPUS_COST, OPUS_USAGE, Base, assistant, user, write_log)

import build_dashboard as b  # noqa: E402


def agent_call(minutes, tool_id, msg_id="m1", req="r1"):
    """An assistant message (Opus, the orchestrator) whose content is one Agent tool call."""
    rec = assistant(minutes, "claude-opus-4-9", OPUS_USAGE, msg_id, req, sid="s1")
    rec["message"]["content"] = [{"type": "tool_use", "id": tool_id, "name": "Agent", "input": {"subagent_type": "hard-solver", "prompt": "do it"}}]
    return rec


def write_session(root, with_meta=True, tool_id="toolu_A"):
    """Two tasks in one session: the first launches a Haiku subagent, the second is a plain follow-up."""
    write_log(root, "proj/s1.jsonl", [
        user(0, "build the thing"),
        agent_call(1, tool_id, "m1", "r1"),
        user(5, "<task-notification> the agent finished"),
        assistant(6, "claude-opus-4-9", OPUS_USAGE, "m2", "r2", sid="s1"),
    ])
    write_log(root, "proj/s1/subagents/agent-x.jsonl", [
        assistant(2, "claude-haiku-4-9", HAIKU_USAGE, "sa1", "rsa1", side=True, sid="s1"),
    ])
    if with_meta:
        Path(root, "proj/s1/subagents/agent-x.meta.json").write_text(json.dumps({"agentType": "hard-solver", "toolUseId": tool_id}))


class SubagentRows(Base):
    def test_subagent_cost_lands_on_the_task_that_launched_it(self):
        write_session(self.root)
        s = self.only_session()
        turns = sorted(s["turns"], key=lambda t: t["ts"])
        self.assertEqual(len(turns), 2)
        first, second = turns
        self.assertAlmostEqual(first["sub_cost"], HAIKU_COST, places=4)
        self.assertAlmostEqual(first["cost"], OPUS_COST + HAIKU_COST, places=4)
        self.assertEqual(first["subs"], [{"agent": "hard-solver", "model": "claude-haiku-4-9", "cost": round(HAIKU_COST, 4)}])
        self.assertAlmostEqual(second["sub_cost"], 0.0, places=4)
        self.assertEqual(second["subs"], [])

    def test_task_rows_now_add_up_to_the_session(self):
        write_session(self.root)
        s = self.only_session()
        self.assertAlmostEqual(sum(t["cost"] for t in s["turns"]), s["cost"], places=4)
        self.assertAlmostEqual(s["cost"], 2 * OPUS_COST + HAIKU_COST, places=4)
        self.assertAlmostEqual(s["sub_cost"], HAIKU_COST, places=4)      # the session figure is unchanged

    def test_without_a_meta_file_the_cost_stays_on_the_session_only(self):
        write_session(self.root, with_meta=False)
        s = self.only_session()
        self.assertAlmostEqual(s["sub_cost"], HAIKU_COST, places=4)
        self.assertAlmostEqual(sum(t["cost"] for t in s["turns"]), 2 * OPUS_COST, places=4)
        self.assertTrue(all(t["subs"] == [] for t in s["turns"]))

    def test_a_meta_file_naming_an_unknown_tool_call_is_ignored(self):
        write_session(self.root, tool_id="toolu_A")
        Path(self.root, "proj/s1/subagents/agent-x.meta.json").write_text(json.dumps({"agentType": "hard-solver", "toolUseId": "toolu_NOPE"}))
        s = self.only_session()
        self.assertAlmostEqual(s["sub_cost"], HAIKU_COST, places=4)
        self.assertAlmostEqual(sum(t["cost"] for t in s["turns"]), 2 * OPUS_COST, places=4)

    def test_a_broken_meta_file_does_not_break_the_build(self):
        write_session(self.root)
        Path(self.root, "proj/s1/subagents/agent-x.meta.json").write_text("{not json")
        s = self.only_session()
        self.assertAlmostEqual(s["cost"], 2 * OPUS_COST + HAIKU_COST, places=4)

    def test_two_subagents_on_two_tasks_each_keep_their_own_cost(self):
        write_log(self.root, "proj/s1.jsonl", [
            user(0, "first"), agent_call(1, "toolu_A", "m1", "r1"),
            user(5, "second"), agent_call(6, "toolu_B", "m2", "r2"),
        ])
        write_log(self.root, "proj/s1/subagents/agent-a.jsonl", [assistant(2, "claude-haiku-4-9", HAIKU_USAGE, "sa1", "ra1", side=True, sid="s1")])
        write_log(self.root, "proj/s1/subagents/agent-b.jsonl", [assistant(7, "claude-opus-4-9", OPUS_USAGE, "sb1", "rb1", side=True, sid="s1")])
        Path(self.root, "proj/s1/subagents/agent-a.meta.json").write_text(json.dumps({"agentType": "hard-solver", "toolUseId": "toolu_A"}))
        Path(self.root, "proj/s1/subagents/agent-b.meta.json").write_text(json.dumps({"agentType": "reviewer", "toolUseId": "toolu_B"}))
        first, second = sorted(self.only_session()["turns"], key=lambda t: t["ts"])
        self.assertAlmostEqual(first["sub_cost"], HAIKU_COST, places=4)
        self.assertAlmostEqual(second["sub_cost"], OPUS_COST, places=4)
        self.assertEqual(second["subs"][0]["agent"], "reviewer")

    def test_main_logs_are_read_before_subagent_logs(self):
        write_log(self.root, "a/s2/subagents/x.jsonl", [assistant(1, "claude-haiku-4-9", HAIKU_USAGE, "x", "rx", side=True, sid="s2")])
        write_log(self.root, "b/s1.jsonl", [user(0, "hi"), assistant(1, "claude-opus-4-9", OPUS_USAGE, "m1", "r1", sid="s1")])
        files = b.log_files(self.root)
        self.assertEqual([("subagents" in Path(f).parts) for f in files], [False, True])


class CallsUnderTasks(Base):
    """A run with several tasks lists, under each task, the calls it made; a subagent's calls sit under the task that launched it."""

    def test_call_entries_name_their_task_and_a_subagents_calls_follow_the_launching_task(self):
        # an A/B run session lives under <run>.session; the call list is only kept for those
        runs = Path(self.root, "runs")
        sess = runs / "r1.session" / "-work"
        write_log(str(runs), "r1.session/-work/s1.jsonl", [
            user(0, "build the thing"),
            agent_call(1, "toolu_A", "m1", "r1"),
            user(5, "<task-notification> done"),
            assistant(6, "claude-opus-4-9", OPUS_USAGE, "m2", "r2", sid="s1"),
        ])
        write_log(str(runs), "r1.session/-work/s1/subagents/agent-x.jsonl", [assistant(2, "claude-haiku-4-9", HAIKU_USAGE, "sa1", "rsa1", side=True, sid="s1")])
        (sess / "s1" / "subagents" / "agent-x.meta.json").write_text(json.dumps({"agentType": "hard-solver", "toolUseId": "toolu_A"}))
        data = b.collect(str(Path(self.root, "empty")), days=0, ab_root=str(runs))
        run = next(r for r in data["sessions"] if r.get("ab") == "r1")
        by_turn = {}
        for c in run["call_list"]:
            by_turn.setdefault(c["turn"], []).append(c)
        first, second = sorted(t["ts"] for t in run["turns"])
        self.assertEqual(sorted(c["sub"] for c in by_turn[first]), [False, True], "the orchestrator's call and the subagent's call belong to the first task")
        self.assertEqual([c["sub"] for c in by_turn[second]], [False])
        self.assertAlmostEqual(sum(c["cost"] for c in run["call_list"]), run["cost"], places=3)


if __name__ == "__main__":
    unittest.main()
