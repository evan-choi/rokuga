# Tasks: add-core-screen-recording

## 1. Project scaffolding

- [ ] 1.1 Create Xcode project: `Rokuga` app target (SwiftUI, macOS 13.3+, sandboxed, `LSUIElement` agent) + local SPM package `RokugaCore` (CaptureKit, EncoderKit, EffectsKit, TrimKit, SettingsKit)
- [ ] 1.2 Entitlements & Info.plist: screen capture, microphone usage description, security-scoped bookmarks, login item helper; no Dock icon
- [ ] 1.3 Add `KeyboardShortcuts` (MIT) as the sole third-party dependency
- [ ] 1.4 CI pipeline: build + unit tests on macOS 13/14/15 runners, SwiftLint/SwiftFormat, benchmark job scaffold (perf gates wired in 13.4)

## 2. Capture core (CaptureKit)

- [ ] 2.1 `RecordingCoordinator` actor with the state machine (idle → preparing → countdown → recording ⇄ paused → finishing → idle) and single-flight guarantees
- [ ] 2.2 SCStream display capture with `sourceRect` cropping (Selected Area) and per-display selection (Full Screen)
- [ ] 2.3 `desktopIndependentWindow` capture (Window mode) incl. target picker metadata (app icon, window title, live preview)
- [ ] 2.4 Content-filter exclusion: own-PID windows toggle, desktop-icon exclusion at `kCGDesktopIconWindowLevel`; countdown/selection overlays always excluded
- [ ] 2.5 Display/window disconnect handling → safe finalize + non-blocking toast

## 3. Encoding & audio (EncoderKit)

- [ ] 3.1 AVAssetWriter pipeline: VideoToolbox H.264/HEVC, MP4/MOV, incremental writes, zero-copy IOSurface path
- [ ] 3.2 Pause/resume splice clock (gapless PTS rewrite, A/V sync across splices)
- [ ] 3.3 System audio via SCStream (`capturesAudio`, `excludeCurrentProcessAudio`) + mic via AVCaptureSession → 48 kHz lock-free mixer → single AAC track
- [ ] 3.4 Rate control: VBR quality 0–100 mapping + capped-VBR "CBR" (`AVVideoDataRateLimitsKey` 1.1×/1 s); AAC 128–320 kbps
- [ ] 3.5 Resolution cap (≤ 5K) & FPS cap (≤ 60) with automatic downscale of oversized sources
- [ ] 3.6 Failure-safe finalization: crash/power-loss recovery of playable partials, disk-full preflight + 30 s watermark + auto-stop < 500 MB free

## 4. UI shell (windowless, Liquid Glass)

- [ ] 4.1 Menu bar `MenuBarExtra`: idle menu (toolbar, last recording, output folder, settings, quit) ↔ recording state with native red-dot + elapsed time + pause/stop
- [ ] 4.2 Recording toolbar: non-activating `NSPanel` HUD at bottom-center of the mouse-pointer display; summon via menu bar / ⇧⌘6 / launch; Esc & record dismiss
- [ ] 4.3 Mode buttons ×3 (area/full screen/window) + options popover (⇧⌘5-style: save location, countdown, audio, mouse, thumbnail toggles) + 녹화 button
- [ ] 4.4 Liquid Glass materials with `NSVisualEffectView`/`.ultraThinMaterial` fallback (13.3–15) + reduce-transparency accessibility path
- [ ] 4.5 Region selection overlay: drag-select, resizable edges/corners, magnifier with window snapping, per-display persistence
- [ ] 4.6 Countdown overlay (1–10 s, Esc cancels, always capture-excluded)

## 5. Recording controls & hotkeys

- [ ] 5.1 Global shortcuts via KeyboardShortcuts: toolbar ⇧⌘6, start/stop ⇧⌘2, pause/resume ⇧⌘4 — reconfigurable, disableable, conflict-detected
- [ ] 5.2 Wire all entry points (toolbar, menu bar, hotkeys) to the coordinator; concurrent-start prevention; quit-while-recording confirm + safe finalize

## 6. Mouse effects (EffectsKit)

- [ ] 6.1 Metal cursor compositor: cursor show/hide, system/dot pointer styles, highlight halo, click animations — recorded-only, invisible live
- [ ] 6.2 Per-frame GPU budget monitor with automatic effect degradation ladder

## 7. Post-recording delivery

- [ ] 7.1 Timestamped save-to-folder with collision suffixes; "last recording" tracking; security-scoped default `~/Movies/Rokuga`
- [ ] 7.2 Floating thumbnail panel (bottom-right, click → preview panel, timeout/swipe dismiss, capture-excluded, settings toggle) + notification fallback
- [ ] 7.3 Preview panel: in-place expand from thumbnail, AVPlayer + scrub bar, QuickTime-style two-finger horizontal scrub, 편집(→trim editor)/삭제(→Trash w/ confirm)/완료(close) actions, non-activating, Esc = Done
- [ ] 7.4 Menu bar "Open Last Recording"(→preview) / "Open Output Folder" incl. deleted-file recovery path

## 8. Trim editor (TrimKit)

- [ ] 8.1 Editor window: AVPlayer preview, thumbnail-strip timeline, draggable keep-range handles with keyframe snap display
- [ ] 8.2 Passthrough export (`AVAssetExportPresetPassthrough` + `timeRange`) with re-encode fallback ("frame-exact") + progress UI
- [ ] 8.3 Non-destructive save-as with name/destination; unsaved-changes guard; in-progress files excluded
- [ ] 8.4 Export Audio Only → M4A (AAC) of selected range, disabled when no audio track
- [ ] 8.5 Timeline zoom & gestures: pinch/⌘-scroll anchored zoom, NSScrollView horizontal pan with momentum, zoom slider + ⌘+/⌘−/⌘0, lazy thumbnail re-tiling per zoom band, frame-level handle placement, QuickTime-style horizontal-scroll scrub over the preview area (phase-aware, coalesced seeks)

## 9. Onboarding & preferences

- [ ] 9.1 First-run flow: output folder save panel → screen-recording permission probe (`SCShareableContent`) → guided denial-recovery panels with System Settings deep links
- [ ] 9.2 Just-in-time mic permission; per-permission re-check on every record attempt
- [ ] 9.3 Settings window (menu bar only, ⌘,): General/Recording/Audio/Mouse/Shortcuts/Output panes, immediate apply, recording-time lock
- [ ] 9.4 Theme (auto/light/dark), launch at login (`SMAppService`), thumbnail toggle, Reset All Settings (confirm, no recordings touched)
- [ ] 9.5 Accessibility: VoiceOver labels on every control, full keyboard operation (incl. frame-nudge arrows in trim editor), Reduce Transparency solid fallback, Reduce Motion paths

## 9a. Localization

- [ ] 9a.1 String Catalog (`.xcstrings`) setup, English as development language; CI lint: no user-facing literals outside the catalog
- [ ] 9a.2 ko/ja/zh-Hans translations at 100% coverage + CI completeness gate
- [ ] 9a.3 Locale-aware formatters for all UI dates/times/sizes; locale-neutral file naming verified
- [ ] 9a.4 CJK layout QA: localized-screenshot pass (toolbar/popover/settings/editor ×4 languages), no truncation/overlap

## 10. Performance & release gates

- [ ] 10.1 Zero-copy audit: instruments trace proving no CPU pixel readback in the record path
- [ ] 10.2 Benchmarks: 4K60 10-min drop-rate < 0.1%, A/V drift < 40 ms/h, CPU ≤ 20%@1080p60 / ≤ 35%@4K60, memory ≤ 400 MB steady, 8 h soak
- [ ] 10.3 Latency tests: summon ≤ 150 ms, record→first frame ≤ 500 ms, stop→playable ≤ 2 s, passthrough trim ≤ 3 s
- [ ] 10.4 Wire benchmarks into CI as regression gates (> 10% fail)
- [ ] 10.5 QA matrix: macOS 13.3/14/15 × Intel/Apple Silicon × 1–3 displays incl. mixed scale factors; accessibility (VoiceOver labels, reduce transparency)
