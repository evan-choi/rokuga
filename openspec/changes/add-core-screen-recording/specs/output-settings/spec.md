# Spec: output-settings

## ADDED Requirements

### Requirement: Container and codec selection
The app SHALL let the user choose the output container — MP4 or MOV (default: MP4) — and the video codec — H.264 or HEVC (H.265) (default: H.264). Every produced file MUST be playable in QuickTime Player and standard web browsers without additional software.

#### Scenario: Default output
- **WHEN** the user records with default settings
- **THEN** the result is an MP4 file with H.264 video that plays in QuickTime Player and Chrome

#### Scenario: HEVC selection
- **WHEN** the user selects HEVC and records
- **THEN** the file is encoded with HEVC and is at a visibly smaller size than an equivalent H.264 recording at the same quality setting

### Requirement: Quality and rate control
The app SHALL provide a quality control from 0 to 100 (default: 80) and a rate-control mode of VBR (default) or CBR. Higher quality values MUST produce higher bitrates. The settings UI MUST show an estimated file size per minute for the current combination of resolution, FPS, codec, and quality.

#### Scenario: Quality affects bitrate
- **WHEN** the same content is recorded at quality 40 and quality 90
- **THEN** the quality-90 file has a substantially higher bitrate and larger size

#### Scenario: Size estimate shown
- **WHEN** the user changes quality, FPS, or codec in settings
- **THEN** the estimated MB/minute figure updates immediately

#### Scenario: CBR bounded bitrate
- **WHEN** CBR mode is selected and highly dynamic content is recorded
- **THEN** the file's bitrate stays within the configured target band rather than spiking

### Requirement: Resolution and frame rate
The app SHALL record at the source's native pixel resolution by default, with a user-selectable maximum resolution cap of 1080p, 1440p, 4K, or 5K (5120×2880; default: native up to 5K). Downscaling MUST preserve aspect ratio. Frame rate SHALL be selectable from 15, 24, 30, and 60 FPS (default: 60), and the encoder MUST tolerate source frame delivery below the target without audio desync.

#### Scenario: Retina capture
- **WHEN** a Retina display region of 1280×720 points is recorded with no cap
- **THEN** the output video is 2560×1440 pixels

#### Scenario: Resolution cap applied
- **WHEN** the cap is 1080p and a 5K display is recorded full screen
- **THEN** the output is downscaled to fit within 1920×1080 while preserving aspect ratio

#### Scenario: Static content at 60 FPS
- **WHEN** a mostly static screen is recorded at 60 FPS for 10 minutes
- **THEN** the file's duration, timestamps, and audio remain correct despite fewer delivered frames

### Requirement: Audio encoding options
Recorded audio SHALL be encoded as AAC with a selectable bitrate of 128, 192, 256, or 320 kbps (default: 192) at 48 kHz stereo.

#### Scenario: Audio bitrate applied
- **WHEN** the user selects 320 kbps and records with audio
- **THEN** the file's audio track is AAC at 320 kbps, 48 kHz stereo

### Requirement: Output folder and file naming
The app SHALL save recordings to a user-chosen output folder (default: ~/Movies/Rokuga, created on first run). The folder MUST be changeable in settings with a standard folder picker, remain accessible across app restarts, and be revealable in Finder from settings. Files SHALL be auto-named with a timestamp pattern (e.g., `Recording 2026-08-15 at 14.30.22.mp4`) that sorts chronologically and never collides.

#### Scenario: Folder change persists
- **WHEN** the user selects a new output folder and relaunches the app
- **THEN** subsequent recordings are saved to the new folder without re-prompting

#### Scenario: Folder missing at recording start
- **WHEN** the configured output folder was deleted or its volume is unmounted
- **THEN** the app blocks the start, explains the problem, and offers to choose a new folder or recreate the default

#### Scenario: Unique auto-names
- **WHEN** two recordings finish within the same second
- **THEN** both files exist with distinct names

### Requirement: Settings presets
The app SHALL provide built-in output presets — "Maximum Quality", "Balanced" (default), and "Smaller Files" — that set codec/quality/FPS together, while still allowing each value to be adjusted individually afterward (showing a "Custom" state).

#### Scenario: Applying a preset
- **WHEN** the user selects "Smaller Files"
- **THEN** codec, quality, and FPS change to the preset's values in one action

#### Scenario: Custom state
- **WHEN** the user modifies FPS after applying a preset
- **THEN** the preset selector displays "Custom" without altering the user's other values

### Requirement: Toolbar FPS quick selection
The recording toolbar's options popover SHALL offer a quick frame-rate choice of 30 fps and 60 fps, two-way synced with the frame-rate setting in the Settings window. Selecting a value in either place updates both. When Settings holds a value outside {30, 60} (15 or 24), the popover SHALL show that custom value as an additional checked row.

#### Scenario: Quick switch from the toolbar
- **WHEN** the user picks 30 fps in the toolbar options popover
- **THEN** the next recording captures at 30 fps and Settings shows 30 FPS

#### Scenario: Custom value surfaced
- **WHEN** Settings is set to 24 FPS and the user opens the toolbar options popover
- **THEN** the popover shows "24 fps" checked alongside the unchecked 30/60 options
