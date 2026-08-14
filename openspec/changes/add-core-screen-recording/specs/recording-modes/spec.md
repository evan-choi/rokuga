# Spec: recording-modes

## ADDED Requirements

### Requirement: Mode selection
The app SHALL present exactly three recording modes — Selected Area, Full Screen, and Window — as the primary choice on the floating recording toolbar (the app has no main window). The app SHALL remember the last used mode across launches and preselect it on next start.

#### Scenario: Switching modes
- **WHEN** the user selects a different recording mode while idle
- **THEN** the toolbar and on-screen overlays update to that mode's target picker and options, and no recording starts

#### Scenario: Mode restored across launches
- **WHEN** the user quits the app while Window mode is selected and relaunches it
- **THEN** Window mode is preselected

#### Scenario: Mode switching disabled while recording
- **WHEN** a recording is in progress or paused
- **THEN** mode selection controls are disabled until the recording stops

### Requirement: Selected Area mode
In Selected Area mode, the app SHALL let the user draw a rectangular region on any display by clicking and dragging, and SHALL record only that region. The selection overlay MUST show the region's pixel dimensions while drawing and allow adjustment via edge and corner handles before recording starts. The selected region SHALL be restored per display on subsequent uses.

#### Scenario: Drawing a region
- **WHEN** the user activates area selection and drags from one point to another on a display
- **THEN** a dimmed overlay shows the bright selected rectangle with live width×height pixel labels

#### Scenario: Adjusting a region
- **WHEN** the user drags an edge or corner handle of an existing selection
- **THEN** the region resizes accordingly and the pixel labels update in real time

#### Scenario: Moving a region
- **WHEN** the user drags from inside the selected rectangle
- **THEN** the entire region moves without resizing, constrained to the display bounds

#### Scenario: Window snapping assist
- **WHEN** the user hovers over an application window during area selection without dragging
- **THEN** the window's bounds are highlighted and a single click selects that window's frame as the region

#### Scenario: Cancelling selection
- **WHEN** the user presses Esc during area selection
- **THEN** the overlay closes and no recording starts

#### Scenario: Minimum region size
- **WHEN** the user attempts to confirm a region smaller than 50×50 pixels
- **THEN** the selection cannot be confirmed and the dimension label indicates the minimum size

#### Scenario: Region restored
- **WHEN** the user re-enters Selected Area mode on the same display arrangement
- **THEN** the previously used region is shown as the initial selection

### Requirement: Full Screen mode
In Full Screen mode, the app SHALL record an entire display at its native pixel resolution (subject to the output resolution cap). When multiple displays are connected, the app MUST let the user choose which display to record and MUST identify displays by name and resolution.

#### Scenario: Single display
- **WHEN** exactly one display is connected and the user starts a Full Screen recording
- **THEN** that display is recorded without prompting for a display choice

#### Scenario: Multiple displays
- **WHEN** two or more displays are connected
- **THEN** the app lists each display with its name and resolution, and records only the selected one

#### Scenario: Selected display disconnected before start
- **WHEN** the chosen display is disconnected while idle
- **THEN** the app falls back to the main display and updates the picker

### Requirement: Window mode
In Window mode, the app SHALL record a single chosen application window in isolation: windows overlapping the target MUST NOT appear in the recording, and the recording MUST follow the window if it moves or resizes. The window picker SHALL list capturable windows with application name, window title, and a thumbnail preview.

#### Scenario: Isolated window capture
- **WHEN** another window is dragged over the recorded window during recording
- **THEN** the overlapping window does not appear in the recorded video

#### Scenario: Window moved during recording
- **WHEN** the recorded window is moved to a different screen position
- **THEN** the recording continues to show the window's content without interruption

#### Scenario: Window resized during recording
- **WHEN** the recorded window is resized
- **THEN** the recording adapts to the new size without stopping

#### Scenario: Window closed during recording
- **WHEN** the recorded window is closed by its application
- **THEN** the recording stops automatically, the file is finalized safely, and the user is notified why the recording ended

#### Scenario: Minimized window excluded from picker
- **WHEN** the user opens the window picker
- **THEN** minimized windows and windows without content (zero size) are not offered

