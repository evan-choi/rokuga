# Spec: audio-capture

## ADDED Requirements

### Requirement: System audio capture without drivers
The app SHALL record the Mac's system audio (sound produced by other applications) into screen recordings without requiring the user to install any audio driver or virtual device. System audio capture SHALL be toggleable (default: on) and MUST NOT include the app's own sound effects (e.g., countdown ticks) in the recording.

#### Scenario: System audio recorded
- **WHEN** system audio is enabled and a video plays in a browser during a screen recording
- **THEN** the browser's audio is present in the recorded file

#### Scenario: System audio disabled
- **WHEN** system audio is toggled off and a recording is made while music plays
- **THEN** the recorded file contains no system audio

#### Scenario: Own app sounds excluded
- **WHEN** the app plays its own notification sound during a recording
- **THEN** that sound is not present in the recorded file

#### Scenario: Volume-independent capture
- **WHEN** the user records with system output volume muted on the speakers
- **THEN** application audio is still captured at its source level

### Requirement: Microphone capture
The app SHALL record from a microphone, toggleable independently of system audio (default: off). The user MUST be able to choose the input device from all connected microphones by name, with a live input level meter shown in settings and in the pre-recording UI. The device list MUST update when microphones are connected or disconnected.

#### Scenario: Microphone recorded
- **WHEN** microphone capture is enabled with a selected device and the user speaks during recording
- **THEN** the voice is present in the recorded file

#### Scenario: Device selection
- **WHEN** multiple microphones are connected
- **THEN** the user can pick one by name and the level meter reflects the chosen device's input

#### Scenario: Microphone disconnected mid-recording
- **WHEN** the active microphone is unplugged during a recording
- **THEN** the recording continues with the remaining audio sources, and the user is notified non-intrusively

#### Scenario: Default device fallback
- **WHEN** the previously selected microphone is not connected at recording start
- **THEN** the app uses the system default input and indicates the substitution

### Requirement: Simultaneous capture and mixing
When both system audio and microphone are enabled, the app SHALL record both simultaneously, mixed into a single audio track that plays back correctly in standard players. The mix MUST remain synchronized with video for recordings of at least 4 hours (drift < 50 ms).

#### Scenario: Both sources mixed
- **WHEN** both sources are enabled and both produce sound during a recording
- **THEN** the recorded file contains one audio track in which both are audible

#### Scenario: Long-recording sync
- **WHEN** a 4-hour recording with both sources completes
- **THEN** audio remains synchronized with video within 50 ms across the entire duration

### Requirement: No-audio recording
The app SHALL allow recording with all audio disabled, producing a video-only file with no audio track, and the pre-recording UI MUST make the "no audio" condition visually evident.

#### Scenario: Silent recording
- **WHEN** both system audio and microphone are off and a recording is made
- **THEN** the resulting file has no audio track

#### Scenario: No-audio warning
- **WHEN** all audio sources are off in a screen recording mode
- **THEN** the recording toolbar shows a muted-state indicator before recording starts

