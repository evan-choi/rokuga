# Design: add-core-screen-recording

## Context

Greenfield native macOS app. No existing code. The product must deliver a professional, production-quality recording experience — four capture modes, driver-free system audio, mouse effects, lossless trimming, fine-grained output control — entirely on-device, with no accounts or network calls.

Constraints:

- macOS 13.3+ (Ventura). This floor gives us stable ScreenCaptureKit system-audio capture without a kernel/virtual-audio driver, and SwiftUI `MenuBarExtra`.
- App Sandbox enabled from day one (future Mac App Store distribution must not require a re-architecture).
- Apache License 2.0: dependencies must be permissively licensed; prefer zero third-party dependencies in the capture/encode path.

## Goals / Non-Goals

**Goals:**

- Rock-solid capture pipeline: no dropped-frame cascades, no A/V desync, safe recovery from device disconnects and permission revocation mid-recording
- All ten capabilities in the proposal implemented to production quality (error states, edge cases, accessibility, localization-ready strings)
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

Real-time writing via `AVAssetWriter` with `AVVideoCodecType.h264` / `.hevc` (hardware-accelerated through VideoToolbox), AAC audio via `AVAssetWriterInput`.

- Quality 0–100 maps to a resolution/FPS-aware target bitrate curve fed to `AVVideoAverageBitRateKey`.
- **VBR** = average bitrate only; **CBR** = average bitrate + `AVVideoDataRateLimitsKey` clamped to ~1.1× target per 1s window (true CBR is not exposed by hardware encoders; this is the standard capped-VBR approximation and is documented as such in the UI tooltip).
- **Pause/resume**: single continuous `AVAssetWriter` session; on resume, all subsequent sample buffer PTS values are shifted by the accumulated pause duration (no segment stitching, no concat step, A/V stays aligned because both tracks share the same offset).
- **Alternatives**: FFmpeg — LGPL/GPL distribution friction, huge binary, unnecessary since VideoToolbox covers H.264/HEVC.

### D3. Audio: mix system audio + microphone into a single AAC track

System audio arrives as `CMSampleBuffer`s from `SCStream`; microphone via `AVCaptureSession`. Both are converted to a canonical 48 kHz stereo float format and summed in a lock-free mixer before hitting one `AVAssetWriterInput`.

- **Why single track**: multi-track MP4 audio has inconsistent player behavior (VLC plays one track, web players ignore extras). One mixed track plays everywhere.
- **Trade-off**: sources can't be separated post-hoc. Acceptable for v1; a "separate tracks (MOV)" advanced option can ship later without spec changes to defaults.

### D4. Mouse effects: manual cursor composition (not overlay windows)

Set `showsCursor = false` on the stream and composite the cursor, highlight halo, and click ripples onto each frame on the GPU (Core Image over Metal-backed `CVPixelBuffer`s). Cursor position sampled per frame via `CGEvent(source:).location`; clicks observed with a global `NSEvent` monitor.

- **Why**: overlay windows are invisible in window-isolated capture and would need per-mode exclusion gymnastics; composition works identically across all modes and keeps effects out of live screen (only in the recording), which is the required behavior.
- **Perf gate**: the compositor must sustain 5K@60 on Apple Silicon base models; benchmark test enforces < 6 ms per-frame budget. Effects auto-degrade (halo only, no ripple animation) if the frame budget is exceeded for 60 consecutive frames.

### D5. Trim: AVAssetExportSession passthrough with keyframe snapping

`AVAssetExportPresetPassthrough` + `timeRange` for lossless, near-instant trims. The trim start handle snaps to the nearest preceding sync frame (keyframe positions read via `AVSampleCursor`); the UI shows the snapped position so what-you-see-is-what-you-get. If passthrough fails (corrupt index, unsupported source), fall back to an HEVC/H.264 re-encode with a progress bar.

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

State machine at the center: `idle → preparing → countdown → recording ⇄ paused → finishing → idle`, owned by a `RecordingCoordinator` actor. All UI observes this single source of truth; the toolbar HUD, menu bar, and hotkeys are just different frontends to the same coordinator.

### D7. Global hotkeys: KeyboardShortcuts (permissive license, sindresorhus)

Battle-tested Carbon `RegisterEventHotKey` wrapper with a recorder UI component, sandbox-safe, permissively licensed. Writing our own Carbon wrapper is avoidable risk. This is the only third-party dependency.

### D8. Capture exclusion mechanics

- **Own windows**: `SCContentFilter(display:excludingWindows:)` with all windows owned by our PID (and the countdown/region overlays always excluded regardless of the setting).
- **Desktop icons**: exclude Finder-owned windows at `kCGDesktopIconWindowLevel`; wallpaper (WindowServer backdrop) remains visible — matches user expectation of "clean desktop".
- Window mode ignores both toggles (isolated capture never contains them) — UI disables the controls with an explanatory tooltip.

### D9. Storage & persistence

- Settings: `UserDefaults` behind a typed `SettingsKit` facade (test-injectable).
- Output folder: security-scoped bookmark (sandbox); default `~/Movies/Rokuga` created on first run via user-confirmed save panel.
- No recording library window and no database — the output folder **is** the library. "Open output folder" in the menu bar reveals it in Finder; file management (rename/delete/move) is Finder's job. The app only tracks the "last recording" URL for the floating thumbnail and the menu bar shortcut.

### D10. System integration choices

- Menu bar: `MenuBarExtra` with state-driven content. Idle → app icon with menu (open toolbar, last recording, output folder, settings, quit). Recording → system-native indicator presentation: red dot + elapsed time + pause/stop, one click to stop (same grammar as ⇧⌘5).
- Countdown: borderless non-activating overlay window, excluded from capture (D8), 1–10 s configurable, Esc cancels.
- Launch at login: `SMAppService.mainApp`.
- Theme: `preferredColorScheme` override (auto/light/dark).
- Permissions: `SCShareableContent` probe for screen recording, `AVCaptureDevice.requestAccess` for the microphone; each denied state gets a guided panel with a deep link to the exact System Settings pane.

### D11. UI shell: windowless ⇧⌘5-style HUD + Liquid Glass

- **App form**: menu bar agent (`LSUIElement`) — no main window, no Dock icon. The entire idle UI is a floating toolbar: mode icons ×4 · options popover · record button, presented bottom-center on the target display, matching the macOS screenshot toolbar grammar.
- **Toolbar hosting**: non-activating borderless `NSPanel` (`.nonactivatingPanel`, `.statusBar` level) hosting SwiftUI — never steals focus from the app being recorded; excluded from capture per D8.
- **Summoning**: menu bar icon click, global hotkey (default ⇧⌘6, configurable in Settings › Shortcuts), or app launch → toolbar appears at the bottom-center of the display containing the mouse pointer; Esc or starting a recording dismisses it. While recording, nothing is on screen except the menu bar indicator (D10).
- **Options popover**: ⇧⌘5-style checkmark menu — save location, countdown, FPS quick pick (30/60, synced with Settings), audio sources, mouse options, thumbnail/remember toggles. Advanced encoding (codec/quality/full FPS list/bitrate) lives in the Settings window, opened only from the menu bar menu (⌘,).
- **Windows that do exist**: Settings and the trim editor — the only two real windows, both secondary and closable without affecting recording. The floating thumbnail and its expanded preview panel (편집/삭제/완료) are transient non-activating panels, not windows.
- **Material**: never raw glass — every window/panel surface layers a dark tint (VS Code Dark family, #1e1e1e–#2e2e36 at 55–75% opacity) over the system material (`NSVisualEffectView`/glass APIs) with forced `.darkAqua` appearance, so surfaces stay chic and legible on bright wallpapers instead of washing out. The dark theme applies exclusively to three surfaces: the toolbar (and its options popover), the trim editor, and the preview (floating thumbnail + preview panel). Everything else — menu bar status item, `NSMenu` dropdowns, dialogs, system recording indicators — is system-rendered as-is, never custom-skinned.
- **Chrome buttons**: icon actions in panel/toolbar chrome are borderless (`.buttonStyle(.borderless)`) — icon-only, neutral monochrome (no red tint on destructive icons; danger is communicated by the confirmation dialog), shape revealed on hover only, hit target kept ≥ 28pt regardless of visual size.
- **Iconography**: in-app icons are real SF Symbols via `Image(systemName:)` (`pencil`, `trash`, etc.) — legal on Apple platforms; SF Symbols assets MUST NOT be committed to the source repository. Repo-shipped artwork (mockups, web, README) uses Lucide (ISC) equivalents tuned to SF stroke weight (~1.8/24).
- **Visual language**: native Liquid Glass — `.glassEffect`/glass background APIs where available (macOS 26+), graceful fallback to `NSVisualEffectView`/`.ultraThinMaterial` on macOS 13.3–15. No custom-drawn glass; use system materials so appearance, vibrancy, and accessibility (reduce transparency) come free.
- **Why**: zero learning curve (users already know ⇧⌘5), no focus-stealing during capture workflows, and the smallest possible UI surface for a recorder — the screen itself is the canvas.

### D12. Performance budget: zero-copy or nothing

- **Pipeline**: SCK IOSurface frames → optional Metal cursor pass → VideoToolbox hardware encode → incremental `AVAssetWriter` writes. No CPU pixel readback anywhere; software encoding is not a fallback, it is absent.
- **Threading**: SCK delivery queue is never blocked — encoder back-pressure is handled by a bounded queue with a degradation ladder (effect quality → capture FPS), never by stalling capture or the main thread.
- **Budgets** (baseline M1, 8 GB): ≤ 0.1% dropped frames over 10 min at up to 4K60; < 40 ms A/V drift per hour; app CPU ≤ 20% of one core at 1080p60 (≤ 35% at 4K60); steady-state memory ≤ 400 MB regardless of duration; toolbar summon ≤ 150 ms; record→first frame ≤ 500 ms; stop→playable ≤ 2 s; passthrough trim ≤ 3 s.
- **Enforcement**: CI benchmarks (capture smoke, encode throughput, memory watermark) fail the build on > 10% regression. Budgets live in the `performance` spec, not in tribal knowledge.

### D13. Localization: String Catalogs, en base + ko/ja/zh-Hans

- **Mechanism**: Xcode String Catalogs (`.xcstrings`), development language English. SwiftUI string literals auto-extract; a CI lint fails on user-facing literals outside the catalog and on < 100% translation completeness per shipping language.
- **Languages**: en (base), ko, ja, zh-Hans. Traditional Chinese (zh-Hant) deferred to a follow-up.
- **Resolution**: system language list + per-app override in System Settings — no in-app picker (native behavior, zero code).
- **Formatting**: `Date.FormatStyle`/`ByteCountFormatStyle` etc. everywhere; generated file names stay locale-neutral for cross-locale sort/sync stability.
- **QA**: localized-screenshot pass over toolbar/popover/settings/editor per release; layouts are content-sized (no fixed-width labels) to absorb CJK↔English length swings.

## Risks / Trade-offs

- [SCK behavior drifts across macOS versions (13.3 → 15+)] → runtime `#available` gates, capture smoke tests in CI on macOS 13/14/15 runners, graceful capability detection (e.g., hide 120 FPS-class options we don't offer anyway)
- [Cursor compositor can't hold 5K@60 on low-end hardware] → GPU-only path, per-frame budget monitor with automatic effect degradation (D4), FPS/resolution suggestions in UI when sustained drops are detected
- [Capped-VBR "CBR" isn't broadcast-true CBR] → label honestly in UI help; acceptable for the target use cases (uploads, tutorials)
- [Passthrough trim start snaps to keyframes — up to one GOP (~2 s) coarser than frame-exact] → visible snap in the UI (no silent surprise) + re-encode fallback offered as "frame-exact trim" option
- [Single mixed audio track prevents post-hoc mic/system separation] → documented; separate-track MOV option is a compatible future addition
- [Device disconnect mid-recording (mic unplugged, display removed)] → coordinator finalizes the file safely (never lose captured footage), surfaces a non-blocking toast, recording continues without the lost source when possible
- [Disk-full during long recordings] → free-space preflight (estimate from bitrate), background watermark check every 30 s, auto-stop with safe finalize at < 500 MB free

## Migration Plan

Greenfield — no migration. Ships as v0.1.0 behind no flags. Rollback = previous build (files produced are standard MP4/MOV, forward/backward compatible).

## Open Questions

- HEVC default on Apple Silicon vs H.264-everywhere default? (Current lean: H.264 default for share-anywhere compatibility; HEVC opt-in.)
- Should area-mode selection persist across launches (remember last region)? (Lean: yes, per display.)
