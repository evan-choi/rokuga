# Tasks: add-core-screen-recording

## 1. Project scaffolding

- [x] 1.1 Create Xcode project: `Rokuga` app target (SwiftUI, macOS 13.3+, sandboxed, `LSUIElement` agent) + local SPM package `RokugaCore` (CaptureKit, EncoderKit, EffectsKit, TrimKit, SettingsKit)
- [x] 1.2 Entitlements & Info.plist: microphone usage description, security-scoped bookmarks, `LSUIElement`; launch at login via `SMAppService.mainApp`
- [x] 1.3 Add `KeyboardShortcuts` (MIT) as the sole third-party dependency
- [x] 1.4 CI pipeline: build + unit tests on macOS 14/15 hosted runners, localization and zero-copy static audits, benchmark job scaffold; macOS 13.3 remains manual QA

## 2. Capture core (CaptureKit)

- [x] 2.1 `RecordingCoordinator` actor with the state machine (idle → preparing → countdown → recording ⇄ paused → finishing → idle) and single-flight guarantees
- [x] 2.2 SCStream display capture with `sourceRect` cropping (Selected Area) and per-display selection (Full Screen)
- [x] 2.3 `desktopIndependentWindow` capture (Window mode) with live pointer-following target overlay and click-to-record
- [x] 2.4 Content-filter exclusion: own-PID windows always excluded; desktop-icon toggle at `kCGDesktopIconWindowLevel`; countdown/selection overlays always excluded
- [x] 2.5 Display/window disconnect handling with safe-finalize attempt
- [ ] 2.6 Surface the source-disconnect reason in a non-blocking user notification

## 3. Encoding & audio (EncoderKit)

- [x] 3.1 AVAssetWriter pipeline: H.264/HEVC, MP4/MOV, incremental writes, no full-frame CPU readback
- [x] 3.2 Pause/resume splice clock (gapless PTS rewrite, A/V sync across splices)
- [x] 3.3a System audio via SCStream (`capturesAudio`, `excludesCurrentProcessAudio`) → 48 kHz AAC track, covered by an asset-writer integration test
- [ ] 3.3b Connected mic capture via AVCaptureSession → 48 kHz mixer → the same AAC track
- [ ] 3.4 Rate-control UI and encoder mapping: selectable VBR/capped-VBR, quality 0–100, MB/min estimate; AAC 128–320 kbps
- [x] 3.5 Resolution cap (≤ 5K) & FPS cap (≤ 60) with automatic downscale of oversized sources
- [x] 3.6 Disk-full preflight + 30 s watermark + auto-stop below 500 MB free
- [ ] 3.7 Crash/power-loss recovery: MOV and MP4 partial handling plus next-launch recovery scan and user notification
- [ ] 3.8 Require hardware encoding at runtime and report an actionable error when no hardware encoder is available
- [ ] 3.9 Output controls: resolution presets, 15/24 FPS choices, output presets/Custom state, and toolbar display of non-30/60 FPS values

## 4. UI shell (windowless, Liquid Glass)

- [x] 4.1 Menu bar controls: idle `MenuBarExtra` menu (toolbar, last recording, output folder, settings, quit) and recording status item with `M:SS` plus one-click stop
- [x] 4.2 Recording toolbar: non-activating `NSPanel` HUD at bottom-center of the mouse-pointer display, movable only from its divider handle; summon via menu bar or ⇧⌘6; Esc and record dismiss
- [x] 4.3 Mode buttons ×3 (area/full screen/window) + options popover (save location, countdown, FPS, audio, mouse, thumbnail toggles) + record button
- [x] 4.4 Liquid Glass materials on HUD and transient preview panels with `NSVisualEffectView` fallback (13.3–15) + Reduce Transparency path
- [ ] 4.5 Region selection overlay: drag-select, resizable edges/corners, Retina pixel dimensions, pixel-loupe magnifier, per-display persistence
- [x] 4.6 Countdown overlay (off/3/5/10 s, Esc cancels, always capture-excluded)
- [x] 4.7 Full Screen selection overlay: clicking any display starts recording that display immediately
- [x] 4.8 Click-to-record cursor: show the bundled camera cursor over Window and Full Screen selection layers and restore the arrow on close
- [x] 4.9 Area selection resize cursors: use the bundled horizontal, vertical, and two diagonal 32×32 SVGs for all eight handles
- [ ] 4.10 Verify that toolbar and preview panels never take keyboard focus from the frontmost app
- [ ] 4.11 Apply the native glass/blur material contract to the trim editor instead of a solid custom background

## 5. Recording controls & hotkeys

- [x] 5.1 Global shortcut via KeyboardShortcuts: toolbar ⇧⌘6 — reconfigurable and disableable; recording start/stop has no global shortcut
- [x] 5.2 Wire toolbar start and menu bar stop to the coordinator; concurrent-start prevention; quit-while-recording confirm + safe finalize

## 6. Mouse effects (EffectsKit)

- [x] 6.1 Cursor compositor: cursor show/hide, system/dot pointer styles, fixed highlight halo, fixed click animation — recorded-only, invisible live
- [x] 6.2 Per-frame GPU budget monitor with automatic effect degradation ladder
- [ ] 6.3 Mouse-effect customization: highlight color/size/opacity, settings preview, independent left/right click toggles and colors
- [x] 6.4 Sample cursor state at the configured capture rate so 60 FPS recordings meet the one-frame positional-lag contract

## 7. Post-recording delivery

- [x] 7.1 Timestamped save-to-folder with collision suffixes; "last recording" tracking; security-scoped default `~/Movies/Rokuga`
- [x] 7.2 Floating thumbnail panel (bottom-right, click → preview panel, 6 s timeout/swipe dismiss, capture-excluded, settings toggle) + notification fallback
- [x] 7.3 Preview panel: in-place expand from thumbnail, AVPlayer + scrub bar, horizontal scrub over the video surface, Edit/Delete/Done actions, non-activating panel, Esc = Done
- [ ] 7.4 Menu bar "Open Last Recording" → internal preview and deleted-file explanation; "Open Output Folder" → Finder
- [ ] 7.5 Finalization and source-loss feedback: show attempted path and cause, preserve recoverable partials, and explain automatic stops
- [ ] 7.6 Extend horizontal trackpad scrub to the entire preview panel and verify momentum behavior

## 8. Trim editor (TrimKit)

- [x] 8.1 Editor window: AVPlayer preview, thumbnail-strip timeline, draggable keep-range handles with keyframe snap display
- [x] 8.2 Passthrough export plus explicit Frame-exact re-encode option with progress UI
- [ ] 8.3 Automatic passthrough-to-frame-exact fallback with user notice
- [ ] 8.4 Non-destructive save-as defaulting beside the source; Save/Discard/Cancel unsaved-changes guard; in-progress files excluded
- [x] 8.5 Export Audio Only → M4A (AAC) of selected range, disabled when no audio track
- [x] 8.6 Timeline zoom & gestures: pinch/⌘-scroll anchored zoom, NSScrollView horizontal pan with momentum, zoom slider + ⌘+/⌘−/⌘0, lazy thumbnail re-tiling per zoom band, frame-level handle placement, QuickTime-style horizontal-scroll scrub over the preview area
- [ ] 8.7 External-file entry: Finder Open With and drag-and-drop for H.264/HEVC MP4/MOV, with format-specific rejection messages
- [ ] 8.8 Exact start/end timecode entry and nearest-preceding-keyframe snap
- [ ] 8.9 Explain why audio-only export is unavailable when the source has no audio track
- [ ] 8.10 Add working on-screen −/+ zoom buttons and two-finger double-tap to fit the full clip

## 9. Onboarding & preferences

- [x] 9.1 First-run flow: output folder save panel → screen-recording permission probe (`SCShareableContent`) → guided denial-recovery panels with System Settings deep links
- [x] 9.2 Just-in-time mic permission; per-permission re-check on every record attempt
- [x] 9.3 Settings window (menu bar only, ⌘,): General/Recording/Audio/Mouse/Shortcuts/Output panes, immediate apply, recording-time lock
- [x] 9.4 App-owned windows and transient panels use fixed Dark appearance; launch at login (`SMAppService.mainApp`); thumbnail toggle
- [ ] 9.5 Accessibility: finish VoiceOver and keyboard verification; run release QA for implemented Increase Contrast, Reduce Transparency, and Reduce Motion paths
- [ ] 9.6 Reset All Settings: reset user preferences while preserving onboarding completion, output bookmark, and last-recording metadata
- [ ] 9.7 Permission recovery: warning states, one-click relaunch after screen permission grant, previous-mode restoration, and a recording-scoped "without mic" override
- [ ] 9.8 Refresh the launch-at-login toggle from `SMAppService.mainApp.status` after external changes
- [ ] 9.9 Output-folder recovery: detect invalid bookmarks or missing volumes, block recording, and offer recreate/choose/reveal actions
- [ ] 9.10 Lock only recording-unsafe controls while a recording is active; keep unrelated preferences editable
- [ ] 9.11 Disable desktop-icon exclusion in Window mode with an explanatory tooltip

## 9a. Localization

- [x] 9a.1 String Catalog (`.xcstrings`) setup, English as development language; CI lint: no user-facing literals outside the catalog
- [x] 9a.2 ko/ja/zh-Hans translations at 100% coverage + CI completeness gate
- [ ] 9a.3 Locale-aware formatters for all UI dates/times/sizes; locale-neutral file naming verified
- [ ] 9a.4 CJK layout QA: localized-screenshot pass (toolbar/popover/settings/editor ×4 languages), no truncation/overlap

## 10. Performance & release gates

- [x] 10.1 Static zero-copy audit: no full-frame CPU pixel-buffer readback in the recording path
- [ ] 10.2 End-to-end capture benchmarks: 4K60 10-min drop-rate < 0.1%, A/V drift < 40 ms/h, CPU ≤ 20%@1080p60 / ≤ 35%@4K60, memory ≤ 400 MB steady, 8 h soak
- [ ] 10.3 Latency tests: summon ≤ 150 ms, record→first frame ≤ 500 ms, stop→playable ≤ 2 s, passthrough trim ≤ 3 s
- [ ] 10.4 Correct CPU thresholds and wire actual capture/audio/effects benchmarks into CI as >10% regression gates
- [ ] 10.5 QA matrix: macOS 13.3/14/15 × Intel/Apple Silicon × 1–3 displays incl. mixed scale factors; accessibility review
- [ ] 10.6 Runtime degradation after effects fallback: lower capture FPS and report the applied degradation after recording
