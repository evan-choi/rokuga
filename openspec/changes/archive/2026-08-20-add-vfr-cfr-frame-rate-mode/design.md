## Context

`SCCaptureSession` forwards complete ScreenCaptureKit video samples to `AssetWriterSink`, which serializes video and audio writes on one encoder queue. `FrameRate` currently sets the ScreenCaptureKit minimum frame interval and the encoder's expected source rate, but it does not define whether idle periods remain sparse or receive duplicate frames.

The reader of this design is the maintainer implementing and reviewing output timing. The decision is whether the pipeline can provide both timing modes without adding a CPU pixel-copy path or changing capture delivery.

## Goals / Non-Goals

**Goals:**

- Persist VFR or CFR as a typed preference, with VFR as the default.
- Preserve capture timestamps in VFR mode.
- Produce uniformly spaced samples at the selected FPS in CFR mode, including static intervals.
- Keep video timing anchored to the first captured frame and synchronized with audio.
- Retain the IOSurface-backed pixel-buffer path.

**Non-Goals:**

- Adding frame-rate choices beyond the existing 30 and 60 FPS values.
- Changing bitrate control, codec selection, or ScreenCaptureKit's capture interval.
- Converting previously recorded files between VFR and CFR.

## Decisions

### Store frame-rate mode independently from target FPS

`SettingsKit` owns a `FrameRateMode` value with `variable` and `constant` cases under `output.frameRateMode`. `EncoderConfiguration.fromSettings` snapshots it with the other output settings at recording start. The Output pane binds directly to this preference and remains disabled while recording.

Keeping mode and FPS separate avoids encoding two independent choices in one enum. Existing preferences have no stored mode, so the typed accessor returns `variable`.

### Preserve source timing for VFR

VFR sends each complete source sample to `AVAssetWriterInput` with its ScreenCaptureKit presentation timestamp after pause-gap adjustment. The pipeline does not create samples for idle periods. `AVVideoExpectedSourceFrameRateKey` remains an encoder hint; it is not treated as a timing guarantee.

### Generate CFR samples on the encoder queue

CFR retains the latest complete `CMSampleBuffer` and emits timing-only copies on a `DispatchSourceTimer` running on the existing serial encoder queue. The first source timestamp anchors the track. Every emitted sample advances presentation time by exactly `1 / selectedFPS` and carries the same duration.

The retained sample shares its pixel buffer with each timing copy. CFR therefore adds encoder work and output frames but does not read or copy full-frame pixels on the CPU.

The timer starts after the first complete video frame. Pause cancels the timer while retaining the next output timestamp; the first post-resume frame restarts it. Finish and cancel stop the timer before the writer input closes. Writer back-pressure is handled on the same queue so presentation timestamps remain monotonic.

Alternatives considered:

- Retiming only when source frames arrive cannot fill a static interval because ScreenCaptureKit may not deliver complete frames during that interval.
- Relying on `AVVideoExpectedSourceFrameRateKey` does not create missing samples.
- Creating new pixel buffers through `AVAssetWriterInputPixelBufferAdaptor` would add allocation and copy behavior that conflicts with the zero-copy recording path.

### Keep the selector in advanced Output settings

The recording toolbar continues to expose only the common FPS shortcut. VFR/CFR appears in Settings › Output beside FPS because it changes file timing and compatibility rather than capture selection. The labels and selector title are present in the String Catalog for Korean, Japanese, and Simplified Chinese.

## Risks / Trade-offs

- [CFR increases file size and encoder load for static content] → Keep VFR as the default and synthesize only timing copies of the latest frame.
- [Timer scheduling jitter changes wall-clock delivery] → Derive media timestamps from the fixed frame duration rather than the timer's firing timestamp.
- [Encoder back-pressure prevents a scheduled append] → Keep all mutation on the encoder queue, preserve monotonic timestamps, and account for unaccepted frames in encoder statistics.
- [A retained frame extends pixel-buffer lifetime] → Retain one latest sample only and release it on finish or cancel.

## Migration Plan

No stored-value migration is required. Existing installations resolve the absent key to VFR. Rolling back to an older build leaves an unknown UserDefaults key that the older build ignores.

## Open Questions

_None._
