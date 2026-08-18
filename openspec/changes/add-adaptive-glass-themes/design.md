## Context

`ThemeApplier` already maps the stored Appearance setting to `NSApp.appearance`: Auto clears the override, Light selects Aqua, and Dark selects Dark Aqua. Existing `NSWindow`, `NSPanel`, and `NSHostingView` instances inherit changes to the application appearance.

That propagation is currently masked by local overrides. The toolbar and preview force a dark SwiftUI color scheme, while the trim editor forces dark appearance in both its window controller and root view. Their backgrounds and foregrounds also use fixed dark RGB and white colors. `GlassBackground` uses a dark tint with 0.40 opacity on macOS 26 and 0.55 on earlier systems, which is insufficient over bright screen content.

The app supports macOS 13.3 and later. Glass rendering therefore has two implementations: `glassEffect` on macOS 26 and `NSVisualEffectView` on macOS 13.3–15. Both must produce the same theme behavior and comparable contrast.

## Goals / Non-Goals

**Goals:**

- Make Auto, Light, and Dark apply to app-owned windows and transient panels without relaunching or recreating them.
- Preserve readable toolbar and preview controls over white, black, and high-chroma screen content.
- Use one semantic palette model across the macOS 26 glass and older visual-effect implementations.
- Honor Reduce Transparency and Increase Contrast.
- Keep colors that identify capture state or sit directly over captured content stable across themes.

**Non-Goals:**

- Sampling screen pixels to choose colors or opacity at runtime.
- Theming the macOS menu bar, system menus, alerts, or recording indicators beyond their native appearance behavior.
- Recoloring video content, selection dimming, trim handles, keyframe ticks, or the red recording indicator.
- Adding themes beyond Auto, Light, and Dark.

## Decisions

### Keep `NSApp.appearance` as the appearance source

The existing `ThemeApplier` remains the single mapping from the stored setting to AppKit appearance. App-owned windows and panels must leave their local `appearance` unset, and SwiftUI roots must not force `preferredColorScheme`.

This uses AppKit's existing appearance inheritance and lets SwiftUI derive `colorScheme` from each hosting view. A second observable theme object would duplicate state and require explicit injection into panel roots created outside the SwiftUI scene hierarchy.

The saved appearance will be applied before status items, screenshot views, or app windows are created to avoid a light-to-dark flash at launch. Changing the Appearance picker will continue to call `ThemeApplier` immediately. Auto will continue to follow system appearance changes because `NSApp.appearance` is `nil`.

### Resolve glass colors from the effective appearance

`GlassBackground` will read `colorScheme`, `colorSchemeContrast`, and `accessibilityReduceTransparency`. It will resolve contrast scrim, solid fallback, and border colors from a small internal palette rather than from call-site constants.

Calibrated normal-contrast values are:

| Appearance | Scrim | Scrim opacity | Border |
| --- | --- | ---: | ---: |
| Dark | `#1E1E23` | 0.70 | white at 0.14 |
| Light | `#E8E8EC` | 0.56 | black at 0.12 |

Increase Contrast raises the dark scrim opacity to 0.84, the light scrim opacity to 0.92, and the border opacity into the 0.22–0.26 range. Reduce Transparency replaces the material and scrim with an opaque color derived from the same palette.

The initial implementation used a 0.82 normal tint because active toolbar labels and icons were dimmed to 72–75% and selected/control fills were derived from `primary`. That combination required an almost opaque surface and obscured the native material. Active controls now use the full semantic label color, while selected modes and the Record control use semantic system surfaces. This permits the lower calibrated scrim values above while keeping normal text and graphical controls above their 4.5:1 and 3:1 targets on white, black, and high-chroma QA backgrounds.

The native material and contrast guarantee are separate layers. On macOS 26+, untinted `.glassEffect(.regular)` remains the lower layer; on macOS 13.3–15, the clipped `NSVisualEffectView` is the lower layer. An identically clipped, alpha-composited scrim is rendered above either material. The implementation does not rely on `.glassEffect.tint`, whose material-dependent output does not guarantee the same composite over black content.

The automated verifier uses sRGB scrim compositing because off-screen view caching omits the system glass material. It verifies the conservative contrast floor and backdrop contribution, not live lensing or refraction. Release QA still checks the macOS 26 material and the macOS 13.3–15 fallback in composited windows.

The explicit scrim provides the contrast floor, but it must leave enough backdrop contribution for the system material's lensing and highlights to remain perceptible. Raw system glass alone is not sufficient for a panel that can be placed over arbitrary content. Dynamically sampling the desktop was rejected because it can cause visible color changes as the panel moves and would complicate multi-display rendering.

The recording toolbar is the deliberate exception: it uses raw system material without an app-defined scrim or border so its backdrop effect matches the system capture toolbar. On macOS 26 it uses untinted `.glassEffect(.regular)`; macOS 13.3–15 use the native HUD visual effect. Reduce Transparency replaces either renderer with the system window background. Other glass surfaces keep the explicit contrast treatment above.

Toolbar and preview hosting views will use a transparent layer masked to the same continuous corner radius as the SwiftUI glass shape. Their native window shadow remains disabled. This prevents the rectangular window backing or a stale shadow mask from appearing outside the rounded surface.

### Use semantic colors for app chrome

Toolbar and preview chrome will use `primary`, `secondary`, separator, and appearance-derived fill colors. Selected and inactive controls will use semantic foreground colors with controlled opacity instead of fixed white. The red record indicator remains red because it communicates recording state.

The trim editor window will inherit the application appearance, and its fixed RGB background will become a semantic window surface. The player, timeline dimming, white trim handles, yellow keyframe ticks, and red playhead remain content-overlay colors. These elements must remain visible over video frames and do not represent app theme.

Options popovers, Settings, onboarding, and native dialogs already use semantic or native controls and will inherit the application appearance. Floating-thumbnail image content and its loading placeholder remain content-oriented; only app chrome around that content is eligible for semantic coloring.

### Keep safe appearance changes available while recording

Appearance changes do not affect capture configuration or encoded output. The Appearance picker must remain enabled during recording even when codec, frame-rate, or audio controls are locked.

## Risks / Trade-offs

- [Light glass can disappear over a white window] → Use a neutral gray contrast scrim and a dark semantic border; verify the rendered boundary on a white background.
- [Material output differs across macOS releases] → Keep the contrast scrim independent of the renderer while using one semantic palette and the same contrast targets.
- [Removing dark overrides before replacing fixed white colors creates unreadable light UI] → Land appearance inheritance and semantic color changes in the same implementation step.
- [An open popover or hosted AppKit view may not redraw during a theme switch] → Test existing windows and panels in place; invalidate custom AppKit drawing only where semantic drawing colors are introduced.
- [A stronger scrim reduces the apparent glass effect] → Use full-strength semantic foregrounds and system control surfaces so the contrast floor does not require an opaque-looking normal scrim.
- [A transparent panel exposes its rectangular backing] → Clear and mask the hosting layer to the glass radius, disable the native window shadow, and invalidate its shadow mask.

## Migration Plan

1. Add the adaptive palette and accessibility variants without changing call sites.
2. Remove local appearance overrides and convert toolbar, preview, and editor chrome to semantic colors in the same change.
3. Apply the stored theme before app surfaces are created and leave appearance changes enabled during recording.
4. Update the active core-screen-recording design, app-preferences requirement, and task status to describe adaptive rather than forced-dark surfaces.
5. Run persistence tests, build the app, and complete the appearance and accessibility visual matrix.

No stored-data migration is required. Existing saved `Theme` values remain unchanged; users without a stored value now start in Dark. Rollback consists of reverting the default; saved preferences remain compatible.

## Open Questions

None. Renderer-specific opacity adjustments will be resolved by the defined contrast checks rather than by a new product decision.
