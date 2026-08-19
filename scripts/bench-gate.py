#!/usr/bin/env python3
"""Synthetic and actual-capture performance gates (tasks 10.2/10.3/10.4).

Accepts a rokuga-bench throughput/latency pair, one or more RokugaPerf capture
results, or both. Usage: bench-gate.py [throughput.json latency.json]
[--capture result.json] [--update-baseline]
"""

import argparse
import json
import sys
from pathlib import Path

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

# The harness already reports CPU time as a percentage of one core.
CPU_BUDGET_BY_HEIGHT = {1080: 20, 2160: 35}


def check(result, budgets, failures, prefix):
    for key, limit in budgets.items():
        if limit is None or key not in result or result[key] is None:
            continue
        value = result[key]
        if value > limit:
            failures.append(f"[budget] {prefix}.{key} = {value:.6g} > {limit}")


def check_strict(result, budgets, failures, prefix):
    for key, limit in budgets.items():
        if key not in result or result[key] is None:
            continue
        value = result[key]
        if value >= limit:
            failures.append(f"[budget] {prefix}.{key} = {value:.6g} >= {limit}")


def required_number(value, path, failures):
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return value
    failures.append(f"[invalid] missing numeric {path}")
    return None


def check_capture(result, path, failures):
    prefix = f"capture[{result.get('scenario') or Path(path).parent.name}]"
    output = result.get("output") if isinstance(result.get("output"), dict) else {}
    derived = result.get("derived") if isinstance(result.get("derived"), dict) else {}
    workload = result.get("workload") if isinstance(result.get("workload"), dict) else {}

    height = required_number(result.get("height"), f"{prefix}.height", failures)
    seconds = required_number(result.get("seconds"), f"{prefix}.seconds", failures)
    cpu = required_number(result.get("cpuPercentOfOneCore"), f"{prefix}.cpuPercentOfOneCore", failures)
    peak = required_number(result.get("peakMemoryMB"), f"{prefix}.peakMemoryMB", failures)
    steady = required_number(result.get("steadyMemoryMB"), f"{prefix}.steadyMemoryMB", failures)
    first_frame = required_number(
        result.get("recordToFirstFrameSeconds"), f"{prefix}.recordToFirstFrameSeconds", failures
    )
    finalize = required_number(
        result.get("stopToPlayableSeconds"), f"{prefix}.stopToPlayableSeconds", failures
    )
    writer_drop = required_number(derived.get("dropRate"), f"{prefix}.derived.dropRate", failures)
    continuity = workload.get("motion") is True or result.get("frameRateMode") == "constant"
    integrity = derived.get("outputIntegrityRate")
    integrity_limit = 0.001 if seconds is not None and seconds >= 600 else 0.01
    if continuity:
        integrity = required_number(integrity, f"{prefix}.derived.outputIntegrityRate", failures)

    if height is not None and cpu is not None:
        check(
            {"cpuPercentOfOneCore": cpu},
            {"cpuPercentOfOneCore": CPU_BUDGET_BY_HEIGHT.get(height, 35)},
            failures,
            prefix,
        )
    check(
        {
            "peakMemoryMB": peak,
            "steadyMemoryMB": steady,
            "recordToFirstFrameSeconds": first_frame,
            "stopToPlayableSeconds": finalize,
        },
        {
            "peakMemoryMB": 400,
            "steadyMemoryMB": 400,
            "recordToFirstFrameSeconds": 0.5,
            "stopToPlayableSeconds": 2.0,
        },
        failures,
        prefix,
    )
    check_strict(
        {"writerDropRate": writer_drop, "outputIntegrityRate": integrity},
        {"writerDropRate": 0.001, "outputIntegrityRate": integrity_limit},
        failures,
        prefix,
    )

    frames = required_number(output.get("videoFrames"), f"{prefix}.output.videoFrames", failures)
    file_size = required_number(output.get("fileSizeBytes"), f"{prefix}.output.fileSizeBytes", failures)
    if frames is not None and frames <= 0:
        failures.append(f"[invalid] {prefix}.output.videoFrames must be positive")
    if file_size is not None and file_size <= 0:
        failures.append(f"[invalid] {prefix}.output.fileSizeBytes must be positive")
    output_path = result.get("outputPath")
    if not isinstance(output_path, str) or not Path(output_path).is_file():
        failures.append(f"[invalid] {prefix}.outputPath does not exist: {output_path}")

    if result.get("systemAudio") is True:
        marker_count = required_number(
            output.get("audioVideoSyncMarkers"), f"{prefix}.output.audioVideoSyncMarkers", failures
        )
        if marker_count is not None and marker_count < 2:
            failures.append(f"[invalid] {prefix}.output.audioVideoSyncMarkers = {marker_count} < 2")
        if seconds is not None and seconds >= 600:
            drift = required_number(
                output.get("audioVideoDriftSecondsPerHour"),
                f"{prefix}.output.audioVideoDriftSecondsPerHour",
                failures,
            )
            if drift is not None:
                check_strict(
                    {"audioVideoDriftSecondsPerHour": drift},
                    {"audioVideoDriftSecondsPerHour": 0.040},
                    failures,
                    prefix,
                )
        else:
            drift = required_number(
                output.get("audioVideoDriftSeconds"), f"{prefix}.output.audioVideoDriftSeconds", failures
            )
            observed = required_number(
                output.get("audioVideoObservedSeconds"), f"{prefix}.output.audioVideoObservedSeconds", failures
            )
            if drift is not None and observed is not None:
                check_strict(
                    {"audioVideoDriftSeconds": drift},
                    {"audioVideoDriftSeconds": 0.020 + 0.040 * observed / 3600},
                    failures,
                    prefix,
                )


def arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument("throughput", nargs="?")
    parser.add_argument("latency", nargs="?")
    parser.add_argument("--capture", action="append", default=[])
    parser.add_argument("--update-baseline", action="store_true")
    return parser.parse_args()


def main():
    args = arguments()
    if bool(args.throughput) != bool(args.latency):
        raise SystemExit("throughput and latency must be provided together")
    if not args.throughput and not args.capture:
        raise SystemExit("provide throughput + latency, --capture, or both")

    failures = []
    if args.throughput:
        with open(args.throughput) as file:
            throughput = json.load(file)
        with open(args.latency) as file:
            latency = json.load(file)

        budgets = dict(ABSOLUTE_BUDGETS["throughput"])
        budgets["cpuPercentOfOneCore"] = CPU_BUDGET_BY_HEIGHT.get(throughput.get("height"), 35)
        drift_budget = 0.040 * max(throughput.get("seconds", 0), 1) / 3600 + 0.020
        budgets["ptsDriftSeconds"] = drift_budget
        check(throughput, budgets, failures, "throughput")
        check(latency, ABSOLUTE_BUDGETS["latency"], failures, "latency")

        try:
            with open(BASELINE_PATH) as file:
                baseline = json.load(file)
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

        if args.update_baseline:
            with open(BASELINE_PATH, "w") as file:
                json.dump(current, file, indent=2, sort_keys=True)
                file.write("\n")
            print(f"baseline updated: {BASELINE_PATH}")
    elif args.update_baseline:
        raise SystemExit("--update-baseline requires throughput and latency")

    for path in args.capture:
        with open(path) as file:
            check_capture(json.load(file), path, failures)

    if failures:
        print("\n".join(failures))
        print(f"\nFAILED: {len(failures)} gate violation(s)")
        return 1

    print("OK: all performance gates passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
