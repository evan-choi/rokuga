# Spec: capture-exclusion

## ADDED Requirements

### Requirement: Exclude own windows from capture
The app SHALL always exclude its own surfaces — recording toolbar, popovers, floating thumbnail, settings window, trim editor, countdown, and selection overlays — from Selected Area and Full Screen recordings. This is an invariant and SHALL NOT have an off setting.

#### Scenario: Toolbar hidden in recording
- **WHEN** an app surface overlaps the recorded area during recording
- **THEN** the recorded video shows the content behind it, not the app's surface

#### Scenario: Overlays always excluded
- **WHEN** a countdown or selection overlay is displayed over the recorded area
- **THEN** the overlay still does not appear in the recorded video

### Requirement: Exclude desktop icons from capture
The app SHALL offer a setting (default: off) that hides desktop icons and files from screen recordings while keeping the wallpaper visible. The live desktop MUST remain unchanged — the exclusion applies only to recorded content.

#### Scenario: Clean desktop in recording
- **WHEN** the setting is on and a full-screen recording captures the desktop
- **THEN** the recorded video shows the wallpaper without any desktop icons, while icons remain visible on the live screen

#### Scenario: Icons restored
- **WHEN** the setting is off
- **THEN** desktop icons appear in recordings normally

### Requirement: Mode applicability
Own-window exclusion SHALL apply automatically to Selected Area and Full Screen modes. The desktop-icons setting SHALL apply to those two modes. In Window mode, the desktop-icons control MUST be shown as not applicable because isolated window capture never includes the desktop.

#### Scenario: Window mode disables desktop-icon exclusion
- **WHEN** the user switches to Window mode
- **THEN** the desktop-icons toggle is disabled with a tooltip explaining it is unnecessary for isolated window capture

#### Scenario: Settings preserved across modes
- **WHEN** the user toggles desktop-icon exclusion in Selected Area mode, switches to Window mode, and returns
- **THEN** the previous desktop-icon setting is retained
