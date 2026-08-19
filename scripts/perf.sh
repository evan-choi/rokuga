#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARTIFACT_ROOT="$REPO_ROOT/artifacts/perf"
DERIVED_DATA="$ARTIFACT_ROOT/DerivedData"
APP_PATH="$DERIVED_DATA/Build/Products/Release/RokugaPerf.app"
EXECUTABLE="$APP_PATH/Contents/MacOS/RokugaPerf"
IDENTITY="Rokuga Dev"
IDENTIFIER="io.rokuga.Rokuga.Perf"
REQUIREMENT_FILE="$ARTIFACT_ROOT/signature.requirement"
REPORT_TOOL="$REPO_ROOT/scripts/perf-report.py"

WORKLOAD_PID=""
PROFILE_RECORDING_PID=""
PROFILE_TRACE_PID=""
PROFILE_NOTIFY_PID=""
WORKLOAD_MOTION=off
WORKLOAD_AUDIO=off
RECORD_CODEC=hevc
RECORD_FRAME_RATE_MODE=variable
RECORD_SYSTEM_AUDIO=off
RECORD_EFFECTS=off

fail() {
    echo "error: $*" >&2
    exit 1
}

require_identity() {
    security find-identity -v -p codesigning | grep -Fq "\"$IDENTITY\"" \
        || fail "missing '$IDENTITY' signing identity; run ./scripts/setup-dev-signing.sh first"
}

verify_signature() {
    local identifier authority requirement previous
    identifier="$(codesign -dvv "$APP_PATH" 2>&1 | sed -n 's/^Identifier=//p')"
    authority="$(codesign -dvv "$APP_PATH" 2>&1 | sed -n 's/^Authority=//p' | head -1)"
    requirement="$(codesign -dr - "$APP_PATH" 2>&1 | sed -n 's/^designated => //p')"

    [[ "$identifier" == "$IDENTIFIER" ]] || fail "unexpected bundle identifier: $identifier"
    [[ "$authority" == "$IDENTITY" ]] || fail "RokugaPerf must not use ad-hoc signing: $authority"
    [[ -n "$requirement" ]] || fail "missing designated requirement"

    if [[ -f "$REQUIREMENT_FILE" ]]; then
        previous="$(<"$REQUIREMENT_FILE")"
        [[ "$requirement" == "$previous" ]] \
            || fail "code signing requirement changed; refusing to invalidate Screen Recording permission"
    else
        printf '%s\n' "$requirement" > "$REQUIREMENT_FILE"
    fi

    echo "APP_PATH=$APP_PATH"
    echo "SIGNING_REQUIREMENT=$requirement"
}

build() {
    require_identity
    mkdir -p "$ARTIFACT_ROOT"
    xcodebuild build \
        -project "$REPO_ROOT/Rokuga.xcodeproj" \
        -scheme RokugaPerf \
        -configuration Release \
        -derivedDataPath "$DERIVED_DATA" \
        CODE_SIGN_IDENTITY="$IDENTITY"
    [[ -d "$APP_PATH" ]] || fail "build did not produce $APP_PATH"
    verify_signature
}

configure_scenario() {
    case "$1" in
        4k-static)
            WORKLOAD_MOTION=off
            WORKLOAD_AUDIO=off
            RECORD_CODEC=hevc
            RECORD_FRAME_RATE_MODE=variable
            RECORD_SYSTEM_AUDIO=off
            RECORD_EFFECTS=off
            ;;
        4k-motion)
            WORKLOAD_MOTION=on
            WORKLOAD_AUDIO=off
            RECORD_CODEC=hevc
            RECORD_FRAME_RATE_MODE=variable
            RECORD_SYSTEM_AUDIO=off
            RECORD_EFFECTS=off
            ;;
        4k-audio)
            WORKLOAD_MOTION=on
            WORKLOAD_AUDIO=on
            RECORD_CODEC=hevc
            RECORD_FRAME_RATE_MODE=variable
            RECORD_SYSTEM_AUDIO=on
            RECORD_EFFECTS=off
            ;;
        4k-effects)
            WORKLOAD_MOTION=on
            WORKLOAD_AUDIO=off
            RECORD_CODEC=hevc
            RECORD_FRAME_RATE_MODE=variable
            RECORD_SYSTEM_AUDIO=off
            RECORD_EFFECTS=on
            ;;
        4k-cfr-h264)
            WORKLOAD_MOTION=off
            WORKLOAD_AUDIO=off
            RECORD_CODEC=h264
            RECORD_FRAME_RATE_MODE=constant
            RECORD_SYSTEM_AUDIO=off
            RECORD_EFFECTS=off
            ;;
        *)
            fail "unknown scenario: $1 (expected 4k-static, 4k-motion, 4k-audio, 4k-effects, or 4k-cfr-h264)"
            ;;
    esac
}

artifact_directory() {
    local suffix="$1" directory
    directory="$ARTIFACT_ROOT/$(date -u +%Y%m%dT%H%M%SZ)-$suffix"
    if [[ -e "$directory" ]]; then
        directory="$directory-$$"
    fi
    mkdir -p "$directory"
    echo "$directory"
}

collect_environment() {
    python3 "$REPORT_TOOL" environment \
        --repo "$REPO_ROOT" \
        --requirement "$REQUIREMENT_FILE" \
        --output "$1"
}

cleanup_workload() {
    if [[ -n "$WORKLOAD_PID" ]] && kill -0 "$WORKLOAD_PID" 2>/dev/null; then
        kill "$WORKLOAD_PID" 2>/dev/null || true
        wait "$WORKLOAD_PID" 2>/dev/null || true
    fi
    WORKLOAD_PID=""
}

cleanup_profile() {
    if [[ -n "$PROFILE_RECORDING_PID" ]] && kill -0 "$PROFILE_RECORDING_PID" 2>/dev/null; then
        kill -CONT "$PROFILE_RECORDING_PID" 2>/dev/null || true
        kill "$PROFILE_RECORDING_PID" 2>/dev/null || true
    fi
    if [[ -n "$PROFILE_TRACE_PID" ]] && kill -0 "$PROFILE_TRACE_PID" 2>/dev/null; then
        kill "$PROFILE_TRACE_PID" 2>/dev/null || true
    fi
    if [[ -n "$PROFILE_NOTIFY_PID" ]] && kill -0 "$PROFILE_NOTIFY_PID" 2>/dev/null; then
        kill "$PROFILE_NOTIFY_PID" 2>/dev/null || true
    fi
    sleep 0.1
    kill -KILL "$PROFILE_RECORDING_PID" "$PROFILE_TRACE_PID" "$PROFILE_NOTIFY_PID" 2>/dev/null || true
    PROFILE_RECORDING_PID=""
    PROFILE_TRACE_PID=""
    PROFILE_NOTIFY_PID=""
}

start_workload() {
    local directory="$1" attempts=0
    local output="$directory/workload.json"
    local errors="$directory/workload.stderr"

    "$EXECUTABLE" workload \
        --motion "$WORKLOAD_MOTION" \
        --audio "$WORKLOAD_AUDIO" \
        > "$output" 2> "$errors" &
    WORKLOAD_PID=$!

    while ! python3 -c 'import json, sys; json.load(open(sys.argv[1]))' "$output" 2>/dev/null; do
        if ! kill -0 "$WORKLOAD_PID" 2>/dev/null; then
            wait "$WORKLOAD_PID" 2>/dev/null || true
            fail "workload exited before becoming ready; see $errors"
        fi
        attempts=$((attempts + 1))
        [[ "$attempts" -lt 100 ]] || fail "workload did not become ready within 10 seconds"
        sleep 0.1
    done

    python3 -c '
import json, sys
value = json.load(open(sys.argv[1]))
expected_pid = int(sys.argv[2])
if value.get("pid") != expected_pid:
    raise SystemExit("workload PID mismatch: %s != %s" % (value.get("pid"), expected_pid))
if (value.get("widthPixels"), value.get("heightPixels")) != (3840, 2160):
    raise SystemExit("workload is not Retina 4K: %sx%s" % (value.get("widthPixels"), value.get("heightPixels")))
' "$output" "$WORKLOAD_PID" || fail "workload validation failed"
    sleep 1
}

record_arguments() {
    local seconds="$1"
    RECORD_ARGUMENTS=(
        record
        --seconds "$seconds"
        --fps 60
        --codec "$RECORD_CODEC"
        --frame-rate-mode "$RECORD_FRAME_RATE_MODE"
        --system-audio "$RECORD_SYSTEM_AUDIO"
        --effects "$RECORD_EFFECTS"
        --window-pid "$WORKLOAD_PID"
    )
}

finalize_result() {
    local directory="$1" scenario="$2" environment="$3" workload
    if [[ -f "$directory/workload.json" ]]; then
        workload="$directory/workload.json"
    else
        workload="$(dirname "$directory")/workload.json"
    fi
    python3 "$REPORT_TOOL" finalize \
        --result "$directory/result.json" \
        --workload "$workload" \
        --environment "$environment" \
        --asset "$directory/recording.mov" \
        --scenario "$scenario"
}

run_recording() {
    local directory="$1" scenario="$2" seconds="$3" environment="$4" status
    mkdir -p "$directory"
    record_arguments "$seconds"
    if "$EXECUTABLE" "${RECORD_ARGUMENTS[@]}" > "$directory/result.json" 2> "$directory/record.stderr"; then
        status=0
    else
        status=$?
    fi
    if [[ "$status" -eq 77 ]]; then
        fail "Screen Recording permission is missing; run ./scripts/perf.sh permission after explicit approval"
    elif [[ "$status" -ne 0 ]]; then
        fail "recording failed with exit $status; see $directory/record.stderr"
    fi
    finalize_result "$directory" "$scenario" "$environment"
}

parse_experiment_options() {
    SCENARIO=4k-motion
    RECORD_SECONDS=30
    REPEATS=5
    WARMUP=on
    while [[ "$#" -gt 0 ]]; do
        [[ "$#" -ge 2 ]] || fail "missing value for $1"
        case "$1" in
            --scenario) SCENARIO="$2" ;;
            --seconds) RECORD_SECONDS="$2" ;;
            --repeats) REPEATS="$2" ;;
            --warmup) WARMUP="$2" ;;
            *) fail "unknown option: $1" ;;
        esac
        shift 2
    done
    configure_scenario "$SCENARIO"
    python3 -c 'import sys; value=float(sys.argv[1]); assert value > 0 and value <= 86400' "$RECORD_SECONDS" \
        || fail "seconds must be in (0, 86400]"
    [[ "$REPEATS" =~ ^[1-9][0-9]*$ ]] || fail "repeats must be a positive integer"
    [[ "$WARMUP" == on || "$WARMUP" == off ]] || fail "warmup must be on or off"
}

parse_profile_options() {
    SCENARIO=4k-motion
    RECORD_SECONDS=30
    while [[ "$#" -gt 0 ]]; do
        [[ "$#" -ge 2 ]] || fail "missing value for $1"
        case "$1" in
            --scenario) SCENARIO="$2" ;;
            --seconds) RECORD_SECONDS="$2" ;;
            *) fail "unknown option: $1" ;;
        esac
        shift 2
    done
    configure_scenario "$SCENARIO"
    python3 -c 'import sys; value=float(sys.argv[1]); assert value > 0 and value <= 86400' "$RECORD_SECONDS" \
        || fail "seconds must be in (0, 86400]"
}

record_series() {
    local directory environment warmup_seconds index
    parse_experiment_options "$@"
    build
    directory="$(artifact_directory "$SCENARIO")"
    environment="$directory/environment.json"
    collect_environment "$environment"
    trap cleanup_workload EXIT INT TERM
    start_workload "$directory"

    if [[ "$WARMUP" == on ]]; then
        warmup_seconds="$(python3 -c 'import sys; print(min(5, float(sys.argv[1])))' "$RECORD_SECONDS")"
        run_recording "$directory/warmup" "$SCENARIO" "$warmup_seconds" "$environment"
    fi
    index=1
    while [[ "$index" -le "$REPEATS" ]]; do
        run_recording "$directory/run-$(printf '%02d' "$index")" "$SCENARIO" "$RECORD_SECONDS" "$environment"
        index=$((index + 1))
    done
    cleanup_workload
    trap - EXIT INT TERM

    python3 "$REPORT_TOOL" summarize \
        --output "$directory/summary.json" \
        "$directory"/run-*/result.json
    echo "ARTIFACT_PATH=$directory"
}

profile_template() {
    case "$1" in
        time) echo "Time Profiler" ;;
        metal) echo "Metal System Trace" ;;
        allocations) echo "Allocations" ;;
        file) echo "File Activity" ;;
        *) fail "unknown profile: $1 (expected time, metal, allocations, or file)" ;;
    esac
}

profile_recording() {
    local profile="$1" directory environment template time_limit notification
    local attempts=0 record_status trace_status
    shift
    parse_profile_options "$@"
    DevToolsSecurity -status 2>&1 | grep -Fq 'Developer mode is currently enabled.' \
        || fail "Developer Tools access is disabled; run sudo DevToolsSecurity -enable after explicit approval"
    build
    directory="$(artifact_directory "$SCENARIO-$profile")"
    environment="$directory/environment.json"
    collect_environment "$environment"
    trap 'cleanup_profile; cleanup_workload' EXIT INT TERM
    start_workload "$directory"
    record_arguments "$RECORD_SECONDS"
    template="$(profile_template "$profile")"
    time_limit="$(python3 -c 'import sys; print(f"{float(sys.argv[1]) + 20:g}s")' "$RECORD_SECONDS")"

    ROKUGA_PERF_SUSPEND_FOR_PROFILING=1 \
        "$EXECUTABLE" "${RECORD_ARGUMENTS[@]}" \
        > "$directory/result.json" \
        2> "$directory/record.stderr" &
    PROFILE_RECORDING_PID=$!

    notification="$IDENTIFIER.xctrace-started.$$"
    notifyutil -q -1 "$notification" &
    PROFILE_NOTIFY_PID=$!
    sleep 0.1
    xcrun xctrace record --quiet --no-prompt \
        --template "$template" \
        --time-limit "$time_limit" \
        --output "$directory/$profile.trace" \
        --notify-tracing-started "$notification" \
        --attach "$PROFILE_RECORDING_PID" \
        > "$directory/xctrace.stdout" \
        2> "$directory/xctrace.stderr" &
    PROFILE_TRACE_PID=$!

    while kill -0 "$PROFILE_NOTIFY_PID" 2>/dev/null; do
        kill -0 "$PROFILE_TRACE_PID" 2>/dev/null \
            || fail "xctrace exited before tracing started; see $directory/xctrace.stderr"
        attempts=$((attempts + 1))
        [[ "$attempts" -lt 300 ]] \
            || fail "xctrace did not start within 30 seconds; see $directory/xctrace.stderr"
        sleep 0.1
    done
    wait "$PROFILE_NOTIFY_PID"
    PROFILE_NOTIFY_PID=""
    kill -CONT "$PROFILE_RECORDING_PID"

    if wait "$PROFILE_RECORDING_PID"; then
        record_status=0
    else
        record_status=$?
    fi
    PROFILE_RECORDING_PID=""
    if wait "$PROFILE_TRACE_PID"; then
        trace_status=0
    else
        trace_status=$?
    fi
    PROFILE_TRACE_PID=""

    if [[ "$record_status" -eq 77 ]]; then
        fail "Screen Recording permission is missing; run ./scripts/perf.sh permission after explicit approval"
    elif [[ "$record_status" -ne 0 ]]; then
        fail "recording failed with exit $record_status; see $directory/record.stderr"
    fi
    if [[ "$trace_status" -ne 0 ]]; then
        grep -Fq 'Fatal logging system error: The log archive is corrupt or incomplete' \
            "$directory/xctrace.stderr" \
            || fail "xctrace failed with exit $trace_status; see $directory/xctrace.stderr"
        python3 -c 'import json, sys; json.load(open(sys.argv[1]))' "$directory/result.json" \
            || fail "xctrace failed with exit $trace_status before recording completed; see $directory/xctrace.stderr"
        echo "warning: xctrace exited with $trace_status after producing a result; validating the trace export" >&2
    fi
    finalize_result "$directory" "$SCENARIO" "$environment"
    xcrun xctrace export --quiet \
        --input "$directory/$profile.trace" \
        --toc \
        --output "$directory/trace-toc.xml"
    python3 -c '
import sys, xml.etree.ElementTree as ET
process = ET.parse(sys.argv[1]).find(".//target/process")
if process is None or process.get("type") != "attached" or process.get("name") != "RokugaPerf":
    raise SystemExit("trace did not attach to RokugaPerf")
if process.get("return-exit-status") != "0":
    raise SystemExit("profiled recording did not exit successfully")
' "$directory/trace-toc.xml" || fail "trace target validation failed; see $directory/trace-toc.xml"
    if [[ "$profile" == time ]]; then
        xcrun xctrace export --quiet \
            --input "$directory/time.trace" \
            --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' \
            --output "$directory/time-profile.xml"
        python3 "$REPORT_TOOL" hot-symbols \
            --input "$directory/time-profile.xml" \
            --output "$directory/hot-functions.json"
    fi
    cleanup_workload
    trap - EXIT INT TERM
    echo "ARTIFACT_PATH=$directory"
}

comparison() {
    local baseline="$1" candidate="$2" directory
    [[ -d "$baseline" ]] && baseline="$baseline/summary.json"
    [[ -d "$candidate" ]] && candidate="$candidate/summary.json"
    [[ -f "$baseline" ]] || fail "baseline summary not found: $baseline"
    [[ -f "$candidate" ]] || fail "candidate summary not found: $candidate"
    directory="$(artifact_directory compare)"
    python3 "$REPORT_TOOL" compare \
        --baseline "$baseline" \
        --candidate "$candidate" \
        --output "$directory/comparison.json"
    echo "ARTIFACT_PATH=$directory"
}

usage() {
    cat >&2 <<'EOF'
usage:
  ./scripts/perf.sh build
  ./scripts/perf.sh check-permission
  ./scripts/perf.sh permission
  ./scripts/perf.sh record [--scenario NAME] [--seconds N] [--repeats N] [--warmup on|off]
  ./scripts/perf.sh profile time|metal|allocations|file [--scenario NAME] [--seconds N]
  ./scripts/perf.sh compare BASELINE_ARTIFACT CANDIDATE_ARTIFACT
  ./scripts/perf.sh scenarios
EOF
}

case "${1:-}" in
    build)
        build
        ;;
    check-permission)
        build
        "$EXECUTABLE" check-permission
        ;;
    permission)
        build
        "$EXECUTABLE" permission
        ;;
    record)
        shift
        record_series "$@"
        ;;
    profile)
        [[ "$#" -ge 2 ]] || fail "profile name is required"
        profile="$2"
        shift 2
        profile_recording "$profile" "$@"
        ;;
    compare)
        [[ "$#" -eq 3 ]] || fail "compare requires baseline and candidate artifact paths"
        comparison "$2" "$3"
        ;;
    scenarios)
        printf '%s\n' 4k-static 4k-motion 4k-audio 4k-effects 4k-cfr-h264
        ;;
    *)
        usage
        exit 2
        ;;
esac
