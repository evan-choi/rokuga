#!/usr/bin/env bash
# CJK layout QA (task 9a.4): renders toolbar/popover/settings/editor in all
# supported languages and drops PNGs under artifacts/l10n/<lang>/.
set -euo pipefail

cd "$(dirname "$0")/.."

APP="${APP:-$(find ~/Library/Developer/Xcode/DerivedData -path '*Build/Products/Debug/Rokuga.app' -print -quit)}"
if [[ -z "$APP" || ! -d "$APP" ]]; then
    echo "Rokuga.app not found — build first (xcodebuild -scheme Rokuga)" >&2
    exit 1
fi

OUT="${OUT:-artifacts/l10n}"
BIN="$APP/Contents/MacOS/Rokuga"

for lang in en ko ja zh-Hans; do
    mkdir -p "$OUT/$lang"
    src=$("$BIN" -AppleLanguages "($lang)" --l10n-screenshots "$lang" | sed -n 's/^L10N_OUT=//p')
    [[ -n "$src" && -d "$src" ]] || { echo "no output dir for $lang" >&2; exit 1; }
    cp "$src"/*.png "$OUT/$lang/"
    count=$(find "$OUT/$lang" -name '*.png' | wc -l | tr -d ' ')
    echo "$lang: $count screenshots"
    [[ "$count" -eq 4 ]] || { echo "expected 4 screenshots for $lang" >&2; exit 1; }
done

echo "OK: $(find "$OUT" -name '*.png' | wc -l | tr -d ' ') screenshots under $OUT"
