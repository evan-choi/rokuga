# Spec: output-settings

## ADDED Requirements

### Requirement: Container and codec selection
The app SHALL let the user choose the output container — MP4 or MOV (default: MOV) — and the video codec — H.264 or HEVC (H.265) (default: HEVC). Every supported combination MUST be playable in QuickTime Player without additional software. H.264 with MP4 is the compatibility choice for browser playback.

#### Scenario: Default output
- **WHEN** the user records with default settings
- **THEN** the result is a MOV file with HEVC video that plays in QuickTime Player

#### Scenario: HEVC selection
- **WHEN** the user selects HEVC and records
- **THEN** the file is encoded with HEVC and is at a visibly smaller size than an equivalent H.264 recording at the same quality setting

### Requirement: Quality and rate control
The app SHALL provide a quality control from 0 to 100 (default: 80) and a rate-control mode of VBR (default) or CBR. Higher quality values MUST produce higher bitrates without changing the selected codec profile or bypassing rate control at quality 100. The app MUST NOT fractionally rescale native source dimensions merely to make them even.

#### Scenario: Quality affects bitrate
- **WHEN** the same content is recorded at quality 40 and quality 90
- **THEN** the quality-90 file has a substantially higher bitrate and larger size

#### Scenario: Maximum quality remains predictable
- **WHEN** quality changes from 99 to 100
- **THEN** the encoder keeps the same codec profile and rate-control strategy while increasing the target bitrate along the same quality curve

#### Scenario: Odd-sized captures preserve the native pixel grid
- **WHEN** an odd-sized native screen region containing text and one-pixel lines is recorded
- **THEN** the captured pixel grid is not fractionally rescaled or cropped and fine edges remain visually faithful at 100% playback size

#### Scenario: CBR bounded bitrate
- **WHEN** CBR mode is selected and highly dynamic content is recorded
- **THEN** the file's bitrate stays within the configured target band rather than spiking

### Requirement: Color fidelity
The capture stream SHALL be color-matched to sRGB at the source, and every output file MUST carry color metadata that matches the encoded pixel values — BT.709 primaries, sRGB (IEC 61966-2-1) transfer function, and BT.709 YCbCr matrix — for all codecs and quality settings. Cursor-composited frames MUST carry the same color tags as passthrough frames. The writer MUST NOT tag color properties that differ from the capture buffers' actual color space.

#### Scenario: Color metadata present
- **WHEN** any recording finishes
- **THEN** the file reports bt709 color primaries, iec61966-2-1 transfer function, and bt709 matrix instead of unknown color metadata

#### Scenario: On-screen colors reproduced
- **WHEN** a static sRGB test pattern is recorded and the file is decoded
- **THEN** the decoded pixel values match the authored sRGB values within encoder rounding, independent of the monitor's ICC profile

### Requirement: Resolution and frame rate
The app SHALL record at the source's native pixel resolution by default, with a user-selectable maximum resolution cap of 1080p, 1440p, 4K, or 5K (5120×2880; default: native up to 5K). Downscaling MUST preserve aspect ratio. Frame rate SHALL be selectable as 30 FPS, 60 FPS (default), or Match Display. Match Display MUST resolve once at recording start to the capture target display's current refresh rate, rounded to the nearest whole FPS, and MUST fall back to 60 FPS when the refresh rate is unavailable. A window target MUST use the display containing the largest portion of the window at recording start. The encoder MUST tolerate source frame delivery below the target without audio desync.

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
The app SHALL save recordings to a user-chosen output folder (default: ~/Movies/Rokuga, created on first run). The folder MUST be changeable in settings with a standard folder picker, remain accessible across app restarts, and be revealable in Finder from settings. Files SHALL be auto-named with a timestamp pattern (e.g., `Recording 2026-08-15 at 14.30.22.mov` for the default container) that sorts chronologically and never collides. The extension SHALL match the selected container.

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
The recording toolbar's options popover SHALL offer 30 FPS, 60 FPS, and Match Display, two-way synced with the frame-rate setting in the Settings window. Selecting a value in either place updates both.

#### Scenario: Quick switch from the toolbar
- **WHEN** the user picks 30 fps in the toolbar options popover
- **THEN** the next recording captures at 30 fps and Settings shows 30 FPS

#### Scenario: Display refresh rate resolved at recording start
- **WHEN** Match Display is selected and recording starts on a 180 Hz display
- **THEN** capture and encoding use 180 FPS for that recording
