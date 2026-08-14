#!/usr/bin/env bash
# Zero-copy audit (task 10.1): the record path (capture → composite → encode)
# must never read frame pixels back to the CPU. This static gate fails when CPU
# pixel-access APIs appear in record-path sources. The cursor compositor's tiny
# overlay tile (≤256 px, not the frame) is rasterized on CPU by design and its
# file is allowlisted; frame compositing there goes through CoreImage on Metal.
#
# For the dynamic proof, run:
#   xctrace record --template 'Metal System Trace' --launch rokuga-bench throughput
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
