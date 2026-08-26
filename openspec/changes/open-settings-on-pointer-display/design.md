## Context

Rokuga declares a native SwiftUI `Settings` scene and opens it from `SettingsMenuItem` with `openSettings()`. SwiftUI controls the resulting `NSWindow` placement, so the window can appear away from the pointer on multi-display systems. The app already uses `NSEvent.mouseLocation`, `NSScreen.screens`, and `visibleFrame` to place the recording toolbar on the pointer's display.

## Goals / Non-Goals

**Goals:**

- Place Settings on the pointer's display for every explicit open request.
- Handle both initial window creation and reopening an existing settings window.
- Keep the settings window fully inside the display's visible frame.

**Non-Goals:**

- Persist a preferred display or per-display window position.
- Replace the native SwiftUI `Settings` scene or `openSettings()` behavior.
- Change placement of the toolbar, editor, or other app windows.

## Decisions

### Keep the native Settings scene and add a small AppKit placement bridge

`SettingsMenuItem` will capture the target display before calling `openSettings()`. A lightweight view attached to `SettingsView` will expose its actual `NSWindow` after SwiftUI creates it. The placement request will be applied immediately when a tracked window already exists, or retained until the new window attaches.

This keeps standard Settings lifecycle and Command-Comma handling. Replacing the scene with a custom window controller would duplicate behavior solely to control position, while relying only on a delayed `NSApp.keyWindow` lookup would be timing-dependent and could select an unrelated window.

### Select and center within the pointer display's visible frame

Display selection will reuse the app's existing AppKit pattern: find the `NSScreen` containing `NSEvent.mouseLocation`, then fall back to `NSScreen.main`. Placement will center the window and constrain its origin to `visibleFrame`, avoiding the menu bar and Dock. If the captured display is no longer available when placement occurs, the main display becomes the target.

Centering provides deterministic behavior without adding position persistence or coordinate mapping between displays.

## Risks / Trade-offs

- [SwiftUI creates the settings window after `openSettings()` returns] → Retain the pending target until the settings view reports its window.
- [Opening Settings again moves a window the user positioned manually] → Reposition only on an explicit Settings open request, never while the window remains in use.
- [A display disconnects between the request and placement] → Resolve the captured display against the current screen list and fall back to the main display.
