# Spec: app-preferences

## ADDED Requirements

### Requirement: Settings window
The app SHALL provide a settings window — the only persistent window besides the trim editor — opened exclusively from the menu bar icon menu (or ⌘, while any app surface is focused), organized into panes: General, Recording, Audio, Mouse, Shortcuts, and Output. All changes MUST apply immediately (no Save button) and persist across app restarts. All app surfaces SHALL use native system glass materials (Liquid Glass where available, standard blur materials on older macOS), never custom-drawn chrome.

#### Scenario: Immediate apply
- **WHEN** the user changes any setting and closes the window
- **THEN** the change is already in effect and remains after quitting and relaunching the app

#### Scenario: Recording-time lock
- **WHEN** a recording is in progress
- **THEN** settings that cannot safely change mid-recording (codec, resolution, FPS, audio sources) are disabled with an explanatory note, while unrelated settings remain editable

### Requirement: Appearance theme
The app SHALL offer an appearance setting with Auto (follow system), Light, and Dark options (default: Auto), applying to all app windows.

#### Scenario: Fixed dark theme
- **WHEN** the user selects Dark while macOS is in light mode
- **THEN** all app windows render in dark appearance

#### Scenario: Auto follows system
- **WHEN** Auto is selected and macOS switches appearance
- **THEN** the app's windows switch accordingly without relaunch

### Requirement: Launch at login
The app SHALL offer a "Launch at login" toggle (default: off) that registers/unregisters the app as a login item, starting it in the menu bar without opening windows.

#### Scenario: Enabled login launch
- **WHEN** launch at login is enabled and the user logs in
- **THEN** the app is running with its menu bar item available, and no windows are opened

#### Scenario: Toggle reflects external change
- **WHEN** the user removes the login item from System Settings
- **THEN** the app's toggle shows the off state next time settings are opened

### Requirement: Reset to defaults
The app SHALL provide a "Reset All Settings" action that restores every preference to its default value after confirmation. Reset MUST NOT delete any recordings and MUST NOT be available while a recording is in progress.

#### Scenario: Reset restores defaults
- **WHEN** the user confirms Reset All Settings
- **THEN** all preferences return to documented defaults, recordings remain untouched, and first-run setup is not re-triggered

#### Scenario: Reset requires confirmation
- **WHEN** the user clicks Reset All Settings
- **THEN** a confirmation dialog appears before anything changes

### Requirement: Accessibility
Every interactive element (toolbar, options popover, trim editor, settings, floating thumbnail) SHALL have a VoiceOver label and be operable by keyboard alone. The app SHALL honor system accessibility settings: Reduce Transparency replaces glass materials with solid equivalents, Increase Contrast strengthens borders, and Reduce Motion disables the thumbnail slide animation and popover transitions.

#### Scenario: VoiceOver on the toolbar
- **WHEN** a VoiceOver user navigates the recording toolbar
- **THEN** each mode button, the options button, and the record button announce a meaningful label and state (e.g., "Selected Area, selected")

#### Scenario: Reduce Transparency
- **WHEN** Reduce Transparency is enabled in System Settings
- **THEN** all glass surfaces render as solid panels with equivalent contrast, with no functional difference

#### Scenario: Keyboard-only trim
- **WHEN** a keyboard-only user edits in the trim editor
- **THEN** handles can be focused and nudged frame-by-frame with arrow keys, and every button is reachable via Tab
