<div align="center">

# <picture><source media="(prefers-color-scheme: dark)" srcset="docs/wordmark-dark.png"><img src="docs/wordmark-light.png" width="159" alt="Rokuga"></picture>

**A free, native, open-source screen recorder for macOS.**

*録画 — "screen recording" in Japanese.*

No watermarks. No time limits. No accounts. No paywalls.

[![CI](https://github.com/evan-choi/rokuga/actions/workflows/ci.yml/badge.svg)](https://github.com/evan-choi/rokuga/actions/workflows/ci.yml)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-macOS%2013.3%2B-black?logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Status](https://img.shields.io/badge/Status-Pre--release-yellow)](#project-status)

</div>

> Rokuga is under active development. There is no signed public build yet, but the app can be built from source.

## Why Rokuga?

Rokuga uses Apple's screen capture and media frameworks directly. It runs as a menu bar app and writes recordings to a folder chosen by the user.

- Native Swift and SwiftUI app using ScreenCaptureKit and AVFoundation
- Floating recording toolbar instead of a main library window
- Recordings stay in a normal Finder folder
- No account, network service, watermark, or recording limit

## Current capabilities

- Selected-area, full-screen, and individual-window capture
- Driver-free system audio capture, independently toggleable and excluded from Rokuga's own sounds
- H.264 and HEVC encoding to MP4 or MOV at up to 5K and 60 fps
- Cursor visibility, cursor highlight, and click effects rendered into the recording
- Floating post-recording thumbnail, preview panel, and trim editor
- Capture exclusion for Rokuga windows and optional desktop-icon exclusion
- English, Korean, Japanese, and Simplified Chinese localization

See [the implementation task list](openspec/changes/add-core-screen-recording/tasks.md) for the current status of each capability.

### Known limitations

- Microphone capture and system-audio/microphone mixing are not connected to the recording session yet.
- Selected-area recording supports a movable, resizable crop. Drawing a new marquee, Retina pixel labels, and the pixel loupe remain in progress.
- Release signing, notarization, and the full hardware and macOS QA matrix are not complete.

## Requirements

To run Rokuga:

- macOS 13.3 (Ventura) or later
- Screen Recording permission

To build Rokuga:

- Xcode 16
- XcodeGen

SwiftLint and SwiftFormat are required only for the same checks used by CI.

## Build from source

```bash
brew install xcodegen swiftlint swiftformat
git clone https://github.com/evan-choi/rokuga.git
cd rokuga
xcodegen generate
open Rokuga.xcodeproj
```

The default ad-hoc signature does not require an Apple account. macOS may reset Screen Recording and Microphone permissions after each rebuild. Run `./scripts/setup-dev-signing.sh` once to create a local self-signed identity and keep permissions between builds.

## Usage

1. Press <kbd>⌘⇧6</kbd> or choose **Open Recording Toolbar** from the menu bar.
2. Choose Selected Area, Full Screen, or Window.
3. Set the countdown, system audio, output, and cursor options.
4. Start from the toolbar or the active Full Screen or Window selection layer.
5. Stop from the elapsed-time control in the menu bar.
6. Use the post-recording thumbnail to preview, trim, delete, or keep the file.

<kbd>Esc</kbd> closes the toolbar, cancels an active countdown, or closes the preview. Rokuga has no global recording start/stop shortcut.

## Project status

The app shell, recording pipeline, three capture modes, system audio output, post-recording flow, and trim editor are implemented. Unit tests cover the core state machine, encoder, audio output, effects, settings, and trim operations. CI builds the app and runs tests on macOS 14 and 15.

Rokuga is still pre-release. Remaining work is tracked in [`openspec/changes/add-core-screen-recording/tasks.md`](openspec/changes/add-core-screen-recording/tasks.md); the unchecked items are not considered complete.

## Development

Run the core test suite:

```bash
(cd RokugaCore && swift test)
```

Run the repository checks:

```bash
swiftlint lint --strict
swiftformat --lint .
python3 scripts/lint-localization.py
./scripts/audit-zero-copy.sh
```

Browse the design mockups with `open design/mockups/index.html`.

## Contributing

Read the active change under [`openspec/changes/add-core-screen-recording/`](openspec/changes/add-core-screen-recording/) before changing behavior. Update the relevant spec and task status with the implementation, then run the tests and repository checks above before opening a pull request.

## License

[Apache License 2.0](LICENSE) © Rokuga contributors
