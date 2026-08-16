# Spec: recording-controls

## ADDED Requirements

### Requirement: Recording lifecycle
The user-facing recording lifecycle SHALL support idle, preparing, countdown, recording, and finishing, with the transitions: start (idle→preparing→countdown or recording), stop (recording→finishing→idle), cancel countdown (countdown→idle), and failure (preparing/countdown/recording/finishing→idle after cleanup). All entry points MUST operate on this single shared state. The core MAY retain pause/resume as an internal encoder capability, but the app SHALL NOT expose pause controls or a pause shortcut in this change.

#### Scenario: Start and stop
- **WHEN** the user starts a recording and later stops it
- **THEN** a single video file containing the captured content is finalized in the output folder

#### Scenario: Concurrent start prevented
- **WHEN** a recording is already in progress or finishing
- **THEN** start commands from any entry point are ignored

### Requirement: Recording countdown
The app SHALL optionally show an on-screen countdown before recording starts, with choices off, 3 seconds (default), 5 seconds, and 10 seconds. The countdown overlay MUST NOT appear in the recording, and pressing Esc during the countdown MUST cancel the pending recording.

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
While recording, the app SHALL display elapsed recording time as `M:SS` and a recording-specific stop control in the menu bar.

#### Scenario: Timer accuracy
- **WHEN** a recording has been running for 90 seconds
- **THEN** the displayed elapsed time reads 1:30 within ±1 second

### Requirement: Menu bar control
The app SHALL provide a menu bar status item at all times while running. While idle, its menu MUST offer: open the recording toolbar, open the last recording, open the output folder in Finder, open settings, and quit. While recording, a recording-specific status item SHALL show elapsed time and a one-click stop control. Quit during an active recording MUST warn the user and finalize the file safely if confirmed.

#### Scenario: Stop from menu bar
- **WHEN** the user clicks Stop in the menu bar during a recording started from the toolbar
- **THEN** the recording stops and the output file is finalized

#### Scenario: Recording status item
- **WHEN** a recording is in progress
- **THEN** the menu bar shows elapsed time and a stop control, and no recording toolbar is visible

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

### Requirement: Global keyboard shortcut
The app SHALL provide a user-configurable global keyboard shortcut for showing the recording toolbar. The default is ⇧⌘6. The shortcut MUST work while the app is in the background and MUST be reconfigurable or disableable in settings. Starting and stopping recordings SHALL require an explicit UI action.

#### Scenario: Shortcut reassignment
- **WHEN** the user records a new key combination for opening the toolbar in settings
- **THEN** the new combination takes effect immediately and the old one no longer triggers

### Requirement: Failure-safe finalization
If a recording ends abnormally (app crash, forced quit, power loss, disk full, capture source lost), the app MUST ensure the footage captured up to that point is recoverable as a playable file, and MUST NOT leave zero-byte or corrupt-unplayable files in the output folder without informing the user on next launch.

#### Scenario: Disk approaching full
- **WHEN** free space on the output volume drops below 500 MB during a recording
- **THEN** the recording auto-stops, the file is finalized playable, and the user is told why

#### Scenario: Crash recovery
- **WHEN** the app is force-quit during a recording and relaunched
- **THEN** the app recovers the interrupted recording into a playable file where technically possible, or informs the user that the recording was lost
