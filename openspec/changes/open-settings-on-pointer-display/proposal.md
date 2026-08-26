## Why

On multi-display setups, Rokuga's settings window can appear on a different display from the pointer, forcing users to find and move it before changing settings. Opening Settings on the display currently under the pointer keeps the menu-bar interaction and its result in the same visual context.

## What Changes

- Determine the pointer's display whenever the user opens Rokuga Settings.
- Place the settings window within that display's visible frame, including when an existing settings window is brought forward again.
- Fall back to the main display when no display contains the pointer location.

## Capabilities

### New Capabilities

- `settings-window-placement`: Defines how the settings window selects and fits within the pointer's display when opened.

### Modified Capabilities

None.

## Impact

- Affects the SwiftUI Settings scene and its menu command in `App/Sources/RokugaApp.swift`.
- Uses existing AppKit display and window APIs; no new dependency or persisted setting is required.
