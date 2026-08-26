## ADDED Requirements

### Requirement: Select the pointer display for Settings
The application SHALL select the connected display containing the pointer when the user requests Settings and SHALL fall back to the main display when no connected display contains the pointer.

#### Scenario: Pointer is on a secondary display
- **WHEN** the user requests Settings while the pointer is within a connected secondary display
- **THEN** the application selects that secondary display for the settings window

#### Scenario: Pointer is outside all display frames
- **WHEN** the user requests Settings while no connected display contains the pointer location
- **THEN** the application selects the main display for the settings window

### Requirement: Place Settings within the selected display
The application SHALL center the settings window within the selected display's visible frame and SHALL keep the complete window frame inside that visible frame whenever the settings window fits within it.

#### Scenario: Create the settings window
- **WHEN** the user requests Settings and no settings window exists
- **THEN** the application opens the settings window centered and fully visible on the selected display

#### Scenario: Reopen an existing settings window on another display
- **WHEN** the user requests Settings while an existing settings window is on a display other than the selected display
- **THEN** the application brings the settings window forward and moves it to the center of the selected display's visible frame
