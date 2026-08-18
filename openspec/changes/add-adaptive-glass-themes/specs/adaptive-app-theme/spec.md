## ADDED Requirements

### Requirement: Fixed Dark appearance
The app SHALL set Dark Aqua before creating app-owned surfaces and SHALL NOT expose or persist an appearance selection. App-owned windows, panels, and SwiftUI hosting views SHALL inherit the application appearance without local Light or Auto overrides.

#### Scenario: macOS uses Light appearance
- **WHEN** the app launches while macOS uses Light appearance
- **THEN** every app-owned window and panel renders in Dark Aqua from its first visible frame

#### Scenario: System appearance changes
- **WHEN** macOS changes its appearance while Rokuga is running
- **THEN** open app-owned windows and panels remain in Dark Aqua

#### Scenario: General settings
- **WHEN** the user opens General settings
- **THEN** no appearance or theme control is shown

### Requirement: Fixed-Dark glass surfaces
App-owned glass chrome SHALL render native material beneath an identically clipped Dark contrast scrim. The palette SHALL NOT depend on the desktop or system appearance. The macOS 26 glass implementation and macOS 13.3–15 visual-effect fallback MUST provide equivalent Dark behavior and MUST NOT rely on `.glassEffect.tint` as the contrast guarantee.

#### Scenario: Glass over bright content
- **WHEN** a glass surface appears over white or near-white content
- **THEN** the Dark scrim prevents the background from washing out its text, icons, selected state, and boundary

#### Scenario: Glass over dark content
- **WHEN** a glass surface appears over black or near-black content
- **THEN** its Dark palette remains stable and normal text reaches at least 4.5:1 while graphical controls reach at least 3:1

#### Scenario: Older macOS fallback
- **WHEN** an app-owned glass surface renders on macOS 13.3 through 15
- **THEN** it uses the visual-effect fallback with the same Dark palette and contrast requirements as macOS 26

#### Scenario: Rounded glass boundary
- **WHEN** a toolbar or preview glass surface is visible
- **THEN** no rectangular window backing, material edge, or window shadow appears outside its rounded boundary

#### Scenario: Native material remains perceptible
- **WHEN** transparency is enabled and Increase Contrast is disabled
- **THEN** untinted native material remains active below the scrim and backdrop variation remains visible

### Requirement: Dark semantic app chrome
App-owned chrome SHALL use semantic foreground and surface colors resolved under Dark Aqua. Colors used directly over captured screens or video MAY remain fixed when semantic recoloring would reduce visibility or change state meaning.

#### Scenario: Capture and timeline overlays
- **WHEN** capture selection or trim timeline overlays are visible
- **THEN** selection outlines, handles, dimming, keyframe ticks, and the playhead retain their fixed-contrast colors

#### Scenario: Recording state indicator
- **WHEN** the toolbar is visible
- **THEN** the recording action continues to use the red state indicator

### Requirement: Appearance accessibility variants
App-owned glass surfaces SHALL honor Reduce Transparency and Increase Contrast without changing available actions or state meaning.

#### Scenario: Reduce Transparency
- **WHEN** Reduce Transparency is enabled
- **THEN** each glass surface uses the opaque Dark background with readable foregrounds and the same controls

#### Scenario: Increase Contrast
- **WHEN** Increase Contrast is enabled
- **THEN** glass surfaces strengthen their Dark contrast scrim and boundary

#### Scenario: Accessibility settings change while visible
- **WHEN** Reduce Transparency or Increase Contrast changes while a glass surface is visible
- **THEN** the surface updates in place without recreating its window or panel
