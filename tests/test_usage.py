"""Tests for extras/usage.py against a generated fixture of Claude Code logs.

Run: python3 -m unittest discover -s tests -p 'test_*.py'
"""
import datetime as dt
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
KIT = os.path.dirname(HERE)
SCRIPT = os.path.join(KIT, "extras", "usage.py")
sys.path.insert(0, os.path.join(KIT, "extras"))
import usage  # noqa: E402


def entry(req, model, ts, inp=0, out=0, cw5=0, cw1=0, cr=0, speed="standard", geo="global",
          session="s1", cwd="/work/demo", sidechain=False):
    return {
        "type": "assistant",
        "timestamp": ts,
        "requestId": req,
        "sessionId": session,
        "cwd": cwd,
        "isSidechain": sidechain,
        "message": {
            "role": "assistant",
            "model": model,
            "usage": {
                "input_tokens": inp,
                "output_tokens": out,
                "cache_creation_input_tokens": cw5 + cw1,
                "cache_read_input_tokens": cr,
                "cache_creation": {"ephemeral_5m_input_tokens": cw5, "ephemeral_1h_input_tokens": cw1},
                "service_tier": "standard",
                "inference_geo": geo,
                "speed": speed,
            },
        },
    }


class UsageTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp(prefix="kit-usage-")
        cls.root = os.path.join(cls.tmp, "projects")
        proj = os.path.join(cls.root, "-work-demo")
        os.makedirs(proj)
        now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
        today = now.isoformat().replace("+00:00", "Z")
        old = (now - dt.timedelta(days=400)).isoformat().replace("+00:00", "Z")
        rows = [
            # 1. Opus 5.5 with a 5-minute cache write and cache reads
            entry("r1", "claude-opus-5-5", today, inp=1000, cw5=2000, cr=10000, out=500),
            # 2. duplicate of r1 (Claude Code logs one line per content block): counted once
            entry("r1", "claude-opus-5-5", today, inp=1000, cw5=2000, cr=10000, out=500),
            # 3. dated snapshot id maps to the claude-haiku-4-5 family
            entry("r3", "claude-haiku-4-5-20251001", today, inp=100000, out=1000),
            # 4. Haiku 5.5 over 100k prompt tokens: long-context prices
            entry("r4", "claude-haiku-5-5", today, inp=50000, cr=60000, out=1000),
            # 5. Haiku 5.5 under the threshold
            entry("r5", "claude-haiku-5-5", today, inp=1000, out=1000),
            # 6. Opus 5.5 fast mode
            entry("r6", "claude-opus-5-5", today, inp=1000, out=1000, speed="fast"),
            # 7. Sonnet 5.5 with a 1-hour cache write, in a subagent
            entry("r7", "claude-sonnet-5-5", today, cw1=1000, sidechain=True),
            # 8. a model the price file does not know
            entry("r8", "claude-opus-9", today, inp=1000, out=1000),
            # 9. US-only inference: 1.1x
            entry("r9", "claude-sonnet-5-5", today, inp=1000, out=1000, geo="us"),
            # 10. fast mode on a model with no fast price
            entry("r10", "claude-sonnet-5-5", today, inp=1000, out=1000, speed="fast"),
            # 11. 400 days old: outside --days, inside --all
            entry("r11", "claude-opus-5-5", old, inp=1000000, session="s-old"),
            # 12. a [1m] suffix maps to the same family
            entry("r12", "claude-opus-5-5[1m]", today, out=1000),
            # 13. synthetic error placeholder with no tokens: ignored
            entry("r13", "<synthetic>", today),
        ]
        with open(os.path.join(proj, "session.jsonl"), "w") as fh:
            for r in rows:
                fh.write(json.dumps(r) + "\n")
            fh.write("not json at all\n")
            fh.write(json.dumps({"type": "user", "message": {"role": "user", "content": "hi"}}) + "\n")

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def run_json(self, *extra):
        buf = io.StringIO()
        with redirect_stdout(buf):
            code = usage.main(["--root", self.root, "--json", "--tz", "UTC", *extra])
        self.assertEqual(code, 0)
        return json.loads(buf.getvalue())

    def test_totals_last_7_days(self):
        s = self.run_json("--days", "7")
        expected = {
            "claude-opus-5-5": (1000 * 4 + 2000 * 5 + 10000 * 0.2 + 500 * 20) / 1e6   # r1
                               + (1000 * 8 + 1000 * 40) / 1e6,                      # r6 fast
            "claude-haiku-4-5-20251001": (100000 * 1 + 1000 * 5) / 1e6,
            "claude-haiku-5-5": (50000 * 0.5 + 60000 * 0.05 + 1000 * 2.5) / 1e6 + (1000 * 0.1 + 1000 * 0.5) / 1e6,
            "claude-sonnet-5-5": (1000 * 4) / 1e6 + (1000 * 2 + 1000 * 10) / 1e6 * 1.1,
        }
        self.assertEqual(s["requests"], 10)            # r1, r3-r10, r12 (r2 duplicate, r11 old, r13 empty)
        self.assertEqual(s["unpriced_requests"], 2)    # r8 unknown model, r10 fast without price
        self.assertEqual(s["unpriced_models"], {"claude-opus-9": 1, "claude-sonnet-5-5 (fast mode)": 1})
        for model, usd in expected.items():
            self.assertAlmostEqual(s["by_model"][model]["usd"], usd, places=6, msg=model)
        self.assertAlmostEqual(s["by_model"]["claude-opus-5-5[1m]"]["usd"], 0.02, places=6)
        self.assertAlmostEqual(s["total_usd"], sum(expected.values()) + 0.02, places=6)

    def test_all_includes_old_rows(self):
        s = self.run_json("--all")
        self.assertEqual(s["requests"], 11)
        self.assertEqual(s["period"], "all history")

    def test_days_zero_is_rejected(self):
        r = subprocess.run([sys.executable, SCRIPT, "--root", self.root, "--days", "0"],
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 2)
        self.assertIn("--days must be 1 or more", r.stderr)

    def test_text_report_warns_about_unpriced(self):
        r = subprocess.run([sys.executable, SCRIPT, "--root", self.root, "--days", "1", "--tz", "UTC",
                            "--sessions", "--daily-target", "0.01"], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("2 requests without a known price", r.stdout)
        self.assertIn("above target", r.stdout)
        self.assertIn("TOP SESSIONS", r.stdout)
        self.assertIn("subagents", r.stdout)

    def test_missing_price_file(self):
        r = subprocess.run([sys.executable, SCRIPT, "--root", self.root, "--prices", "/nonexistent.json"],
                           capture_output=True, text=True)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("price file not found", r.stderr)

    def test_model_family(self):
        cases = {
            "claude-haiku-4-5-20251001": "claude-haiku-4-5",
            "claude-opus-5-5[1m]": "claude-opus-5-5",
            "us.anthropic.claude-opus-5": "claude-opus-5",
            "anthropic.claude-sonnet-4-5-20250929-v1:0": "claude-sonnet-4-5",
            "claude-haiku-4-5@20251001": "claude-haiku-4-5",
            "claude-opus-5-6": "claude-opus-5-6",
            "claude-3-5-haiku-20241022": "claude-3-5-haiku",
        }
        for raw, want in cases.items():
            self.assertEqual(usage.model_family(raw), want, raw)

    def test_price_file_has_current_models(self):
        with open(os.path.join(KIT, "extras", "prices.json")) as fh:
            prices = json.load(fh)
        for model in ("claude-fable-5-1", "claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"):
            self.assertIn(model, prices["models"])
        self.assertTrue(prices["source"].startswith("https://"))
        self.assertRegex(prices["retrieved"], r"^\d{4}-\d{2}-\d{2}$")


if __name__ == "__main__":
    unittest.main()
