# Spec: mouse-effects

## ADDED Requirements

### Requirement: Cursor visibility
The app SHALL offer a toggle to include or exclude the system mouse cursor in screen recordings (default: include). ScreenCaptureKit MUST render the cursor directly into the capture stream, and the setting SHALL apply to all three modes (Selected Area, Full Screen, Window).

#### Scenario: Cursor included
- **WHEN** cursor visibility is on and the user moves the mouse during a recording
- **THEN** the cursor is visible in the recorded video at its correct position

#### Scenario: Cursor excluded
- **WHEN** cursor visibility is off
- **THEN** the recorded video contains no cursor even while the mouse moves over the captured region

### Requirement: Click effects
The app SHALL offer a click-effect toggle backed by ScreenCaptureKit's native mouse-click indicator. When enabled, ScreenCaptureKit MUST draw the system circular indicator directly into the BGRA capture stream when the user clicks. The effect SHALL remain independent of cursor visibility, appear only in the recording, and retain its system-owned appearance without app-specific cursor sampling, composition, color, or animation customization.

#### Scenario: Native click indicator
- **WHEN** click effects are enabled and the user clicks during a recording
- **THEN** the recorded video shows the macOS circular click indicator at the click position

#### Scenario: Indicator with hidden cursor
- **WHEN** click effects are enabled while cursor visibility is off
- **THEN** the native click indicator remains visible in the recording without rendering the cursor

#### Scenario: Click effects off
- **WHEN** click effects are disabled and the user clicks during a recording
- **THEN** no click indicator appears in the recorded video
