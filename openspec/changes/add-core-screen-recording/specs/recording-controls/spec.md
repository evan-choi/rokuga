# Spec: recording-controls

## ADDED Requirements

### Requirement: Recording lifecycle
The app SHALL support the states idle, countdown, recording, paused, and finishing, with the transitions: start (idle→countdown or idle→recording), pause (recording→paused), resume (paused→recording), stop (recording/paused→finishing→idle), and cancel countdown (countdown→idle). All entry points (recording toolbar, menu bar, hotkeys) MUST operate on this single shared state.

#### Scenario: Start and stop
- **WHEN** the user starts a recording and later stops it
- **THEN** a single video file containing the captured content is finalized in the output folder

#### Scenario: Pause and resume produce one continuous file
- **WHEN** the user pauses for any duration and then resumes, possibly multiple times
- **THEN** the final file contains no gap, no frozen segment, and no audio/video desynchronization at the splice points, and its duration equals the total recorded (non-paused) time

#### Scenario: Stop while paused
- **WHEN** the user stops a recording that is currently paused
- **THEN** the file is finalized normally, ending at the last recorded frame

#### Scenario: Concurrent start prevented
- **WHEN** a recording is already in progress or finishing
- **THEN** start commands from any entry point are ignored

### Requirement: Recording countdown
The app SHALL optionally show an on-screen countdown before recording starts, configurable from 1 to 10 seconds or off (default: 3 seconds). The countdown overlay MUST NOT appear in the recording, and pressing Esc during the countdown MUST cancel the pending recording.

#### Scenario: Countdown before start
- **WHEN** countdown is set to 3 and the user starts a recording
- **THEN** a 3-2-1 overlay is displayed, recording begins when it completes, and the overlay is absent from the recorded video

#### Scenario: Countdown cancelled
- **WHEN** the user presses Esc during the countdown
- **THEN** no recording starts and no file is created

#### Scenario: Countdown disabled
- **WHEN** countdown is set to off
- **THEN** recording begins immediately on start

### Requirement: Elapsed time and state feedback
While recording, the app SHALL display the elapsed recording time (HH:MM:SS) and a clearly distinguishable recording indicator. While paused, the indicator MUST visually differ from the recording state and the timer MUST hold its value.

#### Scenario: Timer accuracy
- **WHEN** a recording has been running for 90 seconds of active (non-paused) time
- **THEN** the displayed elapsed time reads 00:01:30 within ±1 second

#### Scenario: Paused indicator
- **WHEN** the user pauses a recording
- **THEN** the indicator switches to a paused representation and the timer stops advancing

### Requirement: Menu bar control
The app SHALL provide a menu bar status item at all times while running. While idle, its menu MUST offer: open the recording toolbar, start recording (in the current mode), open the last recording, open the output folder in Finder, open settings, and quit. While recording, the status item SHALL switch to the system-native recording presentation — red record dot, elapsed time, and pause/stop controls — so stopping is one click, exactly like the built-in ⇧⌘5 indicator. Quit during an active recording MUST warn the user and finalize the file safely if confirmed.

#### Scenario: Stop from menu bar
- **WHEN** the user clicks Stop in the menu bar during a recording started from the toolbar
- **THEN** the recording stops exactly as if stopped via the stop hotkey

#### Scenario: Native-style indicator while recording
- **WHEN** a recording is in progress
- **THEN** the menu bar shows a red dot, the elapsed time, and pause/stop controls, and no other app UI is visible on screen

#### Scenario: State-reflecting icon
- **WHEN** a recording is in progress
- **THEN** the menu bar icon changes to the recording representation, and reverts to idle after stop

#### Scenario: Quit while recording
- **WHEN** the user chooses Quit while a recording is active
- **THEN** the app asks for confirmation, and on confirm stops the recording, finalizes the file, then quits

### Requirement: Recording toolbar summon and placement
The app SHALL present its idle UI as a floating recording toolbar, summoned only by the menu bar icon or the toolbar global shortcut (default ⇧⌘6) — never automatically at app launch, mirroring the system capture UI. The toolbar MUST appear at the bottom-center of the display that currently contains the mouse pointer, MUST NOT steal keyboard focus from the frontmost app (non-activating panel), and SHALL dismiss on Esc or when a recording starts.

#### Scenario: Summon on the display under the mouse
- **WHEN** the user presses ⇧⌘6 while the mouse pointer is on a secondary display
- **THEN** the toolbar appears at the bottom-center of that secondary display

#### Scenario: Toolbar does not steal focus
- **WHEN** the toolbar is summoned while another app is frontmost
- **THEN** the other app keeps keyboard focus and its window state does not change

#### Scenario: Dismissal
- **WHEN** the user presses Esc or starts a recording
- **THEN** the toolbar disappears and nothing else of the app remains on screen (menu bar item aside)

### Requirement: Global keyboard shortcuts
The app SHALL provide user-configurable global keyboard shortcuts for: show/hide recording toolbar, start/stop recording, pause/resume recording. Defaults: toolbar ⇧⌘6, start/stop ⇧⌘2, pause/resume ⇧⌘4. Shortcuts MUST work while the app is in the background and MUST be reconfigurable and individually disableable in settings, with conflict detection against each other.

#### Scenario: Background stop
- **WHEN** the app is not the frontmost application and the user presses the start/stop shortcut during a recording
- **THEN** the recording stops

#### Scenario: Shortcut reassignment
- **WHEN** the user records a new key combination for start/stop in settings
- **THEN** the new combination takes effect immediately and the old one no longer triggers

#### Scenario: Conflicting assignment rejected
- **WHEN** the user tries to assign the same combination to two different actions
- **THEN** the app rejects the assignment and explains the conflict

### Requirement: Failure-safe finalization
If a recording ends abnormally (app crash, forced quit, power loss, disk full, capture source lost), the app MUST ensure the footage captured up to that point is recoverable as a playable file, and MUST NOT leave zero-byte or corrupt-unplayable files in the output folder without informing the user on next launch.

#### Scenario: Disk approaching full
- **WHEN** free space on the output volume drops below 500 MB during a recording
- **THEN** the recording auto-stops, the file is finalized playable, and the user is told why

#### Scenario: Crash recovery
- **WHEN** the app is force-quit during a recording and relaunched
- **THEN** the app recovers the interrupted recording into a playable file where technically possible, or informs the user that the recording was lost
