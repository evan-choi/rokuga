import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
GATE = REPO_ROOT / "scripts" / "bench-gate.py"


class BenchGateTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.directory = Path(self.temporary.name)
        self.recording = self.directory / "recording.mov"
        self.recording.write_bytes(b"mov")

    def tearDown(self):
        self.temporary.cleanup()

    def capture(self, seconds=15, integrity=0.009, drift=0.005, drift_per_hour=None):
        output = {
            "videoFrames": 900,
            "fileSizeBytes": self.recording.stat().st_size,
            "audioVideoSyncMarkers": 15,
            "audioVideoObservedSeconds": 14,
            "audioVideoDriftSeconds": drift,
        }
        if drift_per_hour is not None:
            output["audioVideoDriftSecondsPerHour"] = drift_per_hour
        return {
            "scenario": "4k-audio",
            "height": 2160,
            "seconds": seconds,
            "cpuPercentOfOneCore": 34,
            "peakMemoryMB": 60,
            "steadyMemoryMB": 50,
            "recordToFirstFrameSeconds": 0.49,
            "stopToPlayableSeconds": 1.9,
            "frameRateMode": "variable",
            "systemAudio": True,
            "workload": {"motion": True},
            "derived": {"dropRate": 0, "outputIntegrityRate": integrity},
            "output": output,
            "outputPath": str(self.recording),
        }

    def run_gate(self, capture):
        result = self.directory / "result.json"
        result.write_text(json.dumps(capture), encoding="utf-8")
        return subprocess.run(
            [sys.executable, str(GATE), "--capture", str(result)],
            cwd=REPO_ROOT,
            text=True,
            capture_output=True,
        )

    def test_short_capture_uses_smoke_integrity_ceiling(self):
        self.assertEqual(self.run_gate(self.capture(integrity=0.009)).returncode, 0)

    def test_short_capture_rejects_gross_integrity_failure(self):
        result = self.run_gate(self.capture(integrity=0.011))
        self.assertEqual(result.returncode, 1)
        self.assertIn("outputIntegrityRate", result.stdout)

    def test_ten_minute_capture_enforces_spec_integrity(self):
        result = self.run_gate(self.capture(seconds=600, integrity=0.001, drift_per_hour=0.039))
        self.assertEqual(result.returncode, 1)
        self.assertIn("outputIntegrityRate", result.stdout)

    def test_ten_minute_capture_enforces_hourly_drift(self):
        result = self.run_gate(self.capture(seconds=600, integrity=0.0009, drift_per_hour=0.040))
        self.assertEqual(result.returncode, 1)
        self.assertIn("audioVideoDriftSecondsPerHour", result.stdout)

    def test_ten_minute_capture_passes_spec_budgets(self):
        result = self.run_gate(self.capture(seconds=600, integrity=0.0009, drift_per_hour=0.039))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_synthetic_benchmark_pair_remains_supported(self):
        throughput = self.directory / "throughput.json"
        latency = self.directory / "latency.json"
        throughput.write_text(json.dumps({
            "height": 1080,
            "seconds": 10,
            "dropRate": 0,
            "ptsDriftSeconds": 0,
            "cpuPercentOfOneCore": 4,
            "peakMemoryMB": 36,
            "stopToPlayableSeconds": 0.1,
        }), encoding="utf-8")
        latency.write_text(json.dumps({
            "recordToFirstFrameSeconds": 0.18,
            "stopToPlayableSeconds": 0.13,
            "passthroughTrimSeconds": 0.02,
        }), encoding="utf-8")
        result = subprocess.run(
            [sys.executable, str(GATE), str(throughput), str(latency)],
            cwd=REPO_ROOT,
            text=True,
            capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
