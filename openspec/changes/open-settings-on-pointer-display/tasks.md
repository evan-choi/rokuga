## 1. Settings Window Placement

- [x] 1.1 Capture the pointer display before invoking `openSettings()` and bridge `SettingsView` to its native `NSWindow` for both initial creation and later open requests.
- [x] 1.2 Center the settings window inside the selected display's `visibleFrame`, constrain it to remain fully visible, and fall back to the main display when needed.

## 2. Verification

- [x] 2.1 Build the Rokuga app target and resolve any compiler or concurrency errors introduced by the placement change.
- [x] 2.2 On a two-display setup, verify that a newly created settings window and an existing settings window both move to the display containing the pointer and remain fully visible.
