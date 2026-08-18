## Why

Selectable Auto, Light, and Dark appearances add state without improving the capture workflow. They can also leave dark toolbar foregrounds paired with a light appearance while native glass responds to dark desktop content, making controls unreadable.

## What Changes

- Remove the Appearance setting, stored theme value, and runtime theme switching.
- Apply Dark Aqua before any app-owned surface is created.
- Use one fixed Dark glass palette with an explicit contrast scrim so toolbar and preview controls remain readable over bright, dark, and high-chroma content.
- Retain Increase Contrast and Reduce Transparency behavior.
- Keep capture overlays and video-overlay controls fixed-contrast where required.
- Align the active core-screen-recording design, requirements, tasks, and QA commands with the fixed-Dark policy.

## Capabilities

### New Capabilities

- `adaptive-app-theme`: Fixed-Dark appearance, glass contrast, accessibility variants, and the boundary between app chrome and content overlays.

### Modified Capabilities

_None. The repository has no archived baseline specs; the related `app-preferences` capability remains in an active change._

## Impact

- App startup and Settings UI/model.
- SettingsKit models, persistence, and tests.
- Glass rendering and Dark-only visual verification.
- The active core-screen-recording design, app-preferences spec, task list, and QA matrix.
