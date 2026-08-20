## Context

This document is the implementation contract for adding an optional editing-oriented audio layout without changing the default recording output.

The current capture path already distinguishes `.systemAudio` and `.microphone` samples before `AssetWriterSink`. In Mixed mode, `AssetWriterSink` owns one `AVAssetWriterInput`; `AudioMixer` converts microphone input to 48 kHz stereo and adds it to system audio. Mic-only and system-only recordings write directly to that input. `EncoderConfiguration` snapshots the two source toggles, while `SettingsStore` persists them.

The change crosses SettingsKit, the app settings UI, and EncoderKit. MP4 multi-track playback varies by player, so separate tracks are limited to MOV and remain opt-in.

## Goals / Non-Goals

**Goals:**

- Preserve Mixed as the default and keep its encoded output unchanged.
- Produce independently editable system-audio and microphone tracks when Separate and MOV are selected.
- Keep both tracks on the existing recording timeline across start, pause/resume, finish, and cancel.
- Make invalid MP4/Separate combinations impossible in the UI and harmless in a recording snapshot.

**Non-Goals:**

- Separate tracks in MP4.
- A third pre-mixed playback track alongside the two source tracks.
- Per-source gain, mute automation, monitoring, noise reduction, or post-recording mixing.
- Multiple microphone devices, device selection, disconnect recovery, or a level meter.
- Changing the existing audio bitrate choices or exposing a user-facing track player.

## Decisions

### Keep Mixed as the compatibility default

The product SHALL add `AudioTrackLayout.mixed` and `.separate`, persisted by `SettingsStore`. Missing or unknown values resolve to `.mixed`. `EncoderConfiguration` snapshots the layout at recording start.

The alternatives were keeping mixed output only, making all MOV recordings separate, or adding an option. Mixed-only prevents independent editing. Separate-by-default changes playback behavior for every user. An option preserves current playback while making the editing trade-off explicit.

### Normalize MP4 to Mixed at the settings boundary

The Audio settings disable Separate while MP4 is selected. Changing the container to MP4 while Separate is saved sets the persisted layout to Mixed. `EncoderConfiguration` also exposes an effective layout that resolves to Mixed for MP4, so stale defaults and direct core callers cannot create an unsupported combination. MOV snapshots retain Separate with one enabled source so the resulting track can keep its source title.

This normalization is preferred over failing at recording start: the container and layout are local settings, so the app can present a valid state before capture begins.

### Reuse the existing source routing

`AssetWriterSink` SHALL select its audio inputs once in `start()`:

- Mixed with any enabled source: one audio input; both sources continue through the existing direct/mixer paths.
- Separate with both sources: one system input and one microphone input; `AudioMixer` is not created.
- Either layout with one enabled source: one input for that source.
- No enabled source: no audio input.

Separate mode retimes each incoming sample and appends it only to its matching input. It does not copy samples between tracks or add a new capture queue.

```mermaid
sequenceDiagram
    participant SCStream
    participant MicrophoneCapture
    participant AssetWriterSink
    participant SystemInput as AVAssetWriterInput(system)
    participant MicInput as AVAssetWriterInput(microphone)
    SCStream->>AssetWriterSink: append(sampleBuffer, of: .systemAudio)
    AssetWriterSink->>SystemInput: append(retimedSystemSample)
    MicrophoneCapture->>AssetWriterSink: append(sampleBuffer, of: .microphone)
    AssetWriterSink->>MicInput: append(retimedMicrophoneSample)
```

### Share splice timing and lifecycle ownership

The sink remains the owner of every writer input. Both separate paths use the existing source PTS and the same accumulated pause offset from `SpliceClock`. The first sample after resume establishes the shared offset; later samples from either source use that offset.

`start()` creates and validates all required inputs before `AVAssetWriter.startWriting()`. If any input cannot be added, start fails and the sink removes the output. `finish()` marks video and every created audio input finished before `finishWriting()`. `cancel()` cancels the writer and removes the partial file. A source that stops delivering samples does not block the remaining source or finalization.

### Use stable track identity and per-track bitrate

When both separate tracks exist, the writer adds system audio first and microphone second. Each input receives locale-neutral title metadata: `System Audio` or `Microphone`. Deterministic order provides a fallback for editors that do not expose titles.

The selected AAC bitrate applies to each separate track. A two-track file can therefore use approximately twice the audio bitrate of the equivalent Mixed recording. Splitting one bitrate between tracks would reduce quality and make the existing bitrate setting misleading.

### Keep the option in Audio settings

Track layout belongs in Settings › Audio, not the recording toolbar. The toolbar keeps source toggles; layout is an output/editing preference. The control is disabled during active recording and snapshots only at the next start. MOV-only and player-compatibility guidance comes from the String Catalog in all shipping languages.

## Risks / Trade-offs

- [Some players play only one audio track] → Keep Mixed as default, restrict Separate to MOV, and describe Separate as editing-oriented.
- [Separate output is larger] → State that the selected bitrate applies per track; do not silently lower either source's quality.
- [An editor ignores title metadata] → Write tracks in deterministic system-then-microphone order.
- [One audio input backpressures independently] → Check readiness per input and test that one source does not route into or block the other source's track.
- [Existing and new settings drift] → Make `AudioTrackLayout` and the effective-layout rule the single core contract used by the UI snapshot and writer.

## Migration Plan

No file migration is required. Existing installations have no layout key and resolve to Mixed. Existing recordings are unchanged. Rollback ignores the new preference key and continues producing mixed files; recordings already produced with separate MOV tracks remain standard MOV files.

## Verification

- Settings tests cover the Mixed default, persistence, reset, and MP4 normalization.
- Asset-writer integration tests inspect zero, one, mixed, and separate output track counts and titles.
- Source-isolation fixtures give system and microphone buffers distinct signals and verify each decoded separate track contains only its source.
- Pause/resume integration verifies that both separate tracks use the same splice duration and remain aligned with video.
- Start-failure and cancel tests verify that partial files are removed.
- SwiftLint, SwiftFormat, localization completeness, unsigned app build, and `openspec validate add-separate-audio-tracks --strict` must pass.

## Open Questions

None.
