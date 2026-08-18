## Why

The Appearance setting stores and applies Auto, Light, and Dark, but the recording toolbar, preview panel, and trim editor override it with fixed dark appearances and colors. The original glass contrast treatment is also too transparent over arbitrary content, which can make controls unreadable.

## What Changes

- Apply Auto, Light, and Dark to every app-owned window and transient panel, including surfaces that are already open when the setting or system appearance changes.
- Replace fixed dark backgrounds and white chrome with semantic foreground and surface colors.
- Add light and dark alpha-composited contrast scrims above the native material so foreground contrast does not depend on material tint behavior.
- Strengthen glass surfaces when Increase Contrast is enabled and replace glass with an equivalent solid surface when Reduce Transparency is enabled.
- Keep capture overlays and video-overlay controls theme-independent when fixed colors are required for visibility over arbitrary content.
- Update the active core-screen-recording design and preference requirements to remove the forced-dark policy.

## Capabilities

### New Capabilities

- `adaptive-app-theme`: Appearance propagation, theme-aware glass palettes, accessibility variants, and the boundary between themed app chrome and fixed-contrast capture overlays.

### Modified Capabilities

_None. The repository has no archived baseline specs; the related `app-preferences` capability remains in an active change._

## Impact

- App appearance application and startup ordering in `SettingsModel` and `RokugaApp`.
- Glass rendering in `GlassBackground` for macOS 26 and the macOS 13.3–15 visual-effect fallback.
- Toolbar, options popover, preview, floating thumbnail, and trim-editor colors and appearance inheritance.
- Appearance persistence tests and light/dark visual QA.
- The active `add-core-screen-recording` design, app-preferences spec, and task list.
