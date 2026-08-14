# Spec: post-recording

## ADDED Requirements

### Requirement: Save to output folder
When a recording stops, the app SHALL finalize the file directly into the configured output folder with an auto-generated name containing the date and time (e.g., `Rokuga 2026-08-15 at 14.22.31.mp4`). No import step, no app-internal library, and no database SHALL exist — the output folder in Finder is the single source of truth for recordings.

#### Scenario: File lands in the folder
- **WHEN** a recording stops
- **THEN** the finalized file exists in the output folder with a timestamped name and correct metadata (duration, resolution), with no further user action required

#### Scenario: Name collision
- **WHEN** a file with the generated name already exists
- **THEN** the app appends a numeric suffix and never overwrites an existing file

### Requirement: Floating thumbnail
After a recording stops, the app SHALL show a small floating thumbnail of the recording in the bottom-right corner of the screen (matching the native screenshot thumbnail behavior). Clicking it expands it in place into the preview panel; swiping it right or waiting for the timeout (default 5 seconds) dismisses it and leaves the file in place. The thumbnail MUST be excludable from subsequent captures per capture-exclusion, and a settings toggle SHALL disable it entirely.

#### Scenario: Thumbnail opens the preview
- **WHEN** the user clicks the floating thumbnail after stopping a recording
- **THEN** the thumbnail expands into the preview panel with that recording loaded

#### Scenario: Thumbnail dismissed
- **WHEN** the user ignores the thumbnail for the timeout duration
- **THEN** it slides away and the recording remains in the output folder unchanged

#### Scenario: Thumbnail disabled
- **WHEN** the thumbnail is disabled in settings and a recording stops
- **THEN** no thumbnail appears and a standard user notification with the file name is posted instead

### Requirement: Preview panel
The preview panel SHALL show the recording with play/pause and a scrub bar, and exactly three actions at its top-right: Edit, Delete, and Done. Two-finger horizontal trackpad scrolling anywhere over the panel SHALL scrub the playhead, QuickTime Player-style — proportional to scroll delta, with momentum, pausing playback while scrubbing; the scrub bar provides the mouse equivalent. Edit opens the recording in the trim editor and closes the preview. Delete moves the file to the Trash after confirmation and closes the preview. Done (or Esc) closes the preview leaving the file in the output folder. The panel is a non-activating floating panel — it MUST NOT steal focus and is excluded from capture per capture-exclusion.

#### Scenario: Trackpad scrub
- **WHEN** the user scrolls horizontally with two fingers over the preview video
- **THEN** the playhead scrubs through the recording following the gesture, exactly like QuickTime Player

#### Scenario: Edit from preview
- **WHEN** the user clicks Edit in the preview panel
- **THEN** the trim editor opens with the same recording and the preview closes

#### Scenario: Delete from preview
- **WHEN** the user clicks Delete and confirms
- **THEN** the file moves to the Trash (recoverable), the preview closes, and "last recording" tracking is cleared

#### Scenario: Done keeps the file
- **WHEN** the user clicks Done or presses Esc
- **THEN** the preview closes and the file remains untouched in the output folder

### Requirement: Reaching recordings
The app SHALL provide, from the menu bar menu: "Open Last Recording" (opens the most recent file in the preview panel) and "Open Output Folder" (reveals the folder in Finder). File management — rename, delete, move, organize — is delegated to Finder and MUST NOT be reimplemented in the app.

#### Scenario: Open last recording
- **WHEN** the user chooses "Open Last Recording" from the menu bar
- **THEN** the most recently finished recording opens in the preview panel

#### Scenario: Open output folder
- **WHEN** the user chooses "Open Output Folder"
- **THEN** Finder opens (or focuses) the configured output folder

#### Scenario: Last recording deleted externally
- **WHEN** the last recording was deleted in Finder and the user chooses "Open Last Recording"
- **THEN** the app explains the file no longer exists and offers to open the output folder instead

### Requirement: Recording completion feedback
The moment a recording is finalized SHALL be unmistakable: the menu bar indicator returns to idle, and either the floating thumbnail (default) or a notification (when the thumbnail is disabled) confirms the file name. If finalization fails, an error alert MUST name the file path attempted and the reason, and the partial file MUST be preserved for recovery whenever technically possible.

#### Scenario: Successful finalization feedback
- **WHEN** a recording finalizes successfully
- **THEN** the menu bar returns to idle and the thumbnail (or notification) shows the new file

#### Scenario: Finalization failure
- **WHEN** finalization fails (e.g., disk full at the last write)
- **THEN** an alert states the path and cause, and any recoverable partial file is kept, never silently discarded
