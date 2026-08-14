#!/usr/bin/env python3
"""Benchmark regression gates (tasks 10.2/10.3/10.4).

Reads rokuga-bench JSON from files, enforces the absolute budgets from the
performance spec, and fails on >10% regression against benchmarks/baseline.json.
Usage: bench-gate.py <throughput.json> <latency.json> [--update-baseline]
"""

import json
import sys

BASELINE_PATH = "benchmarks/baseline.json"
REGRESSION_TOLERANCE = 1.10

ABSOLUTE_BUDGETS = {
    # spec: 4K60 drop-rate < 0.1%; PTS drift < 40 ms/h scaled to run length
    "throughput": {
        "dropRate": 0.001,
        "cpuPercentOfOneCore": None,  # resolution-dependent, set below
        "peakMemoryMB": 400,
        "stopToPlayableSeconds": 2.0,
    },
    "latency": {
        "recordToFirstFrameSeconds": 0.5,
        "stopToPlayableSeconds": 2.0,
        "passthroughTrimSeconds": 3.0,
    },
}

# spec: CPU ≤ 20% @1080p60, ≤ 35% @4K60 (percent of total machine ≈ percent of
# one core × cores; the harness reports single-core percent, so budget on that).
CPU_BUDGET_BY_HEIGHT = {1080: 20 * 8, 2160: 35 * 8}


def check(result, budgets, failures, prefix):
    for key, limit in budgets.items():
        if limit is None or key not in result:
            continue
        value = result[key]
        if value > limit:
            failures.append(f"[budget] {prefix}.{key} = {value:.6g} > {limit}")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    update_baseline = "--update-baseline" in sys.argv
    throughput = json.load(open(args[0]))
    latency = json.load(open(args[1]))

    failures = []

    budgets = dict(ABSOLUTE_BUDGETS["throughput"])
    budgets["cpuPercentOfOneCore"] = CPU_BUDGET_BY_HEIGHT.get(throughput.get("height"), 35 * 8)
    drift_budget = 0.040 * max(throughput.get("seconds", 0), 1) / 3600 + 0.020
    budgets["ptsDriftSeconds"] = drift_budget
    check(throughput, budgets, failures, "throughput")
    check(latency, ABSOLUTE_BUDGETS["latency"], failures, "latency")

    try:
        baseline = json.load(open(BASELINE_PATH))
    except FileNotFoundError:
        baseline = None

    current = {
        "throughput.cpuPercentOfOneCore": throughput["cpuPercentOfOneCore"],
        "throughput.peakMemoryMB": throughput["peakMemoryMB"],
        "latency.recordToFirstFrameSeconds": latency["recordToFirstFrameSeconds"],
        "latency.stopToPlayableSeconds": latency["stopToPlayableSeconds"],
        "latency.passthroughTrimSeconds": latency["passthroughTrimSeconds"],
    }

    if baseline:
        for key, value in current.items():
            base = baseline.get(key)
            if base and base > 0 and value > base * REGRESSION_TOLERANCE:
                failures.append(
                    f"[regression] {key} = {value:.6g} exceeds baseline {base:.6g} by >10%"
                )

    if update_baseline:
        json.dump(current, open(BASELINE_PATH, "w"), indent=2, sort_keys=True)
        print(f"baseline updated: {BASELINE_PATH}")

    if failures:
        print("\n".join(failures))
        print(f"\nFAILED: {len(failures)} gate violation(s)")
        return 1

    print("OK: all performance gates passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
