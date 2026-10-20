"""Every search pattern in the two commands must compile in ripgrep.

A pattern that does not compile makes rg exit 2, and the scan it belongs to
silently returns nothing. Skipped when rg is not installed.
"""
import os
import re
import shutil
import subprocess
import unittest

KIT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COMMANDS = [os.path.join(KIT, "commands", name) for name in ("review-security.md", "audit-saas.md")]


def patterns(path):
    text = open(path, encoding="utf-8").read()
    for block in re.findall(r"```text\n(.*?)```", text, re.S):
        for line in block.splitlines():
            parts = re.split(r"\s{2,}", line.strip())
            if len(parts) < 2:
                continue
            yield parts[0], parts[-2] if parts[-1].startswith("(only") else parts[-1]


@unittest.skipUnless(shutil.which("rg"), "ripgrep not installed")
class PatternTest(unittest.TestCase):
    def test_patterns_compile(self):
        count = 0
        for path in COMMANDS:
            for label, pattern in patterns(path):
                count += 1
                r = subprocess.run(["rg", "--quiet", "-e", pattern, os.devnull], capture_output=True, text=True)
                self.assertNotEqual(r.returncode, 2, f"{os.path.basename(path)} [{label}]: {r.stderr.strip()}")
        self.assertGreater(count, 30)

    def test_weak_crypto_pattern_ignores_ordinary_words(self):
        pattern = next(p for path in COMMANDS for label, p in patterns(path) if label == "weak crypto")
        sample = "const description = 'includes DESIGN notes';\nconst k = crypto.createHash('md5');\n"
        r = subprocess.run(["rg", "-n", "-e", pattern], input=sample, capture_output=True, text=True)
        self.assertEqual(r.stdout.strip().splitlines(), ["2:const k = crypto.createHash('md5');"])


if __name__ == "__main__":
    unittest.main()
