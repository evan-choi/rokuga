## ADDED Requirements

### Requirement: Configurable audio track layout
The app SHALL provide a persisted Audio setting with `Mixed` and `Separate` values. `Mixed` SHALL be the default for new and existing installations. The selected value SHALL be snapshotted when recording starts, and the control MUST be disabled while a recording is active.

#### Scenario: Default layout
- **WHEN** no audio track layout has been saved
- **THEN** the Audio setting shows `Mixed` and the next recording uses the mixed layout

#### Scenario: Layout persists
- **WHEN** the user selects `Separate`, quits, and relaunches the app
- **THEN** the Audio setting still shows `Separate`

#### Scenario: Layout is locked during recording
- **WHEN** a recording is active
- **THEN** the track-layout control is disabled and the active recording keeps its start-time layout

### Requirement: Mixed layout remains compatible
In `Mixed` mode, the app SHALL preserve the existing output behavior. When system audio and microphone capture are both enabled, the app SHALL combine them into one 48 kHz stereo AAC track. When exactly one source is enabled, the file SHALL contain one AAC track carrying that source. When neither source is enabled, the file SHALL contain no audio track.

#### Scenario: Both sources use one mixed track
- **WHEN** `Mixed` is selected and both system audio and microphone capture are enabled
- **THEN** the recording contains one AAC track in which both sources are audible

#### Scenario: One source in Mixed mode
- **WHEN** `Mixed` is selected and exactly one audio source is enabled
- **THEN** the recording contains one AAC track carrying the enabled source

#### Scenario: No enabled source
- **WHEN** both audio sources are disabled
- **THEN** the recording contains no audio track regardless of the saved layout

### Requirement: Separate audio tracks
In `Separate` mode with both sources enabled, the app SHALL write an MP4 or MOV file with two 48 kHz stereo AAC tracks instead of applying the audio-capture capability's default single-track mix: system audio first and microphone second. The system-audio track MUST NOT contain microphone samples, and the microphone track MUST NOT contain system-audio samples. The tracks SHALL carry locale-neutral titles `System Audio` and `Microphone`. The selected AAC bitrate SHALL apply to each track independently.

#### Scenario: Both sources are separated
- **WHEN** `Separate` is selected for MP4 or MOV and both audio sources produce sound
- **THEN** the file contains two AAC tracks whose first track contains only system audio and whose second track contains only microphone audio

#### Scenario: Tracks are identified
- **WHEN** an editor reads a recording created with two separate tracks
- **THEN** it can identify the tracks by the titles `System Audio` and `Microphone`

#### Scenario: One source in Separate mode
- **WHEN** `Separate` is selected and exactly one audio source is enabled
- **THEN** the output file contains one titled AAC track for the enabled source

### Requirement: Container-independent separate layout
The `Separate` option SHALL be available for MP4 and MOV. Changing the container MUST preserve the selected layout. The Audio settings SHALL explain that separate tracks are intended for editing and some players may play only one track.

#### Scenario: Separate is available for MP4
- **WHEN** MP4 is selected and both audio sources are enabled
- **THEN** the user can select `Separate` and the next recording contains two audio tracks

#### Scenario: Container changes to MP4
- **WHEN** `Separate` is selected and the user changes the container to MP4
- **THEN** the track layout remains `Separate` and the next recording contains separate audio tracks

#### Scenario: Separate playback guidance
- **WHEN** `Separate` is available in Audio settings
- **THEN** the UI explains that it is intended for editing and some players may play only one track

### Requirement: Shared recording timeline and finalization
All audio tracks SHALL use source presentation timestamps adjusted by the recording session's shared pause/resume splice offset. Stopping SHALL mark every created audio input as finished before finalizing the file. Start or cancel failures MUST clean up every created input and MUST NOT leave a partial output file in the destination folder.

#### Scenario: Separate tracks remain synchronized
- **WHEN** a recording with separate tracks crosses an internal pause/resume splice
- **THEN** both audio tracks remain synchronized with video using the same removed pause duration

#### Scenario: Separate tracks finalize together
- **WHEN** the user stops a recording with two audio tracks
- **THEN** both tracks are finalized in the same playable MP4 or MOV file

#### Scenario: Start failure cleans up
- **WHEN** either separate audio input cannot be configured before recording starts
- **THEN** recording start fails and no partial output file remains in the output folder
