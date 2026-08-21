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
- [mise](https://mise.jdx.dev/)

## Build from source

```bash
git clone https://github.com/evan-choi/rokuga.git
cd rokuga
mise install
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

See [CONTRIBUTING.md](CONTRIBUTING.md) for the branch, commit, change fragment, and pull request workflow.

Install the repository check tools and run the core test suite:

```bash
mise install
(cd RokugaCore && swift test)
```

Run the repository checks:

```bash
actionlint
swiftlint lint --strict
swiftformat --lint .
mise exec -- bun scripts/lint-localization.ts
mise exec -- bun scripts/audit-zero-copy.ts
```

Record each user-facing change before committing it:

```bash
mise run change
```

## Release cycle

Run the **Cut Release** workflow and select `auto`, `patch`, `minor`, or `major`. `auto` derives the SemVer increment from the unreleased Changie fragments.

The workflow batches the fragments, updates `CHANGELOG.md` and the Xcode project version, then opens a release pull request. Merging that pull request starts the **Release** workflow, which uploads the App Store build, publishes the GitHub release with the same notes, and updates the Homebrew cask.

To retry an existing version without creating another release commit, run the **Release** workflow with that version and enable `deploy`.

## Performance testing

The `RokugaPerf` app in [`Perf`](Perf) exercises the production capture path against a deterministic Retina 4K workload. Run it through `./scripts/perf.sh`; it requires local code signing and Screen Recording permission, so performance measurements do not run in CI.

## License

[Apache License 2.0](LICENSE) © Rokuga contributors
