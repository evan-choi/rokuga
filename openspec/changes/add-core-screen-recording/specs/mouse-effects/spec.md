# Spec: mouse-effects

## ADDED Requirements

### Requirement: Cursor visibility
The app SHALL offer a toggle to include or exclude the mouse cursor in screen recordings (default: include). Mouse effects settings SHALL apply to all three modes (Selected Area, Full Screen, Window).

#### Scenario: Cursor included
- **WHEN** cursor visibility is on and the user moves the mouse during a recording
- **THEN** the cursor is visible in the recorded video at its correct position

#### Scenario: Cursor excluded
- **WHEN** cursor visibility is off
- **THEN** the recorded video contains no cursor even while the mouse moves over the captured region

### Requirement: Pointer highlight
The app SHALL offer a highlight effect that renders a colored translucent circle around the cursor in the recording. The user MUST be able to configure the highlight's color, size, and opacity, and the effect MUST appear only in the recording — never on the live screen.

#### Scenario: Highlight rendered in recording only
- **WHEN** highlight is enabled with a yellow color and a recording is made
- **THEN** the recorded video shows a yellow circle following the cursor, while the live screen during recording shows no such circle

#### Scenario: Highlight customization
- **WHEN** the user changes highlight color, size, or opacity in settings
- **THEN** the next recording reflects the new appearance, and a settings preview shows the effect immediately

### Requirement: Click effects
The app SHALL offer click effects that render a brief animation (expanding ripple) at the cursor position when a mouse button is pressed during recording. Left-click and right-click effects MUST be independently toggleable with independently configurable colors, and the animation MUST appear only in the recording.

#### Scenario: Left click ripple
- **WHEN** left-click effect is enabled (red) and the user left-clicks during a recording
- **THEN** the recorded video shows a red ripple expanding from the click position at the moment of the click

#### Scenario: Distinct right click
- **WHEN** both effects are enabled with different colors and the user right-clicks
- **THEN** the recording shows the right-click color, not the left-click color

#### Scenario: Click effects off
- **WHEN** click effects are disabled and the user clicks during a recording
- **THEN** no ripple appears in the recorded video

### Requirement: Effect fidelity and performance
Mouse effect rendering MUST track the true cursor position with no more than one frame of positional lag at the configured frame rate, and enabling all mouse effects MUST NOT reduce the achieved recording frame rate by more than 10% relative to effects-off on supported hardware. If the system cannot sustain the frame budget, effects SHALL degrade gracefully (simplified rendering) rather than dropping video frames.

#### Scenario: Position accuracy
- **WHEN** the cursor moves rapidly across the captured region during a 60 FPS recording
- **THEN** the rendered cursor/highlight in each frame corresponds to the cursor's actual position at that frame within one frame's movement

#### Scenario: Performance under load
- **WHEN** all mouse effects are enabled during a full-screen 60 FPS recording on supported hardware
- **THEN** the achieved average frame rate is at least 90% of the same recording with effects disabled
