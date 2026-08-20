# Design: add-core-screen-recording

## Context

Native macOS menu bar app with an existing SwiftUI app target and a local Swift package. The product has three capture modes, driver-free system audio, mouse effects, trim editing, and output controls. Processing stays on-device and requires no account.

Normative specs define the target contract. `tasks.md` records implementation status. Sections below label incomplete work as **Planned** instead of describing it as existing behavior.

Constraints:

- macOS 15+ (Sequoia). This floor provides ScreenCaptureKit's native mouse-click indicator alongside driver-free system audio capture and SwiftUI `MenuBarExtra`.
- App Sandbox enabled from day one (future Mac App Store distribution must not require a re-architecture).
- MIT license: dependencies must be permissively licensed; prefer zero third-party dependencies in the capture/encode path.

## Goals / Non-Goals

**Goals:**

- Rock-solid capture pipeline: no dropped-frame cascades, no A/V desync, safe recovery from device disconnects and permission revocation mid-recording
- All capabilities in the proposal implemented with explicit error states, accessibility behavior, and localized user-facing strings
- Testable core: capture/encode/trim logic isolated from UI in a local Swift package

**Non-Goals:**

- Webcam/camera recording of any kind (standalone or PIP overlay), drawing tools, transcription, sharing, scheduled recording, GIF export (follow-up changes)
- Windows/Linux ports, CLI interface
- Plugin/extension system

## Decisions

### D1. Capture engine: ScreenCaptureKit (SCStream)

Use `SCStream` + `SCContentFilter` for all screen-based modes.

- **Why**: Apple's current capture API. Provides per-window isolated capture (`desktopIndependentWindow`), display capture, `sourceRect` cropping for area mode, driver-free system audio (`capturesAudio`, macOS 13.0+, reliable from 13.3), self-audio exclusion (`excludeCurrentProcessAudio`), and content filters that natively support window exclusion (used by `capture-exclusion`).
- **Alternatives**: `CGDisplayStream`/`AVCaptureScreenInput` — deprecated paths, no window isolation, no system audio; virtual audio driver (BlackHole-style) — requires install step and violates the "no driver" product promise.

### D2. Encoding: AVAssetWriter with hardware VideoToolbox codecs

Real-time writing uses `AVAssetWriter` with `AVVideoCodecType.h264` / `.hevc` and AAC audio through `AVAssetWriterInput`. The current defaults are HEVC and MOV.

- **Existing**: quality 0–100 maps continuously to a resolution/FPS-aware target bitrate curve and a VideoToolbox quality target. H.264 stays on High 4:2:0 and HEVC stays on Main 4:2:0 across the full range. Native odd pixel dimensions remain unchanged through ScreenCaptureKit and use an even coded frame with a clean aperture, so the pipeline neither drops an edge pixel nor fractionally rescales the source; only genuinely oversized sources are downscaled.
- **Existing**: frame rate can be fixed at 30/60 FPS or matched to the capture display. Display matching remains unresolved in Settings and snapshots the target display's current refresh rate when recording starts; windows use the display containing their largest area, and unavailable rates fall back to 60 FPS.
- **Existing**: variable frame rate is the default. Constant frame rate retains the latest complete ScreenCaptureKit sample and retimes it on a fixed writer-queue cadence when static content stops producing complete samples.
- **Measured limit**: the `4k-cfr-h264` stress scenario reaches about 56 FPS with 6.7% writer backpressure on this M1 Pro. Time Profiler attributes the leaf cost to `AVAssetWriter`/VideoToolbox and `pwritev`; pending-sample scheduling, real-time encoder flags, a pixel-buffer adaptor, NV12 conversion, frame reordering, and `MaximumRealTimeFrameRate` did not improve the five-run median without a regression. Default 4K60 HEVC VFR meets the capture budget; H.264 CFR remains a known unsupported 4K60 limit rather than a passing result.
- **Existing**: the color pipeline is sRGB end to end. SCStream would otherwise deliver buffers in the display's ICC color space, which no standard video tag can describe, so the stream requests `colorSpaceName = sRGB` (ScreenCaptureKit color-matches at the source and tags buffers BT.709 primaries / sRGB transfer / BT.709 matrix) and the writer records the identical `AVVideoColorPropertiesKey` triple. Tags therefore describe the real pixel values without a second color conversion, and color-managed players reproduce the on-screen colors on any monitor profile. The cursor compositor propagates the buffer color attachments onto composited frames.
- **Planned**: expose VBR and capped-VBR choices in Settings. True CBR is not exposed by the hardware encoders.
- **Existing, core only**: the splice clock can remove pause gaps by shifting audio and video PTS by the same accumulated duration. Pause/resume has no app UI or global shortcut.
- **Planned**: require hardware encoding explicitly and report when the hardware encoder cannot be created.
- **Alternatives**: FFmpeg — LGPL/GPL friction for MIT distribution, huge binary, unnecessary since VideoToolbox covers H.264/HEVC.

### D3. Audio: mix system audio + microphone into a single AAC track

System audio arrives as `CMSampleBuffer`s from `SCStream` and is written to the AAC track. `AudioMixer` and `MicrophoneCapture` exist, but microphone samples are not yet connected to the recording session.

- **Planned**: connect `MicrophoneCapture`, add input-device selection and disconnect fallback, and expose a live level meter.

- **Why single track**: multi-track MP4 audio has inconsistent player behavior (VLC plays one track, web players ignore extras). One mixed track plays everywhere.
- **Trade-off**: sources can't be separated post-hoc. Acceptable for v1; a "separate tracks (MOV)" advanced option can ship later without spec changes to defaults.

### D4. Mouse effects: manual cursor composition (not overlay windows)

Use single-owner cursor rendering for the whole recording: ScreenCaptureKit owns the system pointer from the first frame to the last, while EffectsKit owns the custom dot pointer. EffectsKit composites highlight and click effects into recorded frames with Core Image over Metal-backed `CVPixelBuffer`s. The sampler updates custom cursor state at the configured capture rate; each frame's ScreenCaptureKit metadata supplies the live window position and its exact placement inside the output surface. Clicks are observed with a global `NSEvent` monitor. The full-resolution frame remains on the GPU; only small effect tiles are rasterized on the CPU.

- **Why**: overlay windows are invisible in window-isolated capture and would need per-mode exclusion gymnastics; composition works identically across all modes and keeps effects out of live screen (only in the recording), which is the required behavior.
- **Existing**: effects degrade from full rendering to no click animation, no highlight, and cursor-only rendering when the frame budget is exceeded. Cursor ownership never changes during this degradation, so no cursorless transition frame is possible.
- **Planned**: add configurable highlight color/size/opacity and independent left/right click effects, measure actual-capture performance, and reduce capture FPS after effect fallback is exhausted.

### D5. Trim: AVAssetExportSession passthrough with keyframe snapping

`AVAssetExportPresetPassthrough` + `timeRange` provides lossless trim export. The editor also has an explicit Frame-exact option that re-encodes with progress reporting.

- **Existing**: the UI snaps near a keyframe when the handle is within the visual snap threshold.
- **Planned**: snap to the nearest preceding sync frame, validate external MP4/MOV inputs, accept drag-and-drop and Open With, add exact timecode entry, and automatically fall back to frame-exact export when passthrough is unavailable.

- **Alternative**: smart-render (re-encode only the head GOP) — best of both, but significant complexity; deferred.
- **Timeline interaction**: the filmstrip lives in an `NSScrollView` (native momentum/rubber-band for free); pinch is handled via `magnify` events zooming around the pointer anchor, ⌘+scroll maps to the same zoom path, plain scroll pans. Zoom level = seconds-per-point scale; thumbnail strip re-tiles lazily per zoom band so frame-level zoom never generates thumbnails for the whole clip. Trackpad and mouse are strict input peers — every gesture has a slider/shortcut equivalent (⌘+/⌘−/⌘0 fit). Horizontal `scrollWheel` deltas over the video surface (preview panel and editor preview) drive playhead scrubbing QuickTime-style — phase-aware (`NSEvent.phase`/momentum), seek-throttled to display refresh via `AVPlayer.seek(toleranceBefore:after:)` on a coalescing queue.

### D6. App architecture: SwiftUI app + local SPM core package

```
Rokuga.xcodeproj
├── Rokuga (app target: SwiftUI HUD toolbar/panels, menu bar, onboarding)
└── RokugaCore (local Swift package, no AppKit-UI deps)
    ├── CaptureKit      — SCStream/AVCaptureSession wrappers, content filters
    ├── EncoderKit      — AVAssetWriter pipeline, pause/resume clock, audio mixer
    ├── EffectsKit      — cursor compositor (Core Image/Metal)
    ├── TrimKit         — keyframe scan, passthrough/re-encode export
    └── SettingsKit     — typed settings store, bookmark management
```

State machine at the center: `idle → preparing → countdown → recording → finishing → idle`, owned by a `RecordingCoordinator` actor. The core retains `paused` transitions for splice-clock tests, but the app UI does not expose them. All entry points observe the coordinator state.

### D7. Global lifecycle shortcuts: KeyboardShortcuts (MIT, sindresorhus)

Use the existing Carbon `RegisterEventHotKey` wrapper for the configurable toolbar shortcut and fixed lifecycle shortcuts. ⇧⌘6 summons the toolbar. Esc is registered only while capture is preparing or counting down, and ⌃⌘Esc is registered only while recording or internally paused. Idle and finishing states disable both lifecycle shortcuts. This keeps cancellation and stop independent of app focus without reserving Esc outside the pending-capture state. The library is sandbox-safe, MIT-licensed, and remains the only third-party dependency.

### D8. Capture exclusion mechanics

- **Own windows**: `SCContentFilter(display:excludingWindows:)` always excludes windows owned by our PID. This is an invariant, not a user setting.
- **Desktop icons**: exclude Finder-owned windows at `kCGDesktopIconWindowLevel`; wallpaper (WindowServer backdrop) remains visible — matches user expectation of "clean desktop".
- Window mode ignores the desktop-icons setting because isolated capture never includes the desktop.

### D9. Storage & persistence

- Settings: `UserDefaults` behind a typed `SettingsKit` facade (test-injectable).
- Output folder: security-scoped bookmark (sandbox); default `~/Movies/Rokuga` created on first run via user-confirmed save panel.
- No recording library window and no database — the output folder **is** the library. "Open output folder" in the menu bar reveals it in Finder; file management (rename/delete/move) is Finder's job. The app only tracks the "last recording" URL for the floating thumbnail and the menu bar shortcut.

### D10. System integration choices

- Menu bar: `MenuBarExtra` provides the idle menu (open toolbar, last recording, output folder, settings, quit). During recording, a separate status item shows `M:SS` and a one-click stop control. Pause is not exposed.
- Countdown: borderless non-activating overlay window, excluded from capture (D8), with off/3/5/10-second choices. A state-scoped global Esc cancels preparation or countdown even when another app has focus.
- Launch at login: `SMAppService.mainApp`.
- Appearance: application-wide Dark Aqua fixed before app-owned surfaces are created; no user-selectable theme.
- Permissions: `SCShareableContent` probe for screen recording, `AVCaptureDevice.requestAccess` for the microphone; each denied state gets a guided panel with a deep link to the exact System Settings pane.

### D11. UI shell: windowless ⇧⌘5-style HUD + Liquid Glass

- **App form**: menu bar agent (`LSUIElement`) — no main window and no Dock icon. Idle recording UI is a floating toolbar with three mode buttons, an options popover, and a record button.
- **Toolbar hosting**: non-activating borderless `NSPanel` at `.screenSaver + 1`, excluded from capture per D8. **Existing**: the toolbar becomes key without activating Rokuga so its local Esc/Return handling and popover chrome work; selection interaction panels do not take key status. Recording lifecycle shortcuts do not depend on panel focus. **Planned (task 4.10)**: verify that toolbar and preview key handling does not take keyboard focus from the frontmost app, and revise the event route if it does.
- **Summoning**: menu bar menu or global hotkey (default ⇧⌘6, configurable in Settings › Shortcuts). App launch does not open the toolbar. Esc or starting a recording dismisses it.
- **Toolbar controls and tooltips**: a leading close button dismisses the capture UI. Mode and options controls are icon-only; their labels appear with no hover delay in a rounded tooltip anchored directly above the toolbar. Tooltips use a capture-excluded, non-interactive `CapturePanel` and disappear on pointer exit or before any toolbar action. The record action keeps its text label.
- **Options popover**: segmented controls and toggles for output location, countdown, FPS, audio, mouse effects, and thumbnail behavior. Advanced encoding lives in Settings.
- **Windows and panels**: onboarding, Settings, and the trim editor are regular windows. The recording toolbar, selection layers, floating thumbnail, and preview are transient panels.
- **Material and appearance**: app-owned chrome inherits an application-wide Dark Aqua appearance. `captureWindowChrome` is the shared visual contract for the toolbar, tooltip, preview, and trim editor. It places untinted native material below an identically clipped `#1e1e23` scrim at 0.70 opacity. Each owning window clips to the same corner radius and disables the rectangular window shadow; tooltip chrome uses its smaller shared radius. Active chrome uses full-strength semantic Dark foregrounds and system selection/control surfaces. Increase Contrast strengthens the scrim and border; Reduce Transparency replaces both layers with the opaque Dark palette. Capture overlays and controls drawn over video keep fixed-contrast colors. Menu bar items, menus, dialogs, and system recording indicators remain system-rendered under Dark Aqua.
- **Chrome buttons**: icon actions in panel/toolbar chrome are borderless (`.buttonStyle(.borderless)`) — icon-only, neutral monochrome (no red tint on destructive icons; danger is communicated by the confirmation dialog), shape revealed on hover only, hit target kept ≥ 28pt regardless of visual size.
- **Iconography**: in-app icons are real SF Symbols via `Image(systemName:)` (`pencil`, `trash`, etc.) — legal on Apple platforms; SF Symbols assets MUST NOT be committed to the MIT repo. AppKit renders the bundled 32×32 `screenshotwindow.svg` and `resize*.svg` assets as custom capture and resize cursors. Other repo-shipped artwork (mockups, web, README) uses Lucide (ISC) equivalents tuned to SF stroke weight (~1.8/24).
- **Visual language**: native Liquid Glass — untinted `.glassEffect`/glass background APIs where available (macOS 26+), graceful fallback to `NSVisualEffectView`/`.ultraThinMaterial` on macOS 15–25. The fixed Dark contrast scrim is separate from, and does not replace, those system materials. Reduce Transparency replaces the layered background with the opaque Dark palette.
- **Cursor tracking**: non-key capture panels use one `ActiveCursorView` path backed by `NSTrackingArea` mouse enter/move events with `.activeAlways`. The same path owns drag-handle, area-resize, click-to-record, and trim-handle cursor updates. It trusts AppKit's delivered event window and visible view bounds as cursor ownership; it does not re-check WindowServer stacking or write an arrow on exit, so transparent overlays and delayed exit events cannot suppress or overwrite the destination cursor.
- **Why**: zero learning curve (users already know ⇧⌘5), no focus-stealing during capture workflows, and the smallest possible UI surface for a recorder — the screen itself is the canvas.

### D12. Performance budget and frame transport

- **Existing pipeline**: SCK IOSurface frames → optional Core Image/Metal cursor composition → incremental `AVAssetWriter` writes. There is no full-frame CPU readback; the compositor rasterizes only its small overlay tile on the CPU.
- **Isolated harness**: `./scripts/perf.sh` builds `io.rokuga.Rokuga.Perf` with the stable `Rokuga Dev` designated requirement in `artifacts/perf/DerivedData`. The production app, DerivedData, container, and settings are not used. A separate Retina workload window supplies deterministic 3840×2160 content while the harness runs the production coordinator, capture, compositor, and writer path. Rebuilds preserve the Screen Recording grant.
- **Accepted compositor optimization**: the Core Image context disables automatic working-space conversion because the capture surface, overlay pixels, and output surface already share the sRGB contract. In untraced warm-up + five-run `4k-effects` measurements (`20260819T151119Z-4k-effects` → `20260819T151404Z-4k-effects`), median compositor time fell 23.04% and app CPU fell 3.14%, with zero writer drops and no regression in output integrity, latency, steady memory, or memory-growth slope. The follow-up Metal trace changed the kernel from per-frame linear/sRGB conversion to direct source-over composition, reduced median command-buffer duration from 714.7 to 609.3 µs, and preserved the same transient-resource counts and five reused 4K IOSurfaces.
- **Accepted startup optimization**: capture/filter preparation now overlaps encoder setup. Five-run `4k-audio` measurements (`20260819T162919Z-4k-audio` → `20260819T162652Z-4k-audio`) reduced median record-to-first-frame latency from 450.49 ms to 344.58 ms (23.51%). CPU changed by 0.35%, steady memory by 0.26%, writer drops stayed at zero, and output integrity did not regress.
- **Sustained result**: `20260819T160825Z-4k-audio` records 4K60 HEVC with system audio for 10 minutes. Writer drop rate is 0%, output integrity loss is 0.02597%, CPU is 16.67% of one core, steady memory is 47.78 MB, memory slope is 0.00133 MB/s, and measured A/V drift is 11.42 ms/h. Every applicable gate passes.
- **Eight-hour soak**: `20260819T165219Z-4k-audio` finalized 28,800.09 seconds of 4K60 HEVC with system audio into a 47 GiB file. Writer drop rate is 0%, output integrity loss is 0.011789%, CPU is 16.85% of one core, steady/peak memory is 68.23/108.09 MB, memory slope is 0.000986 MB/s, and measured A/V drift is 0.2212 ms/h; the separate endpoint skew is 52.58 ms. Record-to-first-frame is 341.97 ms, finalization is 115.47 ms, and thermal state stayed nominal. Every gate passes.
- **Final representative regression**: warm-up plus five untraced 30-second runs of motion (`20260820T005937Z-4k-motion`), system audio (`20260820T010236Z-4k-audio`), and effects (`20260820T010616Z-4k-effects`) have zero writer drops and pass every gate. Median CPU is 12.72%, 17.33%, and 34.40% of one core respectively; median steady memory is 42.80 MB, 47.72 MB, and 46.11 MB.
- **Latency result**: the production toolbar artifact `20260819T163850Z-toolbar-latency` records 93.00 ms cold and 14.64 ms warm median summon latency. The five-run `20260819T163211Z-latency` artifact records 24.91 ms median passthrough trim and 116 ms median stop-to-playable latency. Five-run actual 4K audio capture starts in 344.58 ms median and finalizes in 53.21 ms median.
- **Profiler disposition**: current Time Profiler artifacts are `20260819T164017Z-4k-effects-time`, `20260819T164702Z-4k-audio-time`, and `20260819T164804Z-4k-cfr-h264-time`; the final Metal and Allocations artifacts are `20260819T151852Z-4k-effects-metal` and `20260820T011153Z-4k-motion-allocations`. Effects spend 30.64% inclusive below `SCCaptureSession.stream` and 21.62% below `CursorCompositor.composite`, but app-owned self time is at most 0.03%; the leaf cost is in IOKit, Core Image/Metal, and kernel writes. Audio and CFR app-owned self time is at most 0.05%, with AAC, `AVAssetWriter`, and `pwritev` as leaves. Replacing the sample-attachment Swift bridge improved CPU by only 0.94%, worsened median compositor time by 0.16%, and regressed first-frame latency by 11.36% (`20260819T164156Z-4k-effects` → `20260819T164405Z-4k-effects`), so it was rejected. No remaining app-owned symbol has 1% self time.
- **File I/O profiling**: Instruments 26.0 (17C52) cannot finalize File Activity or Filesystem Activity even for `/usr/bin/true`. The version-bound `profile file` fallback uses native System Trace without root and exports its syscall table. `20260819T165036Z-4k-audio-file` finalized a 10-second recording, passed all capture gates, and recorded 584 `pwritev`, 1,059 `write`, and 8 `fsync` calls.
- **Optimization acceptance**: zero-copy is the default transport, not an independent success metric. A candidate that adds a buffer copy or CPU readback may replace it only when the same recording output contract is preserved and warm-up plus five untraced runs show at least 3% median improvement in CPU or memory without regressing drop rate, A/V drift, latency, memory growth, or the other resource. The artifact comparison records the exception. Software video encoding remains prohibited.
- **Existing degradation**: effect quality falls back stepwise to cursor-only rendering without changing cursor ownership. The capture delivery path does not yet lower runtime FPS.
- **Planned**: require a hardware encoder, add runtime FPS degradation, and report applied degradation after recording.
- **Budgets** (baseline M1, 8 GB): ≤ 0.1% dropped frames over 10 min at up to 4K60; < 40 ms A/V drift per hour; app CPU ≤ 20% of one core at 1080p60 (≤ 35% at 4K60); steady-state memory ≤ 400 MB regardless of duration; toolbar summon ≤ 150 ms; record→first frame ≤ 500 ms; stop→playable ≤ 2 s; passthrough trim ≤ 3 s.
- **Current enforcement**: local capture, effects, audio, codec, toolbar, trace, compare, and budget commands produce timestamped artifacts. The audio workload emits host-clock-synchronized visual/audio markers; output A/V drift is the change in marker offset, while track endpoint skew is reported separately. CI still runs only the encoder microbenchmark. Actual capture CI integration remains pending in task 10.4 and was not changed by this work.

### D13. Localization: String Catalogs, en base + ko/ja/zh-Hans

- **Mechanism**: Xcode String Catalogs (`.xcstrings`), development language English. SwiftUI string literals auto-extract; a CI lint fails on user-facing literals outside the catalog and on < 100% translation completeness per shipping language.
- **Languages**: en (base), ko, ja, zh-Hans. Traditional Chinese (zh-Hant) deferred to a follow-up.
- **Resolution**: system language list + per-app override in System Settings — no in-app picker (native behavior, zero code).
- **Planned formatting completion**: use `Date.FormatStyle`, `ByteCountFormatStyle`, and other locale-aware formatters for displayed values; keep generated file names locale-neutral for stable sorting.
- **QA**: String Catalog completeness is automated. CJK truncation and overlap review remains a manual release task until screenshot comparison or accessibility-frame assertions are added.

## Risks / Trade-offs

- [SCK behavior drifts across supported macOS versions] → CI build coverage and manual release QA on supported hardware
- [Cursor compositor can't hold 5K@60 on low-end hardware] → GPU-only path, per-frame budget monitor with automatic effect degradation (D4), FPS/resolution suggestions in UI when sustained drops are detected
- [Capped-VBR "CBR" isn't broadcast-true CBR] → label honestly in UI help; acceptable for the target use cases (uploads, tutorials)
- [Passthrough trim start snaps to keyframes — up to one GOP (~2 s) coarser than frame-exact] → visible snap in the UI (no silent surprise) + re-encode fallback offered as "frame-exact trim" option
- [Single mixed audio track prevents post-hoc mic/system separation] → documented; separate-track MOV option is a compatible future addition
- [Device disconnect mid-recording (mic unplugged, display removed)] → coordinator finalizes the file safely (never lose captured footage), surfaces a non-blocking toast, recording continues without the lost source when possible
- [Disk-full during long recordings] → free-space preflight (estimate from bitrate), background watermark check every 30 s, auto-stop with safe finalize at < 500 MB free

## Migration Plan

Greenfield — no migration. Ships as v0.1.0 behind no flags. Rollback = previous build (files produced are standard MP4/MOV, forward/backward compatible).

## Resolved defaults

- Default container and codec: MOV and HEVC.
- Selected Area persists one region per display.
