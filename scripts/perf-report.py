#!/usr/bin/env python3
"""Artifact and statistics helpers for scripts/perf.sh (stdlib only)."""

import argparse
import datetime as dt
import json
import math
import os
import platform
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from statistics import median


METRICS = (
    "cpuPercentOfOneCore",
    "peakMemoryMB",
    "steadyMemoryMB",
    "memoryGrowthMBPerSecond",
    "recordToFirstFrameSeconds",
    "stopToPlayableSeconds",
    "derived.dropRate",
    "derived.outputFPS",
    "capture.incompleteVideoFrames",
    "capture.gapPTS",
    "capture.duplicatePTS",
    "capture.averageCompositeSeconds",
    "capture.maxCompositeSeconds",
    "writer.averageQueueWaitSeconds",
    "writer.maxQueueWaitSeconds",
    "output.gapPTS",
    "output.duplicatePTS",
    "output.audioVideoDriftSeconds",
    "output.fileSizeBytes",
)

HIGHER_IS_BETTER = {"derived.outputFPS"}
COMPARABLE_METRICS = set(METRICS) - {"output.fileSizeBytes"}
RECORDING_CONFIGURATION = (
    "target", "width", "height", "fps", "seconds", "codec",
    "frameRateMode", "systemAudio", "effects",
)
WORKLOAD_CONFIGURATION = (
    "widthPoints", "heightPoints", "backingScale", "widthPixels",
    "heightPixels", "motion", "audio",
)
HOST_CONFIGURATION = (
    "hardwareModel", "logicalCPUCount", "physicalCPUCount",
    "physicalMemoryBytes", "machine", "macOSProductVersion",
    "macOSBuildVersion", "kernel", "xcode", "signingRequirement",
)


def read_json(path):
    with open(path, encoding="utf-8") as file:
        return json.load(file)


def write_json(path, value):
    path = Path(path)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.replace(temporary, path)


def command_output(*command):
    return subprocess.run(command, check=True, text=True, capture_output=True).stdout.strip()


def sysctl(name):
    return command_output("sysctl", "-n", name)


def environment(args):
    repo = Path(args.repo).resolve()
    signature = Path(args.requirement).read_text(encoding="utf-8").strip()
    value = {
        "createdAtUTC": dt.datetime.now(dt.timezone.utc).isoformat(),
        "gitCommit": command_output("git", "-C", str(repo), "rev-parse", "HEAD"),
        "gitDirty": bool(command_output("git", "-C", str(repo), "status", "--porcelain")),
        "hardwareModel": sysctl("hw.model"),
        "logicalCPUCount": int(sysctl("hw.logicalcpu")),
        "physicalCPUCount": int(sysctl("hw.physicalcpu")),
        "physicalMemoryBytes": int(sysctl("hw.memsize")),
        "machine": platform.machine(),
        "macOSProductVersion": command_output("sw_vers", "-productVersion"),
        "macOSBuildVersion": command_output("sw_vers", "-buildVersion"),
        "kernel": platform.release(),
        "xcode": command_output("xcodebuild", "-version"),
        "signingRequirement": signature,
    }
    write_json(args.output, value)


def finalize(args):
    result = read_json(args.result)
    workload = read_json(args.workload)
    environment_value = read_json(args.environment)
    source = Path(result["outputPath"])
    destination = Path(args.asset).resolve()
    if not source.is_file():
        raise FileNotFoundError(f"recording output is missing: {source}")
    if destination.exists():
        raise FileExistsError(f"refusing to overwrite recording: {destination}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(source), destination)

    writer = result["writer"]
    attempts = writer["videoFramesAppended"] + writer["videoFramesDropped"]
    output = result["output"]
    duration = output["durationSeconds"]
    result.update({
        "scenario": args.scenario,
        "outputPath": str(destination),
        "workload": workload,
        "environment": environment_value,
        "derived": {
            "dropRate": writer["videoFramesDropped"] / attempts if attempts else 0,
            "outputFPS": output["videoFrames"] / duration if duration > 0 else 0,
            "incompleteFrameRate": (
                result["capture"]["incompleteVideoFrames"] / result["capture"]["videoCallbacks"]
                if result["capture"]["videoCallbacks"] else 0
            ),
        },
    })
    write_json(args.result, result)


def value_at_path(value, path):
    for component in path.split("."):
        if not isinstance(value, dict) or component not in value:
            return None
        value = value[component]
    return value if isinstance(value, (int, float)) and not isinstance(value, bool) else None


def experiment_signature(run):
    workload = run.get("workload", {})
    environment_value = run.get("environment", {})
    return {
        "scenario": run.get("scenario"),
        "recording": {key: run.get(key) for key in RECORDING_CONFIGURATION},
        "workload": {key: workload.get(key) for key in WORKLOAD_CONFIGURATION},
        "host": {key: environment_value.get(key) for key in HOST_CONFIGURATION},
    }


def percentile(values, fraction):
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    position = (len(ordered) - 1) * fraction
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return ordered[lower]
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (position - lower)


def summarize(args):
    runs = [read_json(path) for path in args.results]
    signature = experiment_signature(runs[0])
    if any(experiment_signature(run) != signature for run in runs[1:]):
        raise ValueError("result configurations differ")
    git_commit = runs[0].get("environment", {}).get("gitCommit")
    if not git_commit or any(
        run.get("environment", {}).get("gitCommit") != git_commit for run in runs[1:]
    ):
        raise ValueError("results come from different git commits")
    metrics = {}
    for path in METRICS:
        values = [value_at_path(run, path) for run in runs]
        if any(value is None for value in values):
            continue
        metrics[path] = {
            "median": median(values),
            "p95": percentile(values, 0.95),
            "min": min(values),
            "max": max(values),
            "values": values,
        }
    write_json(args.output, {
        "scenario": runs[0].get("scenario") if runs else None,
        "runCount": len(runs),
        "experiment": signature,
        "gitCommit": git_commit,
        "gitDirty": any(run.get("environment", {}).get("gitDirty", True) for run in runs),
        "results": [str(Path(path).resolve()) for path in args.results],
        "metrics": metrics,
    })


def compare(args):
    baseline = read_json(args.baseline)
    candidate = read_json(args.candidate)
    if baseline.get("scenario") != candidate.get("scenario"):
        raise ValueError(
            f"scenario mismatch: {baseline.get('scenario')} != {candidate.get('scenario')}"
        )
    if not baseline.get("experiment") or baseline["experiment"] != candidate.get("experiment"):
        raise ValueError("experiment configuration mismatch")
    for name, summary in (("baseline", baseline), ("candidate", candidate)):
        if summary.get("runCount", 0) < 5:
            raise ValueError(f"{name} requires at least 5 runs")
    comparisons = {}
    for path in sorted(set(baseline["metrics"]) & set(candidate["metrics"]) & COMPARABLE_METRICS):
        before = baseline["metrics"][path]["median"]
        after = candidate["metrics"][path]["median"]
        before_p95 = baseline["metrics"][path]["p95"]
        after_p95 = candidate["metrics"][path]["p95"]
        higher_is_better = path in HIGHER_IS_BETTER

        def change(reference, current):
            delta = current - reference if higher_is_better else reference - current
            improvement = delta / abs(reference) * 100 if reference else (0 if current == reference else None)
            worse = current < reference if higher_is_better else current > reference
            return improvement, worse and (improvement is None or improvement < -10)

        improvement, median_regression = change(before, after)
        p95_improvement, p95_regression = change(before_p95, after_p95)
        comparisons[path] = {
            "baselineMedian": before,
            "candidateMedian": after,
            "baselineP95": before_p95,
            "candidateP95": after_p95,
            "higherIsBetter": higher_is_better,
            "improvementPercent": improvement,
            "p95ImprovementPercent": p95_improvement,
            "meaningfulImprovement": improvement is not None and improvement >= 3 and not p95_regression,
            "regressionOver10Percent": median_regression or p95_regression,
        }
    output = {
        "baseline": str(Path(args.baseline).resolve()),
        "candidate": str(Path(args.candidate).resolve()),
        "comparisons": comparisons,
    }
    write_json(args.output, output)
    for path, value in comparisons.items():
        percent = value["improvementPercent"]
        p95_percent = value["p95ImprovementPercent"]
        median_change = "n/a" if percent is None else f"{percent:+.2f}%"
        p95_change = "n/a" if p95_percent is None else f"{p95_percent:+.2f}%"
        print(
            f"{path}: median {value['baselineMedian']:.6g} -> {value['candidateMedian']:.6g} ({median_change}); "
            f"p95 {value['baselineP95']:.6g} -> {value['candidateP95']:.6g} ({p95_change})"
        )


def local_name(element):
    return element.tag.rsplit("}", 1)[-1]


def numeric_weight(element):
    text = element.get("fmt") or element.get("value") or (element.text or "")
    parts = text.strip().split()
    try:
        value = float(parts[0].replace(",", ""))
    except (ValueError, IndexError):
        return None
    unit = parts[1] if len(parts) > 1 else ""
    return value * {"ns": 1e-9, "us": 1e-6, "µs": 1e-6, "ms": 1e-3, "s": 1}.get(unit, 1)


def hot_symbols(args):
    root = ET.parse(args.input).getroot()
    by_id = {element.get("id"): element for element in root.iter() if element.get("id")}

    def resolved(element):
        return by_id.get(element.get("ref"), element)

    def app_owned_name(element):
        frame = resolved(element)
        name = frame.get("name") or frame.get("symbol") or (frame.text or "").strip()
        binaries = [frame.get("binary"), frame.get("module")]
        for child in frame:
            if local_name(child) != "binary":
                continue
            binary = resolved(child)
            binaries.extend((binary.get("name"), binary.get("path")))
        ownership = " ".join(value for value in (name, *binaries) if value)
        return name if name and args.binary.lower() in ownership.lower() else None

    weights = {}
    total = 0.0
    rows = [element for element in root.iter() if local_name(element) == "row"]
    for row in rows:
        weight = next(
            (numeric_weight(resolved(element)) for element in row.iter() if local_name(element) == "weight"),
            None,
        )
        weight = weight if weight is not None else 1.0
        total += weight
        frames = []
        backtraces = [element for element in row.iter() if local_name(element) == "backtrace"]
        for backtrace in backtraces:
            for element in resolved(backtrace).iter():
                if local_name(element) != "frame":
                    continue
                if name := app_owned_name(element):
                    frames.append(name)
        if not backtraces:
            for element in row.iter():
                if local_name(element) != "frame":
                    continue
                if name := app_owned_name(element):
                    frames.append(name)
        for name in set(frames):
            weights[name] = weights.get(name, 0) + weight

    symbols = [
        {"symbol": name, "inclusiveWeight": weight, "percent": weight / total * 100 if total else 0}
        for name, weight in weights.items()
    ]
    symbols.sort(key=lambda value: value["inclusiveWeight"], reverse=True)
    selected = [value for index, value in enumerate(symbols) if index < 20 or value["percent"] >= 1]
    write_json(args.output, {
        "binaryFilter": args.binary,
        "rowCount": len(rows),
        "totalWeight": total,
        "symbols": selected,
    })


def parser():
    root = argparse.ArgumentParser()
    commands = root.add_subparsers(dest="command", required=True)

    command = commands.add_parser("environment")
    command.add_argument("--repo", required=True)
    command.add_argument("--requirement", required=True)
    command.add_argument("--output", required=True)
    command.set_defaults(function=environment)

    command = commands.add_parser("finalize")
    command.add_argument("--result", required=True)
    command.add_argument("--workload", required=True)
    command.add_argument("--environment", required=True)
    command.add_argument("--asset", required=True)
    command.add_argument("--scenario", required=True)
    command.set_defaults(function=finalize)

    command = commands.add_parser("summarize")
    command.add_argument("--output", required=True)
    command.add_argument("results", nargs="+")
    command.set_defaults(function=summarize)

    command = commands.add_parser("compare")
    command.add_argument("--baseline", required=True)
    command.add_argument("--candidate", required=True)
    command.add_argument("--output", required=True)
    command.set_defaults(function=compare)

    command = commands.add_parser("hot-symbols")
    command.add_argument("--input", required=True)
    command.add_argument("--output", required=True)
    command.add_argument("--binary", default="RokugaPerf")
    command.set_defaults(function=hot_symbols)
    return root


def main():
    args = parser().parse_args()
    try:
        args.function(args)
    except Exception as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
