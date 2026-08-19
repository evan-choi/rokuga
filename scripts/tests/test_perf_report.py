import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
REPORT = REPO_ROOT / "scripts" / "perf-report.py"


class PerfReportTests(unittest.TestCase):
    def test_hot_symbols_separates_inclusive_and_self_weight(self):
        xml = """\
<trace-query-result>
  <row>
    <weight fmt="2.00 ms">2000000</weight>
    <backtrace>
      <frame name="framework_leaf"><binary name="Framework"/></frame>
      <frame name="App.hot"><binary name="RokugaPerf"/></frame>
    </backtrace>
  </row>
  <row>
    <weight fmt="1.00 ms">1000000</weight>
    <backtrace>
      <frame name="App.self"><binary name="RokugaPerf"/></frame>
    </backtrace>
  </row>
</trace-query-result>
"""
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            source = directory / "time-profile.xml"
            output = directory / "hot-functions.json"
            source.write_text(xml, encoding="utf-8")
            result = subprocess.run(
                [
                    sys.executable,
                    str(REPORT),
                    "hot-symbols",
                    "--input",
                    str(source),
                    "--output",
                    str(output),
                ],
                cwd=REPO_ROOT,
                text=True,
                capture_output=True,
            )

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            report = json.loads(output.read_text(encoding="utf-8"))

        symbols = {value["symbol"]: value for value in report["symbols"]}
        self.assertAlmostEqual(symbols["App.hot"]["percent"], 200 / 3)
        self.assertEqual(symbols["App.hot"]["selfPercent"], 0)
        self.assertAlmostEqual(symbols["App.self"]["selfPercent"], 100 / 3)
        self.assertEqual(report["leafSymbols"][0]["symbol"], "framework_leaf")
        self.assertEqual(report["leafSymbols"][0]["binary"], "Framework")
        self.assertAlmostEqual(report["leafSymbols"][0]["selfPercent"], 200 / 3)


if __name__ == "__main__":
    unittest.main()
