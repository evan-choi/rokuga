## Why

Rokuga currently lets users choose a target FPS but not whether the output should preserve sparse capture timing or maintain a constant frame cadence. Users need VFR for efficient screen recordings and CFR for editors and workflows that expect uniformly spaced frames.

## What Changes

- Add a persistent Output setting for Variable Frame Rate (VFR) and Constant Frame Rate (CFR), defaulting to VFR.
- Preserve complete ScreenCaptureKit frame timestamps without synthesizing idle frames in VFR mode.
- Emit the latest complete frame at the selected FPS in CFR mode, including while captured content is static.
- Snapshot the selected mode at recording start and keep it locked with other recording-unsafe output controls.
- Localize the setting in English, Korean, Japanese, and Simplified Chinese and cover both timing modes with automated tests.

## Capabilities

### New Capabilities
- `frame-rate-mode`: User selection, persistence, recording-time behavior, and output timing guarantees for VFR and CFR recordings.

### Modified Capabilities

_None._

## Impact

- SettingsKit gains a typed frame-rate-mode preference.
- The Output settings pane exposes the new selector.
- EncoderKit applies source-timestamp or fixed-cadence timing without copying pixel data to the CPU.
- Encoder and settings tests, String Catalog translations, and benchmark configuration are updated.
