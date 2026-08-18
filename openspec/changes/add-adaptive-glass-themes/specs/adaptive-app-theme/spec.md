## ADDED Requirements

### Requirement: Appearance selection and persistence
The app SHALL provide Auto, Light, and Dark appearance options, default to Dark, apply a selection immediately, and persist it across launches. Auto SHALL follow the effective macOS appearance.

#### Scenario: Fixed light appearance
- **WHEN** the user selects Light while macOS uses Dark appearance
- **THEN** all app-owned window and panel chrome renders with the light palette without relaunching

#### Scenario: Fixed dark appearance
- **WHEN** the user selects Dark while macOS uses Light appearance
- **THEN** all app-owned window and panel chrome renders with the dark palette without relaunching

#### Scenario: Auto follows a system change
- **WHEN** Auto is selected and macOS changes its effective appearance
- **THEN** all open app-owned windows and panels adopt the new appearance without being recreated

#### Scenario: Appearance is restored at launch
- **WHEN** the app launches with a previously saved Light or Dark selection
- **THEN** the saved appearance is active before the first app-owned surface becomes visible

#### Scenario: Appearance remains editable while recording
- **WHEN** a recording is active and the user opens General settings
- **THEN** the Appearance control remains enabled and a theme change does not alter the recording configuration

### Requirement: Theme-aware glass surfaces
The recording toolbar SHALL match the system capture toolbar by using untinted native material without an app-defined scrim or border. Options popovers, preview panels, and other app-owned glass chrome SHALL resolve their contrast scrim, border, and foreground colors from the effective appearance. With transparency enabled, an identically clipped scrim SHALL be alpha-composited above those surfaces' native material. The macOS 26 glass implementation and the macOS 13.3–15 visual-effect fallback MUST provide equivalent theme behavior and MUST NOT rely on `.glassEffect.tint` as the contrast guarantee.

#### Scenario: Light glass over bright content
- **WHEN** a scrimmed light glass surface appears over a white or near-white background
- **THEN** its boundary remains distinguishable and its normal text reaches a contrast ratio of at least 4.5:1 while graphical controls reach at least 3:1

#### Scenario: Light glass over black content
- **WHEN** a scrimmed light glass surface appears over a black or near-black background
- **THEN** its explicit light scrim establishes a readable surface while the native material remains active underneath, normal text reaches at least 4.5:1, and graphical controls reach at least 3:1

#### Scenario: Dark glass over bright content
- **WHEN** a scrimmed dark glass surface appears over a white or near-white background
- **THEN** its explicit dark scrim prevents the background from washing out its text, icons, and selected state

#### Scenario: Older macOS fallback
- **WHEN** an app-owned glass surface renders on macOS 13.3 through 15
- **THEN** it uses the visual-effect fallback with the same effective theme and contrast requirements as the macOS 26 surface

#### Scenario: Rounded glass boundary
- **WHEN** a toolbar or preview glass surface is visible
- **THEN** no rectangular window backing, material edge, or window shadow appears outside its rounded boundary

#### Scenario: Native material remains perceptible
- **WHEN** a glass surface renders with transparency enabled and Increase Contrast disabled
- **THEN** untinted native material remains active beneath the explicit contrast scrim, and the scrim preserves visible backdrop variation instead of reducing the system material to an opaque-looking custom fill

### Requirement: Semantic app chrome
App-owned chrome SHALL use appearance-aware semantic foreground and surface colors instead of fixed dark backgrounds or fixed white foregrounds. A theme change SHALL update surfaces that are already visible.

#### Scenario: Open toolbar changes theme
- **WHEN** the user changes from Dark to Light while the recording toolbar is visible
- **THEN** the toolbar's native background, icons, selected mode, and record-button chrome update in place

#### Scenario: Open preview changes theme
- **WHEN** the effective appearance changes while the preview panel is visible
- **THEN** the panel chrome updates in place while the video image and player letterboxing remain unchanged

#### Scenario: Trim editor changes theme
- **WHEN** the effective appearance changes while the trim editor is open
- **THEN** its title bar, window surface, controls, and sheets use one consistent appearance

### Requirement: Content-overlay colors remain stable
Colors used to preserve visibility over captured screens or video content SHALL remain independent of the app appearance when semantic recoloring would reduce visibility or change state meaning.

#### Scenario: Capture selection in Light appearance
- **WHEN** Light appearance is active and the user selects a region or window
- **THEN** selection dimming, outlines, handles, badges, and target highlights retain their fixed-contrast colors

#### Scenario: Timeline overlays in Light appearance
- **WHEN** Light appearance is active and the trim timeline displays video thumbnails
- **THEN** trim handles, excluded-range dimming, keyframe ticks, and the playhead retain their content-overlay colors

#### Scenario: Recording state indicator
- **WHEN** any appearance is active and the toolbar is visible
- **THEN** the recording action continues to use the red state indicator

### Requirement: Appearance accessibility variants
App-owned glass surfaces SHALL honor Reduce Transparency and Increase Contrast without changing available actions or state meaning.

#### Scenario: Reduce Transparency
- **WHEN** Reduce Transparency is enabled
- **THEN** each glass surface uses an opaque theme-equivalent background with readable foregrounds and the same controls

#### Scenario: Increase Contrast
- **WHEN** Increase Contrast is enabled
- **THEN** the system toolbar material follows the accessibility setting, while scrimmed glass surfaces strengthen their contrast scrim and boundary

#### Scenario: Accessibility settings change while visible
- **WHEN** Reduce Transparency or Increase Contrast changes while an app-owned glass surface is visible
- **THEN** the surface updates in place without closing or recreating its window or panel
