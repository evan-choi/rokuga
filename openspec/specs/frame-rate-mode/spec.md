# frame-rate-mode Specification

## Purpose
TBD - created by archiving change add-vfr-cfr-frame-rate-mode. Update Purpose after archive.
## Requirements
### Requirement: Frame-rate mode selection
The app SHALL let the user select Variable Frame Rate (VFR) or Constant Frame Rate (CFR) independently of the target FPS in Output settings. VFR SHALL be the default. The selection MUST persist across app restarts, MUST apply to the next recording, and MUST remain unchanged for an active recording.

#### Scenario: Default mode
- **WHEN** no frame-rate-mode preference has been stored
- **THEN** Output settings shows VFR and the next recording uses VFR timing

#### Scenario: CFR persists
- **WHEN** the user selects CFR, quits the app, and relaunches it
- **THEN** Output settings still shows CFR and the next recording uses CFR timing

#### Scenario: Active recording keeps its timing mode
- **WHEN** a recording starts with either timing mode
- **THEN** that recording keeps the snapshotted mode until it finishes and the Output control is unavailable while recording

### Requirement: Variable frame-rate output
In VFR mode, the encoder SHALL preserve the presentation timestamps of complete frames delivered by ScreenCaptureKit, after applying any recording-clock splice adjustment. The encoder MUST NOT synthesize frames only to fill capture-source idle periods.

#### Scenario: Static content remains sparse
- **WHEN** VFR is selected and the captured content remains unchanged
- **THEN** the encoder writes complete source frames with their capture timing and does not duplicate the latest frame to reach the target FPS

#### Scenario: Source delivery below target FPS
- **WHEN** complete source frames arrive below the selected target FPS
- **THEN** their relative presentation timing is preserved and audio remains synchronized

### Requirement: Constant frame-rate output
In CFR mode, the encoder SHALL emit video samples at uniform intervals of `1 / selectedFPS`, starting at the first complete captured frame. When no new complete frame is available for an interval, the encoder MUST repeat the latest complete frame without copying full-frame pixels to CPU memory. Video duration and audio synchronization MUST remain correct through finish.

#### Scenario: Static content receives duplicate frames
- **WHEN** CFR at 30 FPS is selected and the captured content remains static
- **THEN** the video track continues with uniformly spaced 1/30-second samples using the latest complete frame

#### Scenario: New content replaces the repeated frame
- **WHEN** CFR is active and a new complete source frame arrives
- **THEN** subsequent output intervals use the new frame while preserving the fixed presentation-time cadence

#### Scenario: CFR recording finishes with audio
- **WHEN** a CFR recording with audio is stopped after a static interval
- **THEN** the finalized video and audio durations represent the recorded interval and remain synchronized
