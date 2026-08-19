#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARTIFACT_ROOT="$REPO_ROOT/artifacts/perf"
DERIVED_DATA="$ARTIFACT_ROOT/DerivedData"
APP_PATH="$DERIVED_DATA/Build/Products/Release/RokugaPerf.app"
IDENTITY="Rokuga Dev"
IDENTIFIER="io.rokuga.Rokuga.Perf"
REQUIREMENT_FILE="$ARTIFACT_ROOT/signature.requirement"

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

case "${1:-}" in
    build)
        build
        ;;
    *)
        echo "usage: $0 build" >&2
        exit 2
        ;;
esac
