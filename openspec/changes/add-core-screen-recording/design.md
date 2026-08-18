# Design: add-core-screen-recording

## Context

Native macOS menu bar app with an existing SwiftUI app target and a local Swift package. The product has three capture modes, driver-free system audio, mouse effects, trim editing, and output controls. Processing stays on-device and requires no account.

Normative specs define the target contract. `tasks.md` records implementation status. Sections below label incomplete work as **Planned** instead of describing it as existing behavior.

Constraints:

- macOS 13.3+ (Ventura). This floor gives us stable ScreenCaptureKit system-audio capture without a kernel/virtual-audio driver, and SwiftUI `MenuBarExtra`.
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

- **Existing**: quality 0–100 maps to a resolution/FPS-aware target bitrate curve. The writer applies `AVVideoDataRateLimitsKey` to bound the rate.
- **Planned**: expose VBR and capped-VBR choices in Settings with an MB/min estimate. True CBR is not exposed by the hardware encoders.
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

### D7. Global toolbar shortcut: KeyboardShortcuts (MIT, sindresorhus)

Battle-tested Carbon `RegisterEventHotKey` wrapper with a recorder UI component, sandbox-safe, MIT-licensed. Writing our own Carbon wrapper is avoidable risk. This is the only third-party dependency.

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
- Countdown: borderless non-activating overlay window, excluded from capture (D8), with off/3/5/10-second choices. Esc cancels.
- Launch at login: `SMAppService.mainApp`.
- Theme: `preferredColorScheme` override (auto/light/dark).
- Permissions: `SCShareableContent` probe for screen recording, `AVCaptureDevice.requestAccess` for the microphone; each denied state gets a guided panel with a deep link to the exact System Settings pane.

### D11. UI shell: windowless ⇧⌘5-style HUD + Liquid Glass

- **App form**: menu bar agent (`LSUIElement`) — no main window and no Dock icon. Idle recording UI is a floating toolbar with three mode buttons, an options popover, and a record button.
- **Toolbar hosting**: non-activating borderless `NSPanel` at `.screenSaver + 1`, excluded from capture per D8. **OPEN**: verify focus retention because the panel becomes key for Esc handling.
- **Summoning**: menu bar menu or global hotkey (default ⇧⌘6, configurable in Settings › Shortcuts). App launch does not open the toolbar. Esc or starting a recording dismisses it.
- **Options popover**: segmented controls and toggles for output location, countdown, FPS, audio, mouse effects, and thumbnail behavior. Advanced encoding lives in Settings.
- **Windows and panels**: onboarding, Settings, and the trim editor are regular windows. The recording toolbar, selection layers, floating thumbnail, and preview are transient panels.
- **Material and appearance**: app-owned chrome inherits the Auto, Light, or Dark application appearance. Glass surfaces keep untinted native material as the lower layer and place an identically clipped, alpha-composited contrast scrim above it: Dark uses `#1e1e23` with 0.70 opacity and Light uses `#e8e8ec` with 0.56 opacity. Active chrome uses full-strength semantic foregrounds and system selection/control surfaces so the normal scrim preserves backdrop variation while meeting the contrast floor. Increase Contrast strengthens the scrim and border; Reduce Transparency replaces both background layers with an opaque palette equivalent. The adaptive palette applies to the toolbar, options popover, preview panel, and trim editor chrome. Capture overlays and controls drawn over video keep fixed-contrast colors. Menu bar items, menus, dialogs, and system recording indicators remain system-rendered.
- **Chrome buttons**: icon actions in panel/toolbar chrome are borderless (`.buttonStyle(.borderless)`) — icon-only, neutral monochrome (no red tint on destructive icons; danger is communicated by the confirmation dialog), shape revealed on hover only, hit target kept ≥ 28pt regardless of visual size.
- **Iconography**: in-app icons are real SF Symbols via `Image(systemName:)` (`pencil`, `trash`, etc.) — legal on Apple platforms; SF Symbols assets MUST NOT be committed to the MIT repo. AppKit renders the bundled 32×32 `screenshotwindow.svg` and `resize*.svg` assets as custom capture and resize cursors. Other repo-shipped artwork (mockups, web, README) uses Lucide (ISC) equivalents tuned to SF stroke weight (~1.8/24).
- **Visual language**: native Liquid Glass — untinted `.glassEffect`/glass background APIs where available (macOS 26+), graceful fallback to `NSVisualEffectView`/`.ultraThinMaterial` on macOS 13.3–15. The explicit contrast scrim is separate from, and does not replace, those system materials. Reduce Transparency replaces the layered background with the opaque palette equivalent.
- **Why**: zero learning curve (users already know ⇧⌘5), no focus-stealing during capture workflows, and the smallest possible UI surface for a recorder — the screen itself is the canvas.

### D12. Performance budget and frame transport

- **Existing pipeline**: SCK IOSurface frames → optional Core Image/Metal cursor composition → incremental `AVAssetWriter` writes. There is no full-frame CPU readback; the compositor rasterizes only its small overlay tile on the CPU.
- **Existing degradation**: effect quality falls back stepwise to cursor-only rendering without changing cursor ownership. The capture delivery path does not yet lower runtime FPS.
- **Planned**: require a hardware encoder, add runtime FPS degradation, and report applied degradation after recording.
- **Budgets** (baseline M1, 8 GB): ≤ 0.1% dropped frames over 10 min at up to 4K60; < 40 ms A/V drift per hour; app CPU ≤ 20% of one core at 1080p60 (≤ 35% at 4K60); steady-state memory ≤ 400 MB regardless of duration; toolbar summon ≤ 150 ms; record→first frame ≤ 500 ms; stop→playable ≤ 2 s; passthrough trim ≤ 3 s.
- **Current enforcement**: CI runs an encoder microbenchmark with synthesized video frames. It does not yet cover ScreenCaptureKit, audio, effects, long-run memory growth, A/V drift, or toolbar latency. The complete gates remain planned in `tasks.md`.

### D13. Localization: String Catalogs, en base + ko/ja/zh-Hans

- **Mechanism**: Xcode String Catalogs (`.xcstrings`), development language English. SwiftUI string literals auto-extract; a CI lint fails on user-facing literals outside the catalog and on < 100% translation completeness per shipping language.
- **Languages**: en (base), ko, ja, zh-Hans. Traditional Chinese (zh-Hant) deferred to a follow-up.
- **Resolution**: system language list + per-app override in System Settings — no in-app picker (native behavior, zero code).
- **Planned formatting completion**: use `Date.FormatStyle`, `ByteCountFormatStyle`, and other locale-aware formatters for displayed values; keep generated file names locale-neutral for stable sorting.
- **QA**: String Catalog completeness is automated. CJK truncation and overlap review remains a manual release task until screenshot comparison or accessibility-frame assertions are added.

## Risks / Trade-offs

- [SCK behavior drifts across macOS versions (13.3 → 15+)] → runtime `#available` gates, CI on available macOS 14/15 hosted runners, and manual macOS 13.3 coverage
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
