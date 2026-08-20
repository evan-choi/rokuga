<div align="center">

# <picture><source media="(prefers-color-scheme: dark)" srcset="docs/wordmark-dark.png"><img src="docs/wordmark-light.png" width="159" alt="Rokuga"></picture>

**A free, native, open-source screen recorder for macOS.**

*録画 — "screen recording" in Japanese.*

No watermarks. No time limits. No accounts. No paywalls.

[![CI](https://github.com/evan-choi/rokuga/actions/workflows/ci.yml/badge.svg)](https://github.com/evan-choi/rokuga/actions/workflows/ci.yml)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-macOS%2015%2B-black?logo=apple)](https://www.apple.com/macos/)

</div>

> Rokuga is under active development. There is no signed public build yet, but the app can be built from source.

## Why Rokuga?

Rokuga runs as a menu bar app with a floating recording toolbar instead of a library window. It records directly to a Finder folder using ScreenCaptureKit and AVFoundation.

## Current capabilities

- Selected-area, full-screen, and individual-window capture
- Driver-free system audio and microphone capture, mixed into one AAC track by default or written as separate MP4/MOV tracks for editing
- H.264 and HEVC encoding to MP4 or MOV at up to 5K, with 30/60 fps or display-matched capture
- Cursor visibility and native macOS click indicators
- Floating post-recording thumbnail, preview panel, and trim editor
- Capture exclusion for Rokuga windows and optional desktop-icon exclusion
- English, Korean, Japanese, and Simplified Chinese localization

### Known limitations

- Selected-area recording supports a movable, resizable crop. Drawing a new marquee and the pixel loupe remain in progress.

## Requirements

To run Rokuga:

- macOS 15 (Sequoia) or later
- Screen Recording permission

To build Rokuga:

- Xcode 26
- XcodeGen

## Build from source

```bash
brew install xcodegen
git clone https://github.com/evan-choi/rokuga.git
cd rokuga
xcodegen generate
open Rokuga.xcodeproj
```

The default ad-hoc signature does not require an Apple account. For repeated local builds, run `./scripts/setup-dev-signing.sh` once so macOS keeps Screen Recording permission between builds.

## Usage

1. Press <kbd>⌘⇧6</kbd> or choose **Open Recording Toolbar** from the menu bar.
2. Choose a recording mode and configure its options.
3. Start from the toolbar, or click the active Full Screen or Window selection.
4. Stop from the elapsed-time control in the menu bar, then use the thumbnail to preview or trim the file.

<kbd>Esc</kbd> closes the toolbar, cancels an active countdown, or closes the preview.

## Development

Install the repository check tools and run the core test suite:

```bash
brew install swiftlint swiftformat
(cd RokugaCore && swift test)
```

Run the repository checks:

```bash
swiftlint lint --strict
swiftformat --lint .
python3 scripts/lint-localization.py
./scripts/audit-zero-copy.sh
```

## Performance testing

The `RokugaPerf` app in [`Perf`](Perf) exercises the production capture path against a deterministic Retina 4K workload. Run it through `./scripts/perf.sh`; it requires local code signing and Screen Recording permission, so performance measurements do not run in CI.

## License

[Apache License 2.0](LICENSE) © Rokuga contributors
