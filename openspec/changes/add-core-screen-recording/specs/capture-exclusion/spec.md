# Spec: capture-exclusion

## ADDED Requirements

### Requirement: Exclude own windows from capture
The app SHALL offer a setting (default: on) that excludes all of the app's own surfaces — recording toolbar, popovers, floating thumbnail, settings window, trim editor — from screen recordings. The countdown overlay and region-selection overlay MUST always be excluded from recordings regardless of this setting.

#### Scenario: Toolbar hidden in recording
- **WHEN** the setting is on and an app surface overlaps the recorded area during recording
- **THEN** the recorded video shows the content behind it, not the app's surface

#### Scenario: Own windows visible when disabled
- **WHEN** the setting is off and an app window overlaps the recorded area
- **THEN** the app's window appears in the recording

#### Scenario: Overlays always excluded
- **WHEN** a countdown or selection overlay is displayed over the recorded area, with the exclusion setting off
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
Both exclusion settings SHALL apply to Selected Area and Full Screen modes. In Window mode, the controls MUST be shown as not applicable (disabled with an explanatory tooltip), since isolated window capture never includes other windows or the desktop.

#### Scenario: Window mode disables exclusion controls
- **WHEN** the user switches to Window mode
- **THEN** the exclusion toggles are disabled with a tooltip explaining they are unnecessary for isolated window capture

#### Scenario: Settings preserved across modes
- **WHEN** the user toggles exclusion settings in Selected Area mode, switches to Window mode, and returns
- **THEN** the previous exclusion settings are retained
