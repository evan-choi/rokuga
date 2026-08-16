# Proposal: add-core-screen-recording

## Why

Rokuga is a free, Apache-2.0-licensed native macOS screen recorder with no time limits, watermarks, ads, accounts, or network processing. It combines screen capture, local encoding, post-recording preview, and trim editing in a menu bar app.

This change defines the core product: three recording modes, system and microphone audio, mouse effects, built-in trim editing, output controls, permissions onboarding, countdown, a toolbar shortcut, menu bar control, capture exclusion, and native glass UI. It also defines measurable performance budgets.

`tasks.md` is the implementation-status source of truth. Checked items have implementation evidence; unchecked items remain part of the target contract but are not complete.

## What Changes

- New macOS app (Swift/SwiftUI, macOS 13.3+) with a **windowless UI**: a ⇧⌘5-style floating recording toolbar (menu bar agent app, no main window, no Dock icon) offering three recording modes:
  - **Selected area**: drag-to-select region with resizable edges/corners and a pixel-loupe magnifier
  - **Full screen**: entire display capture with multi-display selection
  - **Window**: single application window capture, isolated from overlapping windows
- System audio capture with no driver installation, plus microphone capture with device selection; both independently toggleable and recordable simultaneously
- Mouse effects rendered into recordings: cursor visibility toggle, pointer style (system cursor or dot), highlight halo, and click animations
- Built-in lossless trim editor: select the range to keep, save as a new file with custom name and destination
- Output controls: MP4/MOV containers, H.264/HEVC codecs, VBR/CBR rate control, quality 0–100, resolution cap up to 5K (5120×2880), up to 60 FPS, AAC audio at 128–320 kbps
- Recording lifecycle controls: record from the toolbar (summoned via menu bar or ⇧⌘6 at the bottom-center of the display under the mouse); while recording the toolbar disappears and the menu bar shows elapsed time with a one-click stop control; countdown choices are off, 3, 5, or 10 seconds
- Performance contract: no full-frame CPU readback, < 0.1% dropped frames at 4K60 on baseline Apple Silicon, bounded memory, interaction latency budgets, and regression gates tracked in `tasks.md`
- Capture exclusion: always hide the app's own windows; optionally hide desktop icons from Selected Area and Full Screen recordings
- Post-recording delivery: recordings save straight to the output folder (Finder is the library — no library window); a floating thumbnail appears briefly and expands into a preview panel (play/scrub + Edit/Delete/Done) when clicked — Edit opens the trim editor; M4A audio extraction via the trim editor's export options
- First-run experience: output folder selection and guided permission flows (screen & system audio recording, microphone)
- App preferences: settings window reachable only from the menu bar icon menu (⌘,) — theme, launch at login, floating-thumbnail toggle, reset all settings; native glass materials on the recording HUD, transient preview surfaces, and trim editor, with standard system surfaces for Settings and onboarding
- Localization: English (base), Korean, Japanese, Simplified Chinese — 100% string coverage enforced in CI; accessibility: VoiceOver, keyboard-only operation, Reduce Transparency/Motion honored

Out of scope for this change (planned as follow-ups): webcam/camera recording of any kind (standalone or PIP overlay), real-time drawing/annotation, AI transcription/subtitles, sharing integrations (AirDrop/cloud links), scheduled recording, GIF export.

## Capabilities

### New Capabilities

- `recording-modes`: The three capture modes (selected area, full screen, window), their selection UI, target pickers, and per-mode behavior
- `recording-controls`: Recording lifecycle (start/stop), countdown, the global toolbar shortcut, menu bar status item controls, and recording state feedback. Pause/resume remains an internal encoder capability and is not a user-facing control.
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
- **Entitlements/Info.plist**: microphone usage description, security-scoped bookmarks for the user-chosen output folder, `LSUIElement`; launch at login uses `SMAppService.mainApp`
- **Minimum OS**: macOS 13.3 (Ventura) — required for driver-free system audio capture via ScreenCaptureKit
- **No network dependencies**: all recording, encoding, and editing is fully local
