"""Unit tests for the cost dashboard's log parsing, cost math, and page rendering.

Run from the plugin repo root:  python3 -m unittest discover -s cost-dashboard/tests -v

Every test builds its own synthetic session logs in a temporary directory and prices them with a fixed rate table (not the shipped
pricing.json), so the expected costs below are hand calculations that do not move when the rates are updated:

    sonnet  3 in / 15 out    opus  5 in / 25 out    haiku  1 in / 5 out    fallback  3 / 15
    cache write = 1.25 x input rate, cache read = 0.1 x input rate     (all USD per million tokens)
"""
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest import mock

PLUGIN = Path(__file__).resolve().parents[1] / "plugins" / "cost-dashboard"
sys.path.insert(0, str(PLUGIN / "scripts"))
import build_dashboard as b  # noqa: E402

FIXED_PRICING = {
    "cache_write_multiplier": 1.25,
    "cache_read_multiplier": 0.1,
    "models": {
        "opus": {"input": 5.0, "output": 25.0},
        "sonnet": {"input": 3.0, "output": 15.0},
        "haiku": {"input": 1.0, "output": 5.0},
    },
    "fallback": {"input": 3.0, "output": 15.0},
}

# Hand calculations (USD) for the usage blocks below.
SONNET_BIG = {"input_tokens": 1_000_000, "output_tokens": 100_000,
              "cache_creation_input_tokens": 200_000, "cache_read_input_tokens": 500_000}
SONNET_BIG_COST = 5.40    # 3.00 + 1.50 + 0.75 + 0.15
OPUS_USAGE = {"input_tokens": 100_000, "output_tokens": 10_000}
OPUS_COST = 0.75          # 0.50 + 0.25
HAIKU_USAGE = {"input_tokens": 1_000_000, "output_tokens": 1_000_000}
HAIKU_COST = 6.0          # 1.00 + 5.00
WEIRD_USAGE = {"input_tokens": 1_000_000, "output_tokens": 0}
WEIRD_COST = 3.0          # fallback input rate


def iso(dt):
    return dt.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


NOW = datetime.now(timezone.utc)
T0 = NOW - timedelta(hours=2)


def ts(minutes=0):
    return iso(T0 + timedelta(minutes=minutes))


def user(minutes, text, **extra):
    return {"type": "user", "sessionId": "s1", "timestamp": ts(minutes), "cwd": "/home/u/proj",
            "message": {"content": text}, **extra}


def tool_result(minutes):
    return {"type": "user", "sessionId": "s1", "timestamp": ts(minutes),
            "message": {"content": [{"type": "tool_result", "tool_use_id": "t", "content": "ok"}]}}


def assistant(minutes, model, usage, msg_id="m1", req="r1", side=False, sid="s1", effort=None, per_turn=None, speed=None, tier=None):
    usage = dict(usage)
    if speed is not None:
        usage["speed"] = speed
    if tier is not None:
        usage["service_tier"] = tier
    rec = {"type": "assistant", "sessionId": sid, "timestamp": ts(minutes), "cwd": "/home/u/proj",
           "isSidechain": side, "message": {"model": model, "usage": usage}}
    if effort is not None:
        rec["effort"] = effort
    if per_turn is not None:
        rec["perTurnEffort"] = per_turn
    if msg_id is not None:
        rec["message"]["id"] = msg_id
        rec["requestId"] = req
    return rec


def write_log(root, rel, records, raw_tail=""):
    p = Path(root) / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text("\n".join(json.dumps(r) for r in records) + "\n" + raw_tail, encoding="utf-8")
    return p


class Base(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = self._tmp.name
        patcher = mock.patch.object(b, "PRICING", FIXED_PRICING)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.addCleanup(self._tmp.cleanup)

    def build(self, **kw):
        kw.setdefault("days", 0)
        return b.collect(self.root, **kw)

    def only_session(self, **kw):
        data = self.build(**kw)
        self.assertEqual(len(data["sessions"]), 1, data["sessions"])
        return data["sessions"][0]


class CostMath(Base):
    def test_every_token_type_is_priced(self):
        self.assertAlmostEqual(b.cost_of("claude-sonnet-5-5", SONNET_BIG), SONNET_BIG_COST, places=9)

    def test_models_match_by_substring_of_the_name(self):
        self.assertAlmostEqual(b.cost_of("claude-opus-4-9", OPUS_USAGE), OPUS_COST, places=9)
        self.assertAlmostEqual(b.cost_of("claude-haiku-4-5", HAIKU_USAGE), HAIKU_COST, places=9)

    def test_unknown_model_uses_the_fallback_and_is_flagged(self):
        b.UNPRICED.clear()
        self.assertAlmostEqual(b.cost_of("weird-model-1", WEIRD_USAGE), WEIRD_COST, places=9)
        self.assertIn("weird-model-1", b.UNPRICED)

    def test_missing_and_null_token_fields_count_as_zero(self):
        self.assertEqual(b.cost_of("claude-sonnet-5-5", {}), 0.0)
        self.assertEqual(b.cost_of("claude-sonnet-5-5", {"input_tokens": None, "output_tokens": None}), 0.0)

    def test_unpriced_flag_resets_on_each_collect(self):
        write_log(self.root, "-p/s1.jsonl", [user(0, "hi"), assistant(1, "weird-model-1", WEIRD_USAGE)])
        self.assertEqual(self.build()["unpriced"], ["weird-model-1"])
        (Path(self.root) / "-p" / "s1.jsonl").unlink()
        write_log(self.root, "-p/s1.jsonl", [user(0, "hi"), assistant(1, "claude-sonnet-5-5", OPUS_USAGE)])
        self.assertEqual(self.build()["unpriced"], [], "a long-running server must not keep stale flags")

    def test_shipped_pricing_file_has_the_shape_the_code_needs(self):
        pricing = json.loads((PLUGIN / "pricing.json").read_text())
        for key in ("cache_write_multiplier", "cache_read_multiplier", "models", "fallback"):
            self.assertIn(key, pricing)
        for rate in list(pricing["models"].values()) + [pricing["fallback"]]:
            self.assertGreater(rate["input"], 0)
            self.assertGreater(rate["output"], 0)


class Totals(Base):
    """A mixed session whose total is a hand calculation, so the numbers cannot drift unnoticed."""

    def test_session_total_and_model_split_match_the_hand_calculation(self):
        write_log(self.root, "-p/s1.jsonl", [
            user(0, "first"),
            assistant(1, "claude-sonnet-5-5", SONNET_BIG, "m1", "r1"),
            user(5, "second"),
            assistant(6, "claude-opus-4-9", OPUS_USAGE, "m2", "r2"),
            assistant(7, "claude-haiku-4-5", HAIKU_USAGE, "m3", "r3"),
            assistant(8, "weird-model-1", WEIRD_USAGE, "m4", "r4"),
        ])
        s = self.only_session()
        self.assertAlmostEqual(s["cost"], SONNET_BIG_COST + OPUS_COST + HAIKU_COST + WEIRD_COST, places=4)
        self.assertEqual(s["calls"], 4)
        self.assertAlmostEqual(s["models"]["claude-opus-4-9"]["cost"], OPUS_COST, places=4)
        self.assertAlmostEqual(sum(m["cost"] for m in s["models"].values()), s["cost"], places=3)
        self.assertAlmostEqual(sum(s["daily"].values()), s["cost"], places=3)
        self.assertAlmostEqual(sum(t["cost"] for t in s["turns"]), s["cost"], places=3)
        self.assertEqual(s["tokens"]["input"], 1_000_000 + 100_000 + 1_000_000 + 1_000_000)
        self.assertEqual(s["tokens"]["cache_write"], 200_000)
        self.assertEqual(s["tokens"]["cache_read"], 500_000)


class Dedupe(Base):
    def test_streamed_duplicates_count_once_with_the_final_usage(self):
        partial = {"input_tokens": 1_000_000, "output_tokens": 1}
        final = {"input_tokens": 1_000_000, "output_tokens": 100_000}
        write_log(self.root, "-p/s1.jsonl", [
            user(0, "go"),
            assistant(1, "claude-sonnet-5-5", partial, "m1", "r1"),
            assistant(2, "claude-sonnet-5-5", final, "m1", "r1"),
        ])
        s = self.only_session()
        self.assertEqual(s["calls"], 1)
        self.assertAlmostEqual(s["cost"], 3.0 + 1.5, places=4)

    def test_same_message_id_with_a_different_request_is_a_separate_call(self):
        write_log(self.root, "-p/s1.jsonl", [
            user(0, "go"),
            assistant(1, "claude-opus-4-9", OPUS_USAGE, "m1", "r1"),
            assistant(2, "claude-opus-4-9", OPUS_USAGE, "m1", "r2"),
        ])
        self.assertEqual(self.only_session()["calls"], 2)

    def test_records_without_a_message_id_are_never_merged(self):
        write_log(self.root, "-p/s1.jsonl", [
            user(0, "go"),
            assistant(1, "claude-opus-4-9", OPUS_USAGE, msg_id=None),
            assistant(2, "claude-opus-4-9", OPUS_USAGE, msg_id=None),
        ])
        s = self.only_session()
        self.assertEqual(s["calls"], 2)
        self.assertAlmostEqual(s["cost"], 2 * OPUS_COST, places=4)

    def test_synthetic_model_and_usage_less_records_are_skipped(self):
        no_usage = assistant(2, "claude-opus-4-9", OPUS_USAGE, "m2", "r2")
        del no_usage["message"]["usage"]
        write_log(self.root, "-p/s1.jsonl", [
            user(0, "go"),
            assistant(1, "<synthetic>", {"input_tokens": 5, "output_tokens": 5}, "m1", "r1"),
            no_usage,
            assistant(3, "claude-opus-4-9", OPUS_USAGE, "m3", "r3"),
        ])
        s = self.only_session()
        self.assertEqual(s["calls"], 1)
        self.assertNotIn("<synthetic>", s["models"])


class Tasks(Base):
    def test_only_real_human_prompts_start_a_task(self):
        write_log(self.root, "-p/s1.jsonl", [
            user(0, "real prompt"),
            assistant(1, "claude-opus-4-9", OPUS_USAGE, "m1", "r1"),
            tool_result(2),
            user(3, "meta text", isMeta=True),
            user(4, "<command-name>/clear</command-name>"),
            user(5, "<local-command-stdout>x</local-command-stdout>"),
            user(6, "Caveat: the messages below were generated by the user"),
            assistant(7, "claude-opus-4-9", OPUS_USAGE, "m2", "r2"),
        ])
        turns = self.only_session()["turns"]
        self.assertEqual([t["prompt"] for t in turns], ["real prompt"])
        self.assertEqual(turns[0]["calls"], 2, "calls after non-prompt user records still belong to the open task")

    def test_each_prompt_collects_the_calls_until_the_next_prompt(self):
        write_log(self.root, "-p/s1.jsonl", [
            user(0, "one"),
            assistant(1, "claude-opus-4-9", OPUS_USAGE, "m1", "r1"),
            user(2, "two"),
            assistant(3, "claude-opus-4-9", OPUS_USAGE, "m2", "r2"),
            assistant(4, "claude-opus-4-9", OPUS_USAGE, "m3", "r3"),
        ])
        turns = self.only_session()["turns"]
        self.assertEqual([(t["prompt"], t["calls"]) for t in turns], [("one", 1), ("two", 2)])
        self.assertAlmostEqual(turns[1]["cost"], 2 * OPUS_COST, places=4)

    def test_a_prompt_with_no_model_calls_is_dropped(self):
        write_log(self.root, "-p/s1.jsonl", [
            user(0, "answered locally"),
            user(1, "this one is answered"),
            assistant(2, "claude-opus-4-9", OPUS_USAGE, "m1", "r1"),
        ])
        self.assertEqual([t["prompt"] for t in self.only_session()["turns"]], ["this one is answered"])

    def test_prompt_given_as_text_blocks_is_read_and_long_prompts_are_cut(self):
        long_text = "x" * 500
        rec = user(0, None)
        rec["message"]["content"] = [{"type": "text", "text": "line one\nline two " + long_text}]
        write_log(self.root, "-p/s1.jsonl", [rec, assistant(1, "claude-opus-4-9", OPUS_USAGE)])
        prompt = self.only_session()["turns"][0]["prompt"]
        self.assertEqual(len(prompt), 140)
        self.assertNotIn("\n", prompt)

    def test_session_title_is_the_first_prompt_or_a_placeholder(self):
        write_log(self.root, "-p/s1.jsonl", [user(0, "the first one"), assistant(1, "claude-opus-4-9", OPUS_USAGE, "m1", "r1"),
                                             user(2, "later"), assistant(3, "claude-opus-4-9", OPUS_USAGE, "m2", "r2")])
        self.assertEqual(self.only_session()["title"], "the first one")
        write_log(self.root, "-p/s1.jsonl", [assistant(1, "claude-opus-4-9", OPUS_USAGE)])
        self.assertEqual(self.only_session()["title"], "(no prompt found)")


class Subagents(Base):
    def test_sidechain_calls_in_the_main_log_count_as_subagent_cost_on_the_task(self):
        write_log(self.root, "-p/s1.jsonl", [
            user(0, "delegate"),
            assistant(1, "claude-opus-4-9", OPUS_USAGE, "m1", "r1"),
            assistant(2, "claude-haiku-4-5", HAIKU_USAGE, "m2", "r2", side=True),
        ])
        s = self.only_session()
        self.assertAlmostEqual(s["cost"], OPUS_COST + HAIKU_COST, places=4)
        self.assertAlmostEqual(s["sub_cost"], HAIKU_COST, places=4)
        self.assertAlmostEqual(s["turns"][0]["sub_cost"], HAIKU_COST, places=4)

    def test_separate_subagent_file_counts_in_the_session_but_not_in_any_task(self):
        write_log(self.root, "-p/s1.jsonl", [user(0, "delegate"), assistant(1, "claude-opus-4-9", OPUS_USAGE, "m1", "r1")])
        write_log(self.root, "-p/s1/subagents/agent-1.jsonl",
                  [assistant(2, "claude-haiku-4-5", HAIKU_USAGE, "x1", "q1", side=True, sid="ignored")])
        s = self.only_session()
        self.assertEqual(s["id"], "s1", "the subagent file belongs to the session folder it sits in")
        self.assertAlmostEqual(s["cost"], OPUS_COST + HAIKU_COST, places=4)
        self.assertAlmostEqual(s["sub_cost"], HAIKU_COST, places=4)
        self.assertAlmostEqual(s["turns"][0]["cost"], OPUS_COST, places=4,
                               msg="known gap (plan 0004 / 0001 enhancement): subagent-file cost is not tied to the spawning task")


class Filters(Base):
    def setUp(self):
        super().setUp()
        old = T0 - timedelta(days=60)

        def stamp(rec):
            rec["timestamp"] = iso(old)
            return rec
        write_log(self.root, "-alpha/old.jsonl", [stamp(user(0, "old")), stamp(assistant(1, "claude-opus-4-9", OPUS_USAGE, sid="old"))])
        write_log(self.root, "-alpha/new.jsonl", [user(0, "new alpha"), assistant(1, "claude-opus-4-9", OPUS_USAGE, "m9", "r9", sid="new")])
        rec = assistant(1, "claude-opus-4-9", OPUS_USAGE, "m8", "r8", sid="beta1")
        rec["cwd"] = "/work/BetaThing"
        write_log(self.root, "-beta/beta1.jsonl", [rec])

    def ids(self, **kw):
        return sorted(s["id"] for s in b.collect(self.root, **kw)["sessions"])

    def test_days_cutoff_drops_old_sessions_and_zero_keeps_all(self):
        self.assertEqual(self.ids(days=30), ["beta1", "new"])
        self.assertEqual(self.ids(days=0), ["beta1", "new", "old"])

    def test_project_filter_is_a_case_insensitive_substring_of_project_dir_or_cwd(self):
        self.assertEqual(self.ids(days=0, project="ALPHA"), ["new", "old"])
        self.assertEqual(self.ids(days=0, project="betathing"), ["beta1"])
        self.assertEqual(self.ids(days=0, project="no-such-project"), [])

    def test_sessions_are_listed_newest_first(self):
        data = b.collect(self.root, days=0)
        lasts = [s["last"] for s in data["sessions"]]
        self.assertEqual(lasts, sorted(lasts, reverse=True))


class ModelAndEffort(Base):
    """Cost split by model and effort level, read per call from the assistant records. Effort is only ever kept with its model."""

    def mixed_session(self):
        write_log(self.root, "-p/s1.jsonl", [
            user(0, "quick one"),
            assistant(1, "claude-sonnet-5-5", OPUS_USAGE, "m1", "r1", per_turn="low", effort="low"),
            user(5, "hard one"),
            assistant(6, "claude-sonnet-5-5", OPUS_USAGE, "m2", "r2", per_turn="high", effort="low"),
            assistant(7, "claude-opus-4-9", OPUS_USAGE, "m3", "r3", per_turn="high", effort="low"),
            assistant(8, "claude-opus-4-9", HAIKU_USAGE, "m4", "r4", per_turn="medium"),
        ])
        return self.only_session()

    SONNET_OPUS_USAGE_COST = 0.3 + 0.15      # 100k in x 3 + 10k out x 15 per million
    OPUS_HAIKU_USAGE_COST = 5.0 + 25.0       # 1M in x 5 + 1M out x 25 per million

    def test_effort_exists_only_inside_the_model_nest(self):
        s = self.mixed_session()
        self.assertNotIn("effort", s)
        self.assertNotIn("daily_effort", s)
        self.assertNotIn("daily_model", s)
        for t in s["turns"]:
            self.assertNotIn("effort", t)
            self.assertNotIn("models", t)

    def test_per_turn_effort_wins_over_the_session_value(self):
        m = self.mixed_session()["matrix"]
        self.assertEqual(sorted(m["claude-sonnet-5-5"]), ["high", "low"], "call 2 is high although effort says low")
        self.assertEqual(sorted(m["claude-opus-4-9"]), ["high", "medium"])

    def test_effort_falls_back_to_the_session_value_then_to_unknown(self):
        write_log(self.root, "-p/s1.jsonl", [
            user(0, "go"),
            assistant(1, "claude-opus-4-9", OPUS_USAGE, "m1", "r1", effort="High"),     # no perTurnEffort; case is normalised
            assistant(2, "claude-opus-4-9", OPUS_USAGE, "m2", "r2"),                      # neither field
        ])
        self.assertEqual(sorted(self.only_session()["matrix"]["claude-opus-4-9"]), ["high", "unknown"])

    def test_the_same_effort_on_two_models_is_two_separate_entries(self):
        m = self.mixed_session()["matrix"]
        self.assertAlmostEqual(m["claude-sonnet-5-5"]["high"]["cost"], self.SONNET_OPUS_USAGE_COST, places=4)
        self.assertAlmostEqual(m["claude-opus-4-9"]["high"]["cost"], OPUS_COST, places=4)
        self.assertEqual(m["claude-sonnet-5-5"]["low"]["calls"], 1)
        self.assertAlmostEqual(m["claude-opus-4-9"]["medium"]["cost"], self.OPUS_HAIKU_USAGE_COST, places=4)

    def test_an_effort_change_inside_a_session_splits_the_cost(self):
        row = self.mixed_session()["matrix"]["claude-sonnet-5-5"]
        self.assertEqual({k: v["calls"] for k, v in row.items()}, {"low": 1, "high": 1})
        self.assertNotEqual(row["low"]["cost"], 0)

    def test_the_matrix_sums_to_the_session_total_and_to_each_model(self):
        s = self.mixed_session()
        self.assertAlmostEqual(sum(c["cost"] for row in s["matrix"].values() for c in row.values()), s["cost"], places=3)
        for model, row in s["matrix"].items():
            self.assertAlmostEqual(sum(c["cost"] for c in row.values()), s["models"][model]["cost"], places=3)
            self.assertEqual(sum(c["calls"] for c in row.values()), s["models"][model]["calls"])

    def test_each_task_carries_a_model_to_effort_nest(self):
        turns = self.mixed_session()["turns"]
        self.assertEqual({m: sorted(e) for m, e in turns[0]["me"].items()}, {"claude-sonnet-5-5": ["low"]})
        self.assertEqual({m: sorted(e) for m, e in turns[1]["me"].items()},
                         {"claude-sonnet-5-5": ["high"], "claude-opus-4-9": ["high", "medium"]})
        for t in turns:
            self.assertAlmostEqual(sum(c["cost"] for e in t["me"].values() for c in e.values()), t["cost"], places=3)

    def test_per_day_nest_is_model_then_effort_and_sums_to_the_day_total(self):
        s = self.mixed_session()
        for day, total in s["daily"].items():
            self.assertAlmostEqual(sum(c for e in s["daily_me"][day].values() for c in e.values()), total, places=3)
        any_day = next(iter(s["daily_me"].values()))
        self.assertEqual(sorted(any_day), ["claude-opus-4-9", "claude-sonnet-5-5"])

    def test_the_final_streamed_record_decides_the_effort(self):
        write_log(self.root, "-p/s1.jsonl", [
            user(0, "go"),
            assistant(1, "claude-opus-4-9", OPUS_USAGE, "m1", "r1", per_turn="low"),
            assistant(2, "claude-opus-4-9", OPUS_USAGE, "m1", "r1", per_turn="high"),
        ])
        s = self.only_session()
        self.assertEqual(list(s["matrix"]["claude-opus-4-9"]), ["high"])
        self.assertEqual(s["calls"], 1)

    def test_subagent_calls_keep_their_own_model_and_effort(self):
        write_log(self.root, "-p/s1.jsonl", [user(0, "go"), assistant(1, "claude-opus-4-9", OPUS_USAGE, "m1", "r1", per_turn="medium")])
        write_log(self.root, "-p/s1/subagents/a.jsonl", [assistant(2, "claude-haiku-4-5", HAIKU_USAGE, "x1", "q1", side=True, per_turn="low")])
        m = self.only_session()["matrix"]
        self.assertEqual({k: list(v) for k, v in m.items()}, {"claude-opus-4-9": ["medium"], "claude-haiku-4-5": ["low"]})

    def test_non_standard_speed_or_tier_is_flagged_not_guessed(self):
        write_log(self.root, "-p/s1.jsonl", [
            user(0, "go"),
            assistant(1, "claude-opus-4-9", OPUS_USAGE, "m1", "r1", speed="fast", tier="priority"),
            assistant(2, "claude-opus-4-9", OPUS_USAGE, "m2", "r2", speed="standard", tier="standard"),
            assistant(3, "claude-opus-4-9", OPUS_USAGE, "m3", "r3"),
        ])
        data = self.build()
        self.assertEqual(data["speed_flags"], ["service_tier=priority", "speed=fast"])
        self.assertAlmostEqual(data["sessions"][0]["cost"], 3 * OPUS_COST, places=4, msg="flagged calls are priced at the standard rate")

    def test_standard_only_logs_raise_no_flag_and_flags_reset_between_builds(self):
        write_log(self.root, "-p/s1.jsonl", [user(0, "go"), assistant(1, "claude-opus-4-9", OPUS_USAGE, "m1", "r1", speed="fast")])
        self.assertEqual(self.build()["speed_flags"], ["speed=fast"])
        write_log(self.root, "-p/s1.jsonl", [user(0, "go"), assistant(1, "claude-opus-4-9", OPUS_USAGE, "m1", "r1", speed="standard")])
        self.assertEqual(self.build()["speed_flags"], [])

    def test_summary_names_the_cost_at_each_model_and_effort(self):
        self.mixed_session()
        text = b.summary(self.build(), "/x/out.html")
        self.assertIn("By model and effort:", text)
        self.assertIn("claude-opus-4-9 · medium: $30.00 (1 calls)", text)
        self.assertNotRegex(text, r"(?m)^By effort:")


class InAndOut(Base):
    """Tokens and dollars in and out for every model and effort: the figures models are compared on ($ in / $ out per million tokens)."""

    SAME_USAGE = {"input_tokens": 100_000, "output_tokens": 10_000}

    def cell(self, model, usage, effort="medium", **kw):
        write_log(self.root, "-p/s1.jsonl", [user(0, "go"), assistant(1, model, usage, "m1", "r1", per_turn=effort, **kw)])
        return self.only_session()["matrix"][model][effort]

    def test_in_is_input_plus_cache_writes_plus_cache_reads_and_out_is_output(self):
        c = self.cell("claude-sonnet-5-5", SONNET_BIG)
        self.assertEqual((c["in_tok"], c["out_tok"]), (1_000_000 + 200_000 + 500_000, 100_000))

    def test_dollars_in_and_out_match_the_hand_calculation(self):
        c = self.cell("claude-sonnet-5-5", SONNET_BIG)
        self.assertAlmostEqual(c["in_cost"], 3.0 + 0.75 + 0.15, places=4)      # fresh input + cache write + cache read
        self.assertAlmostEqual(c["out_cost"], 1.5, places=4)
        self.assertAlmostEqual(c["cost"], c["in_cost"] + c["out_cost"], places=4)

    def test_the_same_tokens_cost_different_dollars_on_different_models(self):
        sonnet = self.cell("claude-sonnet-5-5", self.SAME_USAGE)
        opus = self.cell("claude-opus-4-9", self.SAME_USAGE)
        self.assertEqual((sonnet["in_tok"], sonnet["out_tok"]), (opus["in_tok"], opus["out_tok"]))
        self.assertAlmostEqual(sonnet["in_cost"], 0.30, places=4); self.assertAlmostEqual(sonnet["out_cost"], 0.15, places=4)
        self.assertAlmostEqual(opus["in_cost"], 0.50, places=4); self.assertAlmostEqual(opus["out_cost"], 0.25, places=4)

    def test_each_effort_keeps_its_own_tokens_and_dollars(self):
        write_log(self.root, "-p/s1.jsonl", [
            user(0, "go"),
            assistant(1, "claude-opus-4-9", self.SAME_USAGE, "m1", "r1", per_turn="low"),
            assistant(2, "claude-opus-4-9", {"input_tokens": 300_000, "output_tokens": 50_000}, "m2", "r2", per_turn="high"),
        ])
        row = self.only_session()["matrix"]["claude-opus-4-9"]
        self.assertEqual((row["low"]["in_tok"], row["low"]["out_tok"]), (100_000, 10_000))
        self.assertEqual((row["high"]["in_tok"], row["high"]["out_tok"]), (300_000, 50_000))
        self.assertAlmostEqual(row["high"]["in_cost"], 1.5, places=4)
        self.assertAlmostEqual(row["high"]["out_cost"], 1.25, places=4)

    def test_cells_add_up_to_the_session_totals(self):
        write_log(self.root, "-p/s1.jsonl", [
            user(0, "go"),
            assistant(1, "claude-sonnet-5-5", SONNET_BIG, "m1", "r1", per_turn="low"),
            assistant(2, "claude-opus-4-9", OPUS_USAGE, "m2", "r2", per_turn="high"),
            assistant(3, "claude-haiku-4-5", HAIKU_USAGE, "m3", "r3", per_turn="medium"),
        ])
        s = self.only_session()
        cells = [c for row in s["matrix"].values() for c in row.values()]
        self.assertAlmostEqual(sum(c["in_cost"] + c["out_cost"] for c in cells), s["cost"], places=3)
        self.assertEqual(sum(c["in_tok"] for c in cells), s["tokens"]["input"] + s["tokens"]["cache_write"] + s["tokens"]["cache_read"])
        self.assertEqual(sum(c["out_tok"] for c in cells), s["tokens"]["output"])
        self.assertAlmostEqual(sum(c["out_cost"] for c in cells), s["parts"]["output"], places=3)
        self.assertAlmostEqual(sum(c["in_cost"] for c in cells), s["parts"]["input"] + s["parts"]["cache_write"] + s["parts"]["cache_read"], places=3)

    def test_each_task_has_the_same_cell_fields(self):
        write_log(self.root, "-p/s1.jsonl", [user(0, "go"), assistant(1, "claude-sonnet-5-5", SONNET_BIG, "m1", "r1", per_turn="low")])
        t = self.only_session()["turns"][0]
        c = t["me"]["claude-sonnet-5-5"]["low"]
        self.assertEqual(sorted(c), ["calls", "cost", "in_cost", "in_tok", "out_cost", "out_tok"])
        self.assertAlmostEqual(c["in_cost"] + c["out_cost"], t["cost"], places=4)

    def test_subagent_calls_count_in_the_cells_with_their_own_model(self):
        write_log(self.root, "-p/s1.jsonl", [user(0, "go"), assistant(1, "claude-opus-4-9", OPUS_USAGE, "m1", "r1")])
        write_log(self.root, "-p/s1/subagents/a.jsonl", [assistant(2, "claude-haiku-4-5", HAIKU_USAGE, "x1", "q1", side=True)])
        m = self.only_session()["matrix"]
        self.assertEqual(m["claude-haiku-4-5"]["unknown"]["in_tok"], 1_000_000)
        self.assertAlmostEqual(m["claude-haiku-4-5"]["unknown"]["out_cost"], 5.0, places=4)


class TokensAndContext(Base):
    """Cost by token type, and the context each call carries."""

    def ctx_log(self, sizes, side=None):
        """A session with one main-thread call per entry of `sizes` (context tokens, sent as cache reads)."""
        recs = [user(0, "go")]
        for i, n in enumerate(sizes):
            recs.append(assistant(1 + i, "claude-sonnet-5-5", {"input_tokens": 0, "output_tokens": 10, "cache_read_input_tokens": n},
                                  "m%d" % i, "r%d" % i))
        if side:
            recs.append(assistant(500, "claude-haiku-4-5", {"input_tokens": side}, "sub", "rs", side=True))
        write_log(self.root, "-p/s1.jsonl", recs)
        return self.only_session()

    def test_cost_by_token_type_matches_the_hand_calculation(self):
        write_log(self.root, "-p/s1.jsonl", [user(0, "go"), assistant(1, "claude-sonnet-5-5", SONNET_BIG)])
        parts = self.only_session()["parts"]
        self.assertEqual(parts, {"input": 3.0, "output": 1.5, "cache_write": 0.75, "cache_read": 0.15})

    def test_token_type_costs_add_up_to_the_session_cost_across_models(self):
        write_log(self.root, "-p/s1.jsonl", [
            user(0, "go"),
            assistant(1, "claude-sonnet-5-5", SONNET_BIG, "m1", "r1"),
            assistant(2, "claude-opus-4-9", OPUS_USAGE, "m2", "r2"),
            assistant(3, "weird-model-1", WEIRD_USAGE, "m3", "r3"),
        ])
        s = self.only_session()
        self.assertAlmostEqual(sum(s["parts"].values()), s["cost"], places=3)

    def test_cost_parts_sum_to_cost_of(self):
        for model, usage in (("claude-sonnet-5-5", SONNET_BIG), ("claude-opus-4-9", OPUS_USAGE), ("x", WEIRD_USAGE), ("x", {})):
            self.assertAlmostEqual(sum(b.cost_parts(model, usage).values()), b.cost_of(model, usage), places=12)

    def test_context_of_a_call_is_fresh_input_plus_cache_writes_plus_cache_reads(self):
        self.assertEqual(b.context_tokens(SONNET_BIG), 1_000_000 + 200_000 + 500_000)
        self.assertEqual(b.context_tokens({"output_tokens": 99}), 0, "output is not context")
        self.assertEqual(b.context_tokens({"input_tokens": None}), 0)

    def test_series_has_one_point_per_main_call_and_the_summary_stats(self):
        c = self.ctx_log([100_000, 200_000, 300_000])["ctx"]
        self.assertEqual(c["series"], [100_000, 200_000, 300_000])
        self.assertEqual((c["calls"], c["avg"], c["peak"], c["last"], c["resets"], c["bucket"]), (3, 200_000, 300_000, 300_000, 0, 1))

    def test_subagent_calls_are_not_part_of_the_main_context_series(self):
        c = self.ctx_log([100_000, 200_000], side=900_000)["ctx"]
        self.assertEqual(c["series"], [100_000, 200_000])
        self.assertEqual(c["peak"], 200_000)

    def test_a_session_with_only_subagent_calls_has_an_empty_series(self):
        write_log(self.root, "-p/s1.jsonl", [user(0, "go"), assistant(1, "claude-haiku-4-5", HAIKU_USAGE, side=True)])
        c = self.only_session()["ctx"]
        self.assertEqual((c["calls"], c["series"], c["peak"], c["resets"]), (0, [], 0, 0))

    def test_a_drop_below_seventy_percent_of_the_previous_call_is_a_reset(self):
        c = self.ctx_log([100_000, 400_000, 270_000, 280_000, 100_000, 120_000])["ctx"]
        # 270k is 67.5% of 400k (reset), 100k is 35.7% of 280k (reset); 280k and 120k are not drops
        self.assertEqual(c["resets"], 2)
        self.assertEqual(c["reset_at"], [2, 4])

    def test_a_small_dip_is_not_a_reset(self):
        self.assertEqual(self.ctx_log([100_000, 300_000, 250_000, 260_000])["ctx"]["resets"], 0)

    def test_long_series_are_shrunk_but_keep_their_peak_and_resets(self):
        sizes = [1000 + i * 10 for i in range(1000)]
        sizes[500] = 5_000_000                 # a spike a naive downsample could skip
        sizes[700] = 10                        # a reset
        c = self.ctx_log(sizes)["ctx"]
        self.assertLessEqual(len(c["series"]), b.MAX_CTX_POINTS)
        self.assertEqual(c["calls"], 1000)
        self.assertEqual(c["peak"], 5_000_000)
        self.assertIn(5_000_000, c["series"])
        self.assertEqual(c["bucket"], -(-1000 // b.MAX_CTX_POINTS))
        self.assertGreaterEqual(c["resets"], 1)
        self.assertTrue(all(0 <= i < len(c["series"]) for i in c["reset_at"]))

    def test_short_series_are_left_whole(self):
        sizes = list(range(1000, 1000 + b.MAX_CTX_POINTS * 1))
        c = b.context_summary(sizes)
        self.assertEqual((len(c["series"]), c["bucket"]), (b.MAX_CTX_POINTS, 1))

    def test_empty_series_summary(self):
        self.assertEqual(b.context_summary([])["series"], [])


CARD_PRICING = {          # the v2 shape of pricing.json, small enough to compute by hand
    "cache_write_multiplier": 1.25, "cache_write_1h_multiplier": 2.0, "cache_read_multiplier": 0.1,
    "models": {
        "alpha-2": {"input": 2.0, "output": 10.0, "cache_read_multiplier": 0.05},
        "alpha": {"input": 2.0, "output": 10.0},
        "beta": {"input": 0.1, "output": 0.5, "tiers": [{"over_tokens": 100_000, "input": 0.5, "output": 2.5}]},
    },
    "fallback": {"input": 3.0, "output": 15.0},
}


class Pricing(Base):
    """Per-model cache-read price, the 5-minute / 1-hour cache-write split, size tiers, and the displayed rate card."""

    def setUp(self):
        super().setUp()
        p = mock.patch.object(b, "PRICING", CARD_PRICING)
        p.start()
        self.addCleanup(p.stop)

    def test_cache_read_price_depends_on_the_model(self):
        reads = {"cache_read_input_tokens": 1_000_000}
        self.assertAlmostEqual(b.cost_of("alpha-2", reads), 2.0 * 0.05, places=9)     # this model's own 0.05x
        self.assertAlmostEqual(b.cost_of("alpha-1", reads), 2.0 * 0.1, places=9)      # no override: the top-level 0.1x

    def test_the_more_specific_key_listed_first_wins(self):
        self.assertEqual(b.price_for("vendor-alpha-2-xyz")["cache_read_multiplier"], 0.05)
        self.assertNotIn("cache_read_multiplier", b.price_for("vendor-alpha-1"))

    def test_one_hour_cache_writes_cost_more_than_five_minute_writes(self):
        five = {"cache_creation_input_tokens": 1_000_000, "cache_creation": {"ephemeral_5m_input_tokens": 1_000_000, "ephemeral_1h_input_tokens": 0}}
        hour = {"cache_creation_input_tokens": 1_000_000, "cache_creation": {"ephemeral_5m_input_tokens": 0, "ephemeral_1h_input_tokens": 1_000_000}}
        mixed = {"cache_creation_input_tokens": 1_000_000, "cache_creation": {"ephemeral_5m_input_tokens": 400_000, "ephemeral_1h_input_tokens": 600_000}}
        self.assertAlmostEqual(b.cost_of("alpha", five), 2.0 * 1.25, places=9)
        self.assertAlmostEqual(b.cost_of("alpha", hour), 2.0 * 2.0, places=9)
        self.assertAlmostEqual(b.cost_of("alpha", mixed), 2.0 * (0.4 * 1.25 + 0.6 * 2.0), places=9)

    def test_writes_without_a_breakdown_count_as_five_minute(self):
        self.assertAlmostEqual(b.cost_of("alpha", {"cache_creation_input_tokens": 1_000_000}), 2.5, places=9)
        self.assertEqual(b.write_split({"cache_creation_input_tokens": 10, "cache_creation": "garbage"}), (10, 0))

    def test_a_breakdown_larger_than_the_total_cannot_make_negative_writes(self):
        w5, w1 = b.write_split({"cache_creation_input_tokens": 100, "cache_creation": {"ephemeral_1h_input_tokens": 500}})
        self.assertEqual((w5, w1), (0, 100))

    def test_a_larger_prompt_switches_to_the_tier_rates_just_over_the_threshold(self):
        at = {"input_tokens": 100_000}
        over = {"input_tokens": 100_001}
        self.assertAlmostEqual(b.cost_of("beta", at), 100_000 * 0.1 / 1e6, places=9)
        self.assertAlmostEqual(b.cost_of("beta", over), 100_001 * 0.5 / 1e6, places=9)
        self.assertAlmostEqual(b.cost_of("beta", {"input_tokens": 1, "output_tokens": 1_000_000, "cache_read_input_tokens": 100_000}),
                               (1 * 0.5 + 1_000_000 * 2.5 + 100_000 * 0.5 * 0.1) / 1e6, places=9, msg="the prompt counts cache reads too")

    def test_an_unmatched_model_is_flagged_and_priced_at_the_fallback(self):
        b.UNPRICED.clear()
        self.assertAlmostEqual(b.cost_of("mystery", {"input_tokens": 1_000_000}), 3.0, places=9)
        self.assertEqual(b.UNPRICED, {"mystery"})

    def test_rate_card_is_per_million_tokens(self):
        card = b.rate_card("alpha-2")
        self.assertEqual(card, {"input": 2.0, "output": 10.0, "cache_write_5m": 2.5, "cache_write_1h": 4.0, "cache_read": 0.1, "read_multiplier": 0.05})
        self.assertEqual(b.rate_card("beta")["tiers"], [{"over_tokens": 100_000, "input": 0.5, "output": 2.5}])

    def test_collect_ships_a_rate_card_for_each_model_seen_and_the_source(self):
        write_log(self.root, "-p/s1.jsonl", [user(0, "go"), assistant(1, "alpha-2", OPUS_USAGE, "m1", "r1"), assistant(2, "beta", OPUS_USAGE, "m2", "r2")])
        data = self.build()
        self.assertEqual(sorted(data["rates"]), ["alpha-2", "beta"])
        self.assertIn("rates_source", data)

    def test_context_tokens_and_cost_are_kept_per_model(self):
        usage = {"input_tokens": 1_000_000, "cache_read_input_tokens": 2_000_000, "output_tokens": 1_000_000}
        write_log(self.root, "-p/s1.jsonl", [user(0, "go"), assistant(1, "alpha-2", usage, "m1", "r1")])
        m = self.only_session()["models"]["alpha-2"]
        self.assertEqual(m["ctx_tokens"], 3_000_000)
        self.assertAlmostEqual(m["ctx_cost"], 2.0 + 2_000_000 * 2.0 * 0.05 / 1e6, places=4, msg="output is not part of context cost")

    def test_one_hour_write_tokens_are_counted_per_session(self):
        u = {"cache_creation_input_tokens": 300, "cache_creation": {"ephemeral_5m_input_tokens": 100, "ephemeral_1h_input_tokens": 200}}
        write_log(self.root, "-p/s1.jsonl", [user(0, "go"), assistant(1, "alpha", u, "m1", "r1")])
        self.assertEqual(self.only_session()["cw1h"], 200)

    def test_a_non_global_inference_geo_is_flagged(self):
        write_log(self.root, "-p/s1.jsonl", [user(0, "go"), assistant(1, "alpha", {**OPUS_USAGE, "inference_geo": "us"}, "m1", "r1"),
                                             assistant(2, "alpha", {**OPUS_USAGE, "inference_geo": "global"}, "m2", "r2")])
        self.assertEqual(self.build()["speed_flags"], ["inference_geo=us"])


class ShippedPricing(unittest.TestCase):
    """Pins the shipped pricing.json to the published rate card it was copied from. When Anthropic changes a price, update pricing.json,
    its `verified` date and this table together; a mismatch means one of them was edited alone."""

    CARD = {   # model id -> (input, output, cache read, cache write 5m, cache write 1h), USD per MTok, from the pricing page on 2026-11-11
        "claude-fable-5-2": (8, 40, 0.20, 10, 16), "claude-mythos-5-2": (8, 40, 0.20, 10, 16),
        "claude-fable-5-1": (10, 50, 0.25, 12.5, 20), "claude-fable-5": (10, 50, 1.0, 12.5, 20),
        "claude-opus-5-5": (4, 20, 0.20, 5, 8), "claude-opus-5": (5, 25, 0.50, 6.25, 10),
        "claude-opus-4-8": (5, 25, 0.50, 6.25, 10), "claude-opus-4-5": (5, 25, 0.50, 6.25, 10),
        "claude-opus-4-1-20250805": (15, 75, 1.50, 18.75, 30), "claude-opus-4-20250514": (15, 75, 1.50, 18.75, 30),
        "claude-sonnet-5-5": (2, 10, 0.10, 2.5, 4), "claude-sonnet-5": (2, 10, 0.20, 2.5, 4),
        "claude-sonnet-4-6": (3, 15, 0.30, 3.75, 6), "claude-sonnet-4-5": (3, 15, 0.30, 3.75, 6),
        "claude-haiku-5-5": (0.10, 0.50, 0.01, 0.125, 0.20), "claude-haiku-4-5": (1, 5, 0.10, 1.25, 2),
    }

    def test_every_model_matches_the_published_card(self):
        for model, (inp, out, read, w5, w1) in self.CARD.items():
            card = b.rate_card(model)
            got = (card["input"], card["output"], card["cache_read"], card["cache_write_5m"], card["cache_write_1h"])
            for g, want in zip(got, (inp, out, read, w5, w1)):
                self.assertAlmostEqual(g, want, places=6, msg="%s: %r vs %r" % (model, got, (inp, out, read, w5, w1)))

    def test_haiku_5_5_charges_more_for_prompts_over_100k(self):
        small = b.cost_of("claude-haiku-5-5", {"input_tokens": 1_000_000 - 900_001})
        self.assertAlmostEqual(small, 99_999 * 0.10 / 1e6, places=9)
        big = b.cost_of("claude-haiku-5-5", {"input_tokens": 200_000, "output_tokens": 1_000_000})
        self.assertAlmostEqual(big, (200_000 * 0.50 + 1_000_000 * 2.50) / 1e6, places=9)
        self.assertAlmostEqual(b.cost_of("claude-haiku-5-5", {"cache_read_input_tokens": 200_000}), 200_000 * 0.05 / 1e6, places=9)

    def test_file_is_stamped_with_its_source_and_check_date(self):
        pricing = json.loads((PLUGIN / "pricing.json").read_text())
        self.assertTrue(pricing["source"].startswith("https://"))
        self.assertRegex(pricing["verified"], r"^\d{4}-\d{2}-\d{2}$")

    def test_unknown_models_are_flagged_not_guessed(self):
        b.UNPRICED.clear()
        b.price_for("claude-some-future-model")
        self.assertEqual(b.UNPRICED, {"claude-some-future-model"})


class SessionsTab(Base):
    """The Sessions table: paging, a column order that puts the prompt first, a no-wrap date, and a prompt column that collapses."""

    N = 25

    def setUp(self):
        super().setUp()
        for i in range(self.N):                     # session i costs more than session i-1, so the default sort (cost, descending) is s24 first
            usage = {"input_tokens": 1_000_000 * (i + 1), "output_tokens": 0}
            write_log(self.root, "-p/s%d.jsonl" % i, [user(i, "prompt number %d" % i),
                                                      assistant(i + 1, "claude-opus-4-9", usage, "m%d" % i, "r%d" % i, sid="s%d" % i)])
        self.html = b.render(self.build())

    def page(self, *actions):
        out = run_page(self, self.html, list(actions))
        rows = re.findall(r'<tr class="s[^"]*" data-id="([^"]+)"', out["sess"])
        pager = re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", out["pager"])).strip()
        return out, rows, pager

    def test_first_page_shows_ten_of_the_sessions_with_the_costliest_first(self):
        out, rows, pager = self.page()
        self.assertEqual(rows, ["s%d" % i for i in range(24, 14, -1)])
        self.assertIn("1–10 of 25", pager)
        self.assertIn("Page 1 of 3", pager)
        self.assertRegex(out["pager"], r'data-pg="prev" disabled')
        self.assertNotRegex(out["pager"], r'data-pg="next" disabled')

    def test_next_and_previous_move_through_the_pages(self):
        _, rows, pager = self.page({"pager": "next"})
        self.assertEqual(rows, ["s%d" % i for i in range(14, 4, -1)])
        self.assertIn("11–20 of 25", pager)
        out, rows, pager = self.page({"pager": "next"}, {"pager": "next"})
        self.assertEqual(rows, ["s%d" % i for i in range(4, -1, -1)], "the last page holds the remaining five")
        self.assertIn("21–25 of 25", pager)
        self.assertRegex(out["pager"], r'data-pg="next" disabled')
        _, rows, _ = self.page({"pager": "next"}, {"pager": "prev"})
        self.assertEqual(rows[0], "s24", "previous returns to the first page")

    def test_next_cannot_go_past_the_last_page_or_previous_before_the_first(self):
        _, rows, pager = self.page(*[{"pager": "next"}] * 6)
        self.assertIn("Page 3 of 3", pager)
        _, rows, pager = self.page({"pager": "prev"}, {"pager": "prev"})
        self.assertIn("Page 1 of 3", pager)

    def test_rows_per_page_can_be_changed_and_returns_to_page_one(self):
        _, rows, pager = self.page({"pager": "next"}, {"pageSize": 25})
        self.assertEqual(len(rows), 25)
        self.assertIn("1–25 of 25", pager)
        self.assertIn("Page 1 of 1", pager)
        _, rows, pager = self.page({"pageSize": 50})
        self.assertEqual(len(rows), 25)

    def test_search_filters_across_pages_and_goes_back_to_page_one(self):
        _, rows, pager = self.page({"pager": "next"}, {"search": "prompt number 1"})
        self.assertIn("1–10 of 11", pager, "11 prompts contain 'prompt number 1': 1 and 10 to 19; page one holds ten of them")
        self.assertTrue(all(r in {"s1", "s10", "s11", "s12", "s13", "s14", "s15", "s16", "s17", "s18", "s19"} for r in rows))
        _, rows, pager = self.page({"search": "no such thing"})
        self.assertEqual(rows, [])
        self.assertIn("0–0 of 0", pager)

    def test_sorting_goes_back_to_page_one(self):
        _, rows, pager = self.page({"pager": "next"}, {"sort": "last"})
        self.assertIn("1–10 of 25", pager)
        self.assertEqual(len(rows), 10)

    def heads(self, out):
        return [re.sub(r"<[^>]+>|[▸◂]", "", h).strip() for h in re.findall(r"<th[^>]*>(.*?)</th>", out["sess"], re.S)]

    def test_last_active_never_wraps(self):
        out, _, _ = self.page()
        self.assertRegex(out["sess"], r'<th data-k="last" class="nw"')
        self.assertIn('<td class="nw">', out["sess"])
        css = (PLUGIN / "scripts" / "template.html").read_text()
        self.assertRegex(css, r"\.cd-table \.nw\s*\{\s*white-space:\s*nowrap")

    def test_model_and_effort_never_wraps(self):
        out, _, _ = self.page()
        self.assertRegex(out["sess"], r'<th data-k="model" class="nw"')
        self.assertRegex(out["sess"], r'<td class="nw"><span class="cd-sw"[^>]*></span> opus-4-9')

    def test_only_project_shows_by_default(self):
        out, _, _ = self.page()
        self.assertEqual(self.heads(out)[:4], ["Last active", "Project", "Model · effort", "Tasks"])
        self.assertNotIn("First prompt", out["sess"])
        self.assertNotIn("prompt number 24", out["sess"], "the first prompt is not in the table until it is expanded")
        self.assertEqual(out["sess:class"], "cd-table")
        self.assertRegex(out["sess"], r'<button class="cd-ptoggle"[^>]*aria-expanded="false"')

    def test_clicking_project_splits_it_into_project_and_first_prompt(self):
        out, _, _ = self.page({"toggleWide": True})
        self.assertEqual(self.heads(out)[:5], ["Last active", "Project", "First prompt", "Model · effort", "Tasks"])
        self.assertEqual(out["sess:class"], "cd-table wide-prompt")
        self.assertRegex(out["sess"], r'<button class="cd-ptoggle"[^>]*aria-expanded="true"')
        self.assertIn('title="prompt number 24"', out["sess"], "the full prompt is also on hover")
        out, _, _ = self.page({"toggleWide": True}, {"toggleWide": True})
        self.assertNotIn("First prompt", out["sess"], "a second click folds it back")
        self.assertEqual(out["sess:class"], "cd-table")

    def test_the_project_header_still_sorts_and_the_toggle_keeps_the_page(self):
        out, _, _ = self.page()
        self.assertRegex(out["sess"], r'<th data-k="project"')
        _, rows, pager = self.page({"pager": "next"}, {"toggleWide": True})
        self.assertIn("11–20 of 25", pager)

    def test_expanded_task_rows_keep_the_columns_lined_up_in_both_states(self):
        collapsed, _, _ = self.page({"expand": "s24"})
        task = re.search(r'<tr class="t">(.*?)</tr>', collapsed["sess"], re.S).group(1)
        self.assertEqual(task.count("<td"), len(self.heads(collapsed)), "one cell per column")
        self.assertLess(task.index("prompt number 24"), task.index("cd-sw"), "collapsed: the task prompt sits in the Project column")
        wide, _, _ = self.page({"toggleWide": True}, {"expand": "s24"})
        task = re.search(r'<tr class="t">(.*?)</tr>', wide["sess"], re.S).group(1)
        self.assertEqual(task.count("<td"), len(self.heads(wide)), "one cell per column")
        self.assertLess(task.index('class="p"'), task.index("cd-sw"), "expanded: the prompt cell comes before the model and effort cell")

    def test_the_toggled_table_scrolls_sideways_and_collapsed_prompts_are_capped(self):
        css = (PLUGIN / "scripts" / "template.html").read_text()
        self.assertRegex(css, r"\.cd-table\.wide-prompt\s*\{[^}]*width:\s*max-content")
        self.assertRegex(css, r"\.cd-pc\s*\{[^}]*max-width:\s*12rem[^}]*text-overflow:\s*ellipsis")
        self.assertRegex(css, r"\.cd-table\.wide-prompt \.cd-pc\s*\{[^}]*max-width:\s*none")
        self.assertRegex(css, r"\.cd-box\s*\{[^}]*overflow-x:\s*auto")

    def test_an_empty_search_keeps_the_header_and_spans_every_column(self):
        out, _, _ = self.page({"search": "nothing matches"})
        self.assertIn("<thead>", out["sess"])
        self.assertIn('colspan="11"', out["sess"])
        out, _, _ = self.page({"toggleWide": True}, {"search": "nothing matches"})
        self.assertIn('colspan="12"', out["sess"])


class ActiveTime(Base):
    """Active time: the sum of gaps between consecutive calls that are no longer than ten minutes."""

    def test_idle_gaps_over_ten_minutes_are_left_out(self):
        write_log(self.root, "-p/s1.jsonl", [user(0, "go")] + [assistant(m, "claude-opus-4-9", OPUS_USAGE, "m%d" % m, "r%d" % m) for m in (1, 2, 3, 40)])
        s = self.only_session()
        self.assertEqual(s["active_s"], 120, "1 -> 2 and 2 -> 3 count; the 37-minute gap does not")

    def test_the_ten_minute_boundary_counts_and_one_second_more_does_not(self):
        self.assertEqual(b.active_seconds([datetime(2026, 1, 1, 0, 0, 0), datetime(2026, 1, 1, 0, 10, 0)]), 600)
        self.assertEqual(b.active_seconds([datetime(2026, 1, 1, 0, 0, 0), datetime(2026, 1, 1, 0, 10, 1)]), 0)

    def test_order_does_not_matter_and_one_call_is_zero(self):
        a, c = datetime(2026, 1, 1, 0, 0, 0), datetime(2026, 1, 1, 0, 5, 0)
        self.assertEqual(b.active_seconds([c, a]), 300)
        self.assertEqual(b.active_seconds([a]), 0)
        self.assertEqual(b.active_seconds([]), 0)

    def test_subagent_calls_are_part_of_the_active_time(self):
        write_log(self.root, "-p/s1.jsonl", [user(0, "go"), assistant(1, "claude-opus-4-9", OPUS_USAGE, "m1", "r1")])
        write_log(self.root, "-p/s1/subagents/a.jsonl", [assistant(4, "claude-haiku-4-5", HAIKU_USAGE, "x1", "q1", side=True)])
        self.assertEqual(self.only_session()["active_s"], 180)


class Robustness(Base):
    def test_empty_and_missing_roots_give_no_sessions(self):
        self.assertEqual(self.build()["sessions"], [])
        self.assertEqual(b.collect(os.path.join(self.root, "nope"), days=0)["sessions"], [])
        self.assertEqual(b.log_files(os.path.join(self.root, "nope")), [])

    def test_malformed_and_blank_lines_are_skipped(self):
        write_log(self.root, "-p/s1.jsonl", [user(0, "go"), assistant(1, "claude-opus-4-9", OPUS_USAGE)],
                  raw_tail="this is not json\n\n{\"type\": \"assistant\", \"message\": \n")
        s = self.only_session()
        self.assertAlmostEqual(s["cost"], OPUS_COST, places=4)

    def test_records_with_odd_shapes_do_not_crash(self):
        write_log(self.root, "-p/s1.jsonl", [
            {"type": "assistant"},
            {"type": "assistant", "message": {"usage": {"input_tokens": 10}}},      # no model -> "unknown" fallback
            {"type": "user", "message": {"content": 42}},
            {"type": "user"},
            {"type": "summary", "summary": "x"},
            user(0, "go"),
            assistant(1, "claude-opus-4-9", OPUS_USAGE),
        ])
        self.assertGreaterEqual(self.only_session()["cost"], OPUS_COST)

    def test_unreadable_timestamps_do_not_crash(self):
        rec = assistant(1, "claude-opus-4-9", OPUS_USAGE)
        rec["timestamp"] = "not a time"
        write_log(self.root, "-p/s1.jsonl", [user(0, "go"), rec])
        self.assertAlmostEqual(self.only_session()["cost"], OPUS_COST, places=4)


class NewestMtime(Base):
    def test_zero_when_there_are_no_logs(self):
        self.assertEqual(b.newest_mtime(self.root), 0.0)

    def test_tracks_the_newest_log_including_subagent_files(self):
        main = write_log(self.root, "-p/s1.jsonl", [user(0, "go")])
        sub = write_log(self.root, "-p/s1/subagents/a.jsonl", [user(0, "go")])
        os.utime(main, (1_000, 1_000))
        os.utime(sub, (1_000, 1_000))
        self.assertEqual(b.newest_mtime(self.root), 1_000)
        os.utime(sub, (2_000, 2_000))
        self.assertEqual(b.newest_mtime(self.root), 2_000)

    def test_ignores_files_that_are_not_jsonl(self):
        write_log(self.root, "-p/s1.jsonl", [user(0, "go")])
        os.utime(Path(self.root) / "-p" / "s1.jsonl", (1_000, 1_000))
        (Path(self.root) / "-p" / "notes.txt").write_text("x")
        self.assertEqual(b.newest_mtime(self.root), 1_000)


def run_page(case, html, actions=None):
    """Run the page's script under node with a stub DOM, replaying `actions` (see dom_stub.js); returns {element id: innerHTML}."""
    import shutil
    node = shutil.which("node")
    if not node:
        case.skipTest("node is not installed")
    script = re.search(r"<script>(.*)</script>", html, re.S).group(1)
    runner = Path(__file__).with_name("dom_stub.js")
    with tempfile.TemporaryDirectory() as tmp:
        page = Path(tmp) / "page.js"
        page.write_text(script, encoding="utf-8")
        r = subprocess.run([node, str(runner), str(page), json.dumps(actions or [])], capture_output=True, text=True, timeout=30)
    case.assertEqual(r.returncode, 0, r.stderr)
    return json.loads(r.stdout)


class Render(Base):
    def page(self, prompt="plain"):
        write_log(self.root, "-p/s1.jsonl", [user(0, prompt), assistant(1, "claude-opus-4-9", OPUS_USAGE)])
        return b.render(self.build())

    def data_blob(self, html):
        m = re.search(r"const DATA = (\{.*?\});\n", html, re.S)
        self.assertIsNotNone(m, "the data placeholder was not replaced")
        return m.group(1)

    def test_placeholder_is_replaced_with_valid_json(self):
        html = self.page()
        self.assertNotIn("/*__DATA__*/", html)
        data = json.loads(self.data_blob(html).replace("<\\/", "</"))
        self.assertEqual(data["sessions"][0]["turns"][0]["prompt"], "plain")

    def test_page_is_self_contained(self):
        html = self.page()
        self.assertEqual(re.findall(r"""(?:src|href)\s*=\s*["']?https?:""", html), [])
        self.assertEqual(re.findall(r"url\(\s*['\"]?https?:", html), [])
        self.assertEqual(re.findall(r"@import", html), [])

    def test_prompt_text_cannot_close_the_script_tag(self):
        template = (PLUGIN / "scripts" / "template.html").read_text()
        html = self.page("evil </script><script>alert(1)</script> & <b>")
        self.assertEqual(html.count("</script>"), template.count("</script>"))
        self.assertNotIn("</script><script>alert", html, "only the closing tag is a hazard; <script> inside the JSON string is inert")
        self.assertIn("<\\/script>", html)

    def run_page_script(self, html, actions=None):
        return run_page(self, html, actions)

    def test_page_script_draws_the_model_and_effort_views(self):
        write_log(self.root, "-p/s1.jsonl", [
            user(0, "quick"),
            assistant(1, "claude-sonnet-5-5", OPUS_USAGE, "m1", "r1", per_turn="low"),
            user(5, "hard"),
            assistant(6, "claude-opus-4-9", OPUS_USAGE, "m2", "r2", per_turn="high"),
            assistant(7, "claude-opus-4-9", HAIKU_USAGE, "m3", "r3", per_turn="medium"),
        ])
        out = self.run_page_script(b.render(self.build()))
        text = lambda k: re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", out[k]))
        for gone in ("eff-tbl", "mod-tbl"):
            self.assertNotIn(gone, out, "the standalone effort and model tables are gone")
        grouped = text("mod-eff")
        self.assertLess(grouped.index("claude-opus-4-9"), grouped.index("high"), "an effort row comes after the model it ran on")
        self.assertLess(grouped.index("high"), grouped.index("claude-sonnet-5-5 · low"))
        self.assertEqual(out["mod-eff"].count('<tr class="tot"'), 2, "opus (two efforts) gets a total row; sonnet (one effort) is a single row")
        self.assertEqual(out["mod-eff"].count('<tr class="t"'), 2, "only opus has nested effort rows, one per effort")
        self.assertEqual(out["matrix"].count("color-mix"), 3, "one heat cell per model x effort pair that has calls")
        self.assertIn("small sample", text("task-eff"), "fewer than 5 tasks must be marked")
        self.assertIn("opus-4-9 · medium", text("task-eff"), "the costliest pair in the hard task ($30 at medium, not $0.75 at high)")
        self.assertIn("sonnet-5-5 · low", text("task-eff"), "tasks are grouped by model and effort together")
        self.assertEqual(out["daily-eff"].count("<rect"), 3)
        self.assertEqual(out["eff-legend"].count("cd-sw"), 3)
        self.assertIn("opus-4-9 · high", text("eff-legend"))
        self.assertEqual(out["sess"].count("<th "), 11, "Project alone, one Model · effort column, then in and out tokens and dollars")
        self.assertIn("Model · effort", text("sess"))
        self.assertIn("opus-4-9 · medium +2", text("sess"), "costliest model and effort pair, plus a count of the other two pairs")

    def test_a_model_with_one_effort_is_one_row_and_with_several_is_nested(self):
        write_log(self.root, "-p/s1.jsonl", [
            user(0, "go"),
            assistant(1, "claude-sonnet-5-5", OPUS_USAGE, "m1", "r1", per_turn="medium"),
            assistant(2, "claude-opus-4-9", OPUS_USAGE, "m2", "r2", per_turn="low"),
            assistant(3, "claude-opus-4-9", OPUS_USAGE, "m3", "r3", per_turn="high"),
        ])
        out = self.run_page_script(b.render(self.build()))
        rows = re.findall(r'<tr class="(tot|t)"><td[^>]*>(.*?)</td>', out["mod-eff"], re.S)
        labels = [(cls, re.sub(r"<[^>]+>", "", cell).strip()) for cls, cell in rows]
        self.assertEqual(labels, [("tot", "claude-opus-4-9"), ("t", "low"), ("t", "high"), ("tot", "claude-sonnet-5-5 · medium")])

    def test_page_script_shows_tokens_and_dollars_in_and_out_in_every_table(self):
        write_log(self.root, "-p/s1.jsonl", [user(0, "go"), assistant(1, "claude-opus-4-9", HAIKU_USAGE, "m1", "r1", per_turn="high")])
        out = self.run_page_script(b.render(self.build()))
        text = lambda k: re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", out[k]))
        for table in ("models", "mod-eff", "sess"):
            for head in ("In tokens", "Out tokens", "$ In", "$ Out"):
                self.assertIn(head, text(table), "%s lacks %s" % (table, head))
        self.assertIn("In tokens / task", text("task-eff"))
        self.assertIn("$ Out / task", text("task-eff"))
        # 1M tokens in at $5 and 1M out at $25 on opus: dollars, then the price paid per million, then the total
        self.assertIn("claude-opus-4-9 · high 1 1.0M 1.0M $5.00 $25.00 $5.00 $25.00 $30.00", text("mod-eff"))
        self.assertEqual(out["mod-eff"].count('<tr class="t"'), 0, "a model with one effort is one row, not a total plus a repeat of it")
        self.assertIn("1.0M in · 1.0M out", text("matrix"))
        self.assertIn("$5.00 in · $25.00 out", text("matrix"))
        self.assertIn("1.0M / 1.0M", text("kpis"))
        self.assertIn("$5.00 / $25.00", text("kpis"))

    def test_page_script_draws_the_context_tab(self):
        sizes = [100_000, 400_000, 200_000]
        recs = [user(0, "go")] + [assistant(1 + i, "claude-sonnet-5-5", {"output_tokens": 10, "cache_read_input_tokens": n}, "m%d" % i, "r%d" % i)
                                  for i, n in enumerate(sizes)]
        write_log(self.root, "-p/s1.jsonl", recs)
        with mock.patch.object(b, "PRICING", json.loads((PLUGIN / "pricing.json").read_text())):   # the shipped rates, for the rate card
            out = self.run_page_script(b.render(self.build()))
        text = lambda k: re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", out[k]))
        self.assertIn("Cache read", text("parts-tbl"))
        self.assertIn("3 calls", out["ctx-note"])
        self.assertIn("peak 400.0k", out["ctx-note"])
        self.assertIn("1 drop", out["ctx-note"])
        self.assertEqual(out["ctx-chart"].count("<rect"), 3)
        self.assertEqual(out["ctx-chart"].count("stroke-dasharray"), 1, "one dashed reset line")
        self.assertEqual(out["ctx-sel"].count("<option"), 1)
        self.assertEqual(out["ctx-tbl"].count('<tr class="s'), 1)
        self.assertIn("average call sent", out["ctx-read"])
        rates = re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", out["rate-tbl"]))
        self.assertIn("claude-sonnet-5-5", rates)
        self.assertIn("0.05x", rates, "Sonnet 5.5 cache reads are 0.05x the input price")
        self.assertIn("$0.100", rates, "and $0.10 per million tokens")
        self.assertIn("per million tokens", out["rate-note"])
        self.assertIn("Per 1M tokens", out["parts-tbl"])

    def test_page_script_copes_with_no_sessions(self):
        out = self.run_page_script(b.render(self.build()))
        self.assertIn("No calls in this period", out["mod-eff"])
        self.assertIn("No sessions match", out["sess"])
        self.assertIn("No main-conversation calls", out["ctx-tbl"])
        self.assertIn("No main-conversation calls", out["ctx-note"])

    def test_table_boxes_have_no_inner_vertical_scrollbar(self):
        """A scrollbar inside a table box sat beside the last column's header, so the boxes must never scroll vertically."""
        css = (PLUGIN / "scripts" / "template.html").read_text()
        box = re.search(r"\.cd-box\s*\{([^}]*)\}", css).group(1)
        self.assertNotIn("max-height", box)
        self.assertNotRegex(box, r"overflow(-y)?\s*:\s*(auto|scroll)")
        self.assertNotIn("scrollbar-gutter", box)
        self.assertNotIn("position: sticky", re.search(r"\.cd-table th\s*\{([^}]*)\}", css).group(1))

    def test_the_model_and_effort_tab_stacks_the_chart_above_the_task_table_at_full_width(self):
        html = (PLUGIN / "scripts" / "template.html").read_text()
        day = re.search(r'<div class="([^"]*)"><h2>Cost per day by model and effort</h2>', html)
        task = re.search(r'<div class="([^"]*)"><h2>Cost per task by model and effort</h2>', html)
        self.assertIn("cd-span", day.group(1))
        self.assertIn("cd-span", task.group(1))
        self.assertLess(day.start(), task.start(), "the chart comes before the table it would otherwise squeeze")

    def test_the_stacked_chart_uses_a_wide_canvas_to_fill_its_card(self):
        write_log(self.root, "-p/s1.jsonl", [user(0, "go"), assistant(1, "claude-opus-4-9", OPUS_USAGE, "m1", "r1", per_turn="high")])
        out = self.run_page_script(b.render(self.build()))
        xs = [float(x) for x in re.findall(r'<rect x="([\d.]+)"', out["daily-eff"])]
        self.assertTrue(xs)
        self.assertGreater(float(re.search(r'<text x="([\d.]+)" y="[\d.]+" font-size="10" text-anchor="end"', out["daily-eff"]).group(1)), 1000,
                           "the end label sits at the right edge of the 1100-wide canvas")

    def test_model_and_effort_labels_never_wrap(self):
        write_log(self.root, "-p/s1.jsonl", [user(0, "go"), assistant(1, "claude-opus-4-9", OPUS_USAGE, "m1", "r1", per_turn="high")])
        out = self.run_page_script(b.render(self.build()))
        self.assertRegex(out["task-eff"], r'<tr><td class="nw"><span class="cd-sw"')
        self.assertRegex(out["mod-eff"], r'<tr class="tot"><td class="nw"><span class="cd-sw"')
        self.assertIn('<th class="nw">Model · effort</th>', out["task-eff"])

    def test_generated_time_can_be_fixed(self):
        write_log(self.root, "-p/s1.jsonl", [user(0, "go"), assistant(1, "claude-opus-4-9", OPUS_USAGE)])
        fixed = datetime(2026, 1, 2, 3, 4, 5)
        self.assertEqual(self.build(now=fixed)["generated"], "2026-01-02T03:04:05")

    def test_summary_lists_total_and_top_sessions(self):
        write_log(self.root, "-p/s1.jsonl", [user(0, "pricey"), assistant(1, "claude-haiku-4-5", HAIKU_USAGE)])
        text = b.summary(self.build(), "/x/out.html")
        self.assertIn("Sessions: 1", text)
        self.assertIn("$6.00", text)
        self.assertIn("pricey", text)
        self.assertTrue(text.endswith("Dashboard: /x/out.html"))


class CommandLine(unittest.TestCase):
    """Runs the script the way the slash command does."""

    def run_cli(self, *args):
        return subprocess.run([sys.executable, "-I", str(PLUGIN / "scripts" / "build_dashboard.py"), *args],
                              capture_output=True, text=True, timeout=60)

    def test_no_logs_exits_1_with_a_message_and_writes_nothing(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "out" / "d.html"
            r = self.run_cli("--root", str(Path(tmp) / "empty"), "--out", str(out))
            self.assertEqual(r.returncode, 1)
            self.assertIn("No session logs found", r.stdout)
            self.assertFalse(out.exists())

    def test_builds_the_page_creating_parent_folders_and_prints_the_summary(self):
        with tempfile.TemporaryDirectory() as tmp:
            write_log(tmp, "logs/-p/s1.jsonl", [user(0, "go"), assistant(1, "claude-opus-4-9", OPUS_USAGE)])
            out = Path(tmp) / "deep" / "er" / "d.html"
            r = self.run_cli("--root", str(Path(tmp) / "logs"), "--days", "0", "--out", str(out))
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertTrue(out.read_text().startswith("<!doctype html>") or "<html" in out.read_text()[:200].lower())
            self.assertIn("Sessions: 1", r.stdout)
            self.assertIn("Dashboard: " + str(out), r.stdout)


class StaticOutputUnchanged(Base):
    """Regression guard for the collect/render split: the page for a fixed fixture must keep this exact data."""

    def test_fixed_fixture_data_is_stable(self):
        write_log(self.root, "-p/s1.jsonl", [
            user(0, "one"), assistant(1, "claude-sonnet-5-5", SONNET_BIG, "m1", "r1"),
            user(5, "two"), assistant(6, "claude-opus-4-9", OPUS_USAGE, "m2", "r2"),
        ])
        data = self.build(now=datetime(2026, 1, 1))
        s = data["sessions"][0]
        self.assertEqual(
            (s["id"], s["project"], s["title"], s["cost"], s["sub_cost"], s["calls"]),
            ("s1", "proj", "one", round(SONNET_BIG_COST + OPUS_COST, 4), 0.0, 2))
        self.assertEqual(sorted(data), ["days", "generated", "rates", "rates_source", "rates_verified", "sessions", "speed_flags", "unpriced"])
        self.assertEqual(sorted(s), ["active_s", "calls", "cost", "ctx", "cw1h", "daily", "daily_me", "first", "id", "last",
                                     "matrix", "models", "parts", "project", "sub_cost", "title", "tokens", "turns"])


if __name__ == "__main__":
    unittest.main()
