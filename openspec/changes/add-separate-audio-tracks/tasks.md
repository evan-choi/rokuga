## 1. Settings contract

- [x] 1.1 Add `AudioTrackLayout` with a Mixed default, persist it in `SettingsStore`, and cover default, round-trip, reset, and unknown-value fallback in SettingsKit tests.
- [x] 1.2 Snapshot the layout in `EncoderConfiguration` and normalize Separate to Mixed for MP4 while preserving Separate for MOV recordings with one or two enabled sources.
- [x] 1.3 Add the Mixed/Separate control to Settings › Audio, disable Separate for MP4, reset Separate to Mixed when the container changes to MP4, lock the control during recording, and add complete en/ko/ja/zh-Hans strings and guidance.

## 2. Writer routing

- [x] 2.1 Refactor `AssetWriterSink` audio-input setup to reuse the existing single input and mixer in Mixed mode and create independent system/microphone inputs in Separate mode without adding a dependency or capture queue.
- [x] 2.2 Route separate samples only to their matching inputs, preserve source PTS through the shared splice offset, apply the configured AAC bitrate to each input, and write deterministic system-then-microphone order with locale-neutral track titles.
- [x] 2.3 Finish or cancel every created audio input with the video input, preserve the remaining source when one input stops receiving samples, and remove partial output after start or cancel failure.

## 3. Behavioral verification

- [x] 3.1 Extend asset-writer integration tests for no audio, each single source, both Mixed sources, and both Separate sources; assert container, track count, order, titles, 48 kHz format, and per-track bitrate configuration.
- [x] 3.2 Add distinct system/microphone signal fixtures and decode separate output to verify source isolation while retaining the existing Mixed audibility test.
- [x] 3.3 Add pause/resume, backpressure, finish, start-failure, and cancel coverage for two audio inputs, including shared A/V splice timing and partial-file cleanup.

## 4. Documentation and gates

- [x] 4.1 Update README audio capabilities to describe Mixed as the default and Separate as a MOV editing option.
- [x] 4.2 Run `swift test`, unsigned `xcodebuild`, SwiftLint, SwiftFormat, localization checks, `git diff --check`, and `openspec validate add-separate-audio-tracks --strict`.
