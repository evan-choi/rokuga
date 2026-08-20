## Why

The current mixed AAC track plays reliably in standard players but prevents users from adjusting or removing system audio and microphone audio independently during editing. An optional editing-oriented track layout preserves the compatible default while allowing separate post-production control.

## What Changes

- Add an Audio setting for `Mixed` (default) or `Separate` track layout.
- Keep `Mixed` behavior unchanged: enabled system audio and microphone input are combined into one AAC track.
- In `Separate` mode, write system audio and microphone input as two independently identified AAC tracks in an MP4 or MOV file.
- Keep `Mixed` as the compatibility default and explain that some players may play only one separate track.
- When only one audio source is enabled, write one audio track regardless of the selected layout.
- Lock the track-layout control while recording and localize its labels and compatibility guidance.

## Capabilities

### New Capabilities

- `audio-track-layout`: Defines the Mixed/Separate setting, container compatibility, output track count and identity, and recording-time behavior.

### Modified Capabilities

None.

## Impact

- `SettingsKit`: persist the selected audio track layout and include it in per-recording snapshots.
- `EncoderKit`: create either one mixed audio input or independent system/microphone audio inputs with shared pause/resume timing.
- App settings UI: expose the option, playback guidance, and recording-time lock.
- Tests and localization: verify track counts, metadata, default compatibility, persistence, and all shipping languages.
- No new dependency or output format is introduced.
