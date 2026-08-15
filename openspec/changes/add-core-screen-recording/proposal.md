# Proposal: add-core-screen-recording

## Why

macOS users currently choose between the bare-bones built-in screenshot toolbar and paid subscription screen recorders that lock essential features (unlimited recording time, trimming, ad-free use) behind a paywall. Rokuga is a free, MIT-licensed, native macOS screen recorder that delivers the full professional recording feature set with no time limits, no watermarks, no ads, and no accounts — all processing stays on the user's machine.

This change establishes the core product: three recording modes, system/microphone audio capture, mouse effects, built-in trim editing, professional output controls, and the surrounding windowless app experience (permissions onboarding, countdown, hotkeys, menu bar control, capture exclusion, native glass UI) — with performance budgets specified and CI-enforced.

## What Changes

- New macOS app (Swift/SwiftUI, macOS 13.3+) with a **windowless UI**: a ⇧⌘5-style floating recording toolbar (menu bar agent app, no main window, no Dock icon) offering three recording modes:
  - **Selected area**: drag-to-select region with resizable edges/corners and a pixel-loupe magnifier
  - **Full screen**: entire display capture with multi-display selection
  - **Window**: single application window capture, isolated from overlapping windows
- System audio capture with no driver installation, plus microphone capture with device selection; both independently toggleable and recordable simultaneously
- Mouse effects rendered into recordings: cursor visibility toggle, pointer style (system cursor or dot), highlight halo, and click animations
- Built-in lossless trim editor: select the range to keep, save as a new file with custom name and destination
- Professional output controls: MP4/MOV containers, H.264/HEVC codecs, VBR/CBR rate control, quality 0–100, resolution cap up to 5K (5120×2880), up to 60 FPS, AAC audio at 128–320 kbps
- Recording lifecycle controls: record from the toolbar (summoned via menu bar or ⇧⌘6 at the bottom-center of the display under the mouse); while recording the toolbar disappears and the menu bar shows the system-native indicator (red dot, elapsed time, pause/stop); configurable 1–10 second countdown, global keyboard shortcuts (toolbar ⇧⌘6, start/stop ⇧⌘2, pause/resume ⇧⌘4 — all reconfigurable)
- Performance as a requirement, not a hope: zero-copy GPU pipeline (ScreenCaptureKit → Metal → VideoToolbox), < 0.1% dropped frames at 4K60 on baseline Apple Silicon, bounded memory, no system lag while recording, CI-enforced budgets
- Capture exclusion: hide the app's own windows and/or desktop icons from recordings
- Post-recording delivery: recordings save straight to the output folder (Finder is the library — no library window); a floating thumbnail appears briefly and expands into a preview panel (play/scrub + Edit/Delete/Done) when clicked — Edit opens the trim editor; M4A audio extraction via the trim editor's export options
- First-run experience: output folder selection and guided permission flows (screen & system audio recording, microphone)
- App preferences: settings window reachable only from the menu bar icon menu (⌘,) — theme, launch at login, floating-thumbnail toggle, reset all settings; Liquid Glass native materials across all surfaces (blur-material fallback on macOS 13.3–15)
- Localization: English (base), Korean, Japanese, Simplified Chinese — 100% string coverage enforced in CI; accessibility: VoiceOver, keyboard-only operation, Reduce Transparency/Motion honored

Out of scope for this change (planned as follow-ups): webcam/camera recording of any kind (standalone or PIP overlay), real-time drawing/annotation, AI transcription/subtitles, sharing integrations (AirDrop/cloud links), scheduled recording, GIF export.

## Capabilities

### New Capabilities

- `recording-modes`: The three capture modes (selected area, full screen, window), their selection UI, target pickers, and per-mode behavior
- `recording-controls`: Recording lifecycle (start/pause/resume/stop), countdown, global hotkeys, menu bar status item controls, and recording state feedback
- `audio-capture`: System audio and microphone capture, device selection, toggles, mixing into the recording, and failure/permission states
- `mouse-effects`: Cursor rendering in recordings, pointer style, highlight halo, and click effect options
- `video-trimming`: Keep-range trim editing of recordings, preview scrubbing, and lossless export of the trimmed result
- `output-settings`: Container/codec/rate-control/quality/resolution/FPS/audio-bitrate configuration and output folder management
- `capture-exclusion`: Excluding the app's own windows and desktop icons from captured content
- `post-recording`: Windowless post-recording delivery — save-to-folder, floating thumbnail, notifications, and Finder/menu-bar access to recordings
- `performance`: Measurable performance budgets — zero-copy pipeline, frame integrity, system responsiveness, interaction latency, and CI regression gates
- `localization`: Full localization in English (base), Korean, Japanese, and Simplified Chinese — String Catalogs, system language resolution, locale-aware formatting, CJK layout QA
- `permissions-onboarding`: First-run output folder selection and guided macOS permission acquisition/recovery flows
- `app-preferences`: General app options — theme, launch at login, post-recording behavior, settings reset

### Modified Capabilities

_None — this is the first change; no existing specs._

## Impact

- **New codebase**: Xcode project, Swift 5.9+/SwiftUI app target, sandboxed for future Mac App Store distribution
- **System frameworks**: ScreenCaptureKit (screen/window/audio capture), AVFoundation (mic, asset writing/export), VideoToolbox (hardware H.264/HEVC encoding), CoreGraphics/AppKit (region selection overlays, menu bar)
- **Entitlements/Info.plist**: screen capture, microphone usage descriptions; security-scoped bookmarks for the user-chosen output folder; login item helper
- **Minimum OS**: macOS 13.3 (Ventura) — required for driver-free system audio capture via ScreenCaptureKit
- **No network dependencies**: all recording, encoding, and editing is fully local
