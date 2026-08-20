## 1. Fixed-Dark appearance

- [x] 1.1 Apply Dark Aqua before app-owned surfaces are created
- [x] 1.2 Remove the Appearance picker and runtime theme switching
- [x] 1.3 Remove Theme persistence, models, and persistence tests

## 2. Glass surfaces

- [x] 2.1 Use one Dark palette for macOS 26 glass and the macOS 15–25 visual-effect fallback
- [x] 2.2 Apply the shared Dark glass contract to the toolbar, tooltip, preview, and trim editor
- [x] 2.3 Preserve rounded clipping, fixed-contrast overlays, and semantic Dark chrome
- [x] 2.4 Retain Increase Contrast and Reduce Transparency behavior

## 3. Verification

- [x] 3.1 Replace appearance propagation checks with a fixed-Dark inheritance check
- [x] 3.2 Replace Light/Dark rendering checks with Dark contrast and accessibility checks
- [x] 3.3 Build the app and run SettingsKit and existing core tests
- [x] 3.4 Align the core-screen-recording spec, design, tasks, and QA matrix
