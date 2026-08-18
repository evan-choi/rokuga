## 1. Appearance foundations

- [x] 1.1 Add light, dark, increased-contrast, and reduce-transparency palette values to `GlassBackground`
- [x] 1.2 Apply the adaptive palette consistently to macOS 26 `glassEffect` and the macOS 13.3–15 `NSVisualEffectView` fallback
- [x] 1.3 Apply the saved appearance before app-owned surfaces are created while retaining `NSApp.appearance = nil` for Auto
- [x] 1.4 Keep the Appearance picker enabled during recording without unlocking recording-unsafe settings

## 2. Surface adoption

- [x] 2.1 Remove forced dark appearance from the toolbar and replace fixed white chrome with semantic colors
- [x] 2.2 Remove forced dark appearance from the preview panel and convert its header and playback chrome to semantic colors
- [x] 2.3 Remove both AppKit and SwiftUI dark overrides from the trim editor and replace its fixed background with a semantic window surface
- [x] 2.4 Verify the options popover, floating thumbnail chrome, Settings, onboarding, sheets, and alerts inherit the selected appearance
- [x] 2.5 Preserve fixed-contrast colors for capture selection, countdown, video overlays, timeline overlays, and the red recording indicator
- [x] 2.6 Clip toolbar and preview hosting layers to their rounded glass bounds so no rectangular backing or shadow remains visible

## 3. Automated coverage

- [x] 3.1 Add SettingsStore tests for the Auto default, Light and Dark round trips, and Reset returning to Auto
- [x] 3.2 Add a focused appearance propagation harness that verifies an existing window, panel, and SwiftUI hosting view update in place
- [x] 3.3 Extend the screenshot harness to render toolbar, preview, and editor chrome in both Light and Dark appearances

## 4. Specification alignment

- [x] 4.1 Update the active core-screen-recording design to replace the forced-dark policy with adaptive glass palettes
- [x] 4.2 Update the active app-preferences requirement so Appearance applies immediately to app-owned windows and transient panels
- [x] 4.3 Reconcile the core-screen-recording theme and accessibility task statuses with the implemented behavior

## 5. Verification

- [x] 5.1 Build the app and run the SettingsKit and existing core test suites
- [x] 5.2 Verify fixed Light, fixed Dark, and Auto system-following behavior while toolbar, popover, preview, and editor surfaces remain open
- [x] 5.3 Model contrast over white, black, and high-chroma backgrounds with the resolved contrast scrim and semantic color tokens; tune text to at least 4.5:1 and graphical controls to at least 3:1
- [x] 5.4 Verify Reduce Transparency and Increase Contrast on macOS 26 and document the macOS 13.3–15 fallback check in the QA matrix

## 6. Native material calibration

- [x] 6.1 Replace dimmed active chrome and foreground-derived control fills with full-strength semantic colors and system surfaces
- [x] 6.2 Lower normal scrim opacity enough to preserve visible backdrop contribution while retaining the defined contrast floor
- [x] 6.3 Update the contrast harness to measure the semantic selection and control surfaces used by the toolbar

## 7. Explicit contrast scrim

- [x] 7.1 Separate the native material from an alpha-composited contrast scrim so Light chrome remains legible over black content
- [x] 7.2 Update the screenshot and contrast harnesses to model the explicit scrim contract
- [x] 7.3 Build the app and verify Light, Dark, accessibility, and appearance propagation paths
