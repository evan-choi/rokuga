# Spec: video-trimming

## ADDED Requirements

### Requirement: Trim editor
The app SHALL provide a built-in trim editor, openable from the preview panel's Edit button and via drag-and-drop or Open With from Finder. The editor SHALL accept any MP4/MOV file with H.264/HEVC video (not only this app's recordings); unsupported files MUST be rejected with a clear message naming the unsupported format. The editor MUST show a video preview with play/pause, a timeline with a frame-thumbnail strip, and draggable start/end handles that define the range to keep.

#### Scenario: External file accepted
- **WHEN** the user drops an H.264 MP4 recorded by another tool onto the editor
- **THEN** it opens and trims exactly like a native recording

#### Scenario: Unsupported file rejected
- **WHEN** the user opens a file the editor cannot process (e.g., WebM)
- **THEN** a message names the format and no partial/corrupt state remains

#### Scenario: Opening the editor
- **WHEN** the user clicks Edit in the preview panel
- **THEN** the trim editor opens with the video loaded, handles at the full range, and playback paused at the first frame

#### Scenario: Selecting a keep range
- **WHEN** the user drags the start handle to 00:00:05 and the end handle to 00:00:20
- **THEN** the editor displays the resulting duration (00:00:15) and the preview playhead is constrained to the selected range

#### Scenario: Preview scrubbing
- **WHEN** the user drags a handle or the playhead
- **THEN** the preview updates to the frame at that position while dragging

#### Scenario: Precise time entry
- **WHEN** the user types an exact timecode for the start or end point
- **THEN** the corresponding handle moves to that time, clamped within the video's duration and ordered start < end

### Requirement: Lossless trim export
Saving a trim SHALL NOT re-encode the video by default: export MUST be lossless (identical quality) and complete in near-constant time regardless of video length. The start point SHALL snap to the nearest preceding sync frame, and the editor MUST visually indicate the snapped position before saving. If lossless export is impossible for the source file, the app SHALL fall back to re-encoding with a visible progress indicator and MUST inform the user.

#### Scenario: Lossless save
- **WHEN** the user saves a trim of a 1-hour recording
- **THEN** the trimmed file is written without quality loss and the export completes in seconds, not minutes

#### Scenario: Keyframe snap disclosure
- **WHEN** the user places the start handle between sync frames
- **THEN** the handle visibly snaps to the nearest preceding sync frame position before export, so the saved result matches the preview

#### Scenario: Re-encode fallback
- **WHEN** the source file cannot be exported losslessly
- **THEN** the app informs the user, re-encodes the selected range with a progress bar, and produces a playable result

### Requirement: Non-destructive output
Trimming MUST NOT modify or delete the original recording. The trimmed result SHALL be saved as a new file, with the user able to set its name and destination folder before saving (default: original name with a suffix, in the same folder).

#### Scenario: Original preserved
- **WHEN** the user saves a trimmed version of a recording
- **THEN** the original file remains unchanged, and a new file exists alongside it

#### Scenario: Custom name and destination
- **WHEN** the user edits the output name and picks a different folder in the save step
- **THEN** the trimmed file is created with that name in that folder

#### Scenario: Name collision
- **WHEN** the chosen output name already exists in the destination
- **THEN** the app proposes a non-conflicting name and never silently overwrites

### Requirement: Trim editor safety
The editor MUST prevent invalid operations: saving an empty or inverted range SHALL be impossible, and closing the editor with unsaved changes MUST ask for confirmation. Trim MUST be disabled for a file currently being recorded.

#### Scenario: Inverted range prevented
- **WHEN** the user drags the end handle before the start handle
- **THEN** the handles cannot cross and the range remains valid

#### Scenario: Unsaved-changes guard
- **WHEN** the user closes the editor after moving handles without saving
- **THEN** a confirmation dialog offers to save, discard, or cancel

#### Scenario: Active recording excluded
- **WHEN** a recording is still in progress
- **THEN** its in-progress file is not offered for trimming

### Requirement: Audio-only export
The trim editor SHALL offer an "Export Audio Only" option producing an M4A (AAC) file of the selected range with the same base name in the same folder, without modifying the original video. The option MUST be disabled with an explanation when the video has no audio track.

#### Scenario: Extract audio
- **WHEN** the user chooses Export Audio Only on a recording with audio
- **THEN** an M4A file with the selected range's audio appears next to the original, which remains unchanged

#### Scenario: No audio track
- **WHEN** the loaded video has no audio track
- **THEN** the option is disabled with an explanatory tooltip

### Requirement: Timeline zoom and navigation
The timeline SHALL support zooming from full-clip overview down to frame-level detail. On zoom-in, the timeline widens beyond the window and gains native horizontal scrolling; the zoom anchor MUST be the pointer position (gesture zoom) or the playhead (keyboard/slider zoom), so the content under the anchor stays put. Trim handles, the playhead, and the keep-range MUST stay consistent and draggable at every zoom level, with dragging precision increasing as the timeline zooms.

#### Scenario: Zoom in reveals horizontal scroll
- **WHEN** the user zooms the timeline beyond the window width
- **THEN** the timeline scrolls horizontally with native momentum physics, and a scroll indicator reflects the visible viewport

#### Scenario: Anchored zoom
- **WHEN** the user zooms in with the pointer over a specific frame
- **THEN** that frame remains stationary under the pointer while the timeline expands around it

#### Scenario: Frame-level precision
- **WHEN** the timeline is zoomed to maximum
- **THEN** individual frames are distinguishable and trim handles can be placed on an exact frame boundary

### Requirement: Trackpad and mouse input parity
Every editor interaction SHALL be first-class on both trackpad and mouse. Trackpad: pinch zooms the timeline, two-finger horizontal swipe scrolls it, and standard momentum/rubber-band behavior applies. Trackpad horizontal scroll over the video preview scrubs the playhead (QuickTime grammar); over the timeline it pans. Mouse: scroll wheel scrolls horizontally over the timeline, ⌘ + scroll wheel zooms, and an on-screen zoom slider with −/+ buttons (plus ⌘+/⌘−/⌘0 shortcuts, ⌘0 = fit clip) covers the same range. No function may exist only as a gesture.

#### Scenario: Pinch zoom on trackpad
- **WHEN** the user pinches outward over the timeline
- **THEN** the timeline zooms in smoothly around the pointer, matching native macOS gesture feel (immediate, proportional, interruptible)

#### Scenario: Mouse-only operation
- **WHEN** the user has only a mouse
- **THEN** ⌘ + scroll wheel and the zoom slider provide the full zoom range, and plain scroll wheel pans the zoomed timeline

#### Scenario: QuickTime-style scrub over the preview
- **WHEN** the user scrolls horizontally with two fingers over the video preview area (not the timeline)
- **THEN** the playhead scrubs through the clip QuickTime Player-style, while the same gesture over the timeline pans the zoomed timeline

#### Scenario: Fit to window
- **WHEN** the user presses ⌘0 or double-taps the trackpad with two fingers on the timeline
- **THEN** the timeline returns to full-clip overview with no horizontal scroll
