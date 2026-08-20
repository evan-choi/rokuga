#!/usr/bin/env bash
# Zero-copy audit (task 10.1): the record path (capture → encode)
# must never read frame pixels back to the CPU. This static gate fails when CPU
# pixel-access APIs appear in record-path sources.
#
# For the dynamic proof, run:
#   ./scripts/perf.sh profile metal --scenario 4k-motion --seconds 10
# and verify no CVPixelBuffer lock intervals on the capture/encode queues.
set -euo pipefail

cd "$(dirname "$0")/.."

RECORD_PATH_SOURCES=(
    RokugaCore/Sources/CaptureKit
    RokugaCore/Sources/EncoderKit
)
FORBIDDEN='CVPixelBufferLockBaseAddress|CVPixelBufferGetBaseAddress|vImage|CGBitmapContextCreate'

violations=$(grep -rnE "$FORBIDDEN" "${RECORD_PATH_SOURCES[@]}" --include='*.swift' || true)

if [[ -n "$violations" ]]; then
    echo "$violations"
    echo "FAILED: CPU pixel readback detected in the record path"
    exit 1
fi

echo "OK: no CPU pixel readback APIs in the record path"
