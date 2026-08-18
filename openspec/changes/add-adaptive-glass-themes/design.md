## Context

The app previously persisted an Auto, Light, or Dark selection and applied it through `ThemeApplier`. Native glass still reacts to desktop content, so a stored Light appearance could leave dark-backdrop toolbar controls without enough contrast. Rokuga supports macOS 13.3 and later, with `glassEffect` on macOS 26 and `NSVisualEffectView` on earlier supported releases.

## Goals / Non-Goals

**Goals:**

- Render every app-owned window and panel in Dark Aqua from launch.
- Keep toolbar and preview controls readable over white, black, and high-chroma screen content.
- Honor Reduce Transparency and Increase Contrast.
- Remove theme selection, persistence, switching, and Light-only verification paths.

**Non-Goals:**

- Sampling desktop pixels to choose colors or opacity.
- Recoloring video content or fixed-contrast capture overlays.
- Theming macOS-owned menus or recording indicators beyond normal Dark Aqua inheritance.

## Decisions

### Fix the application appearance at launch

Set `NSApp.appearance` to `.darkAqua` in `applicationWillFinishLaunching`, before status items or app windows are created. App-owned windows, panels, and hosting views leave local appearance overrides unset and inherit that single value. There is no stored theme, picker, or runtime theme observer.

### Use one Dark glass palette

`GlassBackground` uses a `#1E1E23` scrim at 0.70 opacity and a white border at 0.14 opacity. Increase Contrast raises these to 0.84 and 0.26. Reduce Transparency replaces native material and scrim compositing with the opaque Dark tint. The shared `captureWindowChrome` modifier applies this contract to the toolbar, tooltip, preview, and trim editor; shared constants keep the panel and tooltip radii consistent.

Native material remains below the scrim: `.glassEffect(.regular)` on macOS 26 and clipped `NSVisualEffectView` on macOS 13.3–15. The explicit scrim, not material tint behavior, provides the contrast floor over arbitrary content. Rounded hosting layers remain clipped to their visible bounds with native window shadows disabled, including the smaller tooltip panel. The trim editor uses the same material and scrim with square window corners.

### Resolve app chrome under Dark Aqua

App chrome continues to use semantic label, selection, separator, and control colors, but they always resolve under Dark Aqua. Capture selection colors, timeline overlays, and the red recording indicator remain content-oriented fixed colors.

### Keep accessibility adaptations

Increase Contrast strengthens the fixed Dark scrim and boundary. Reduce Transparency uses the equivalent opaque Dark background. Neither setting changes available controls or recording behavior.

## Risks / Trade-offs

- [A dark scrim obscures too much native material] → Keep normal opacity at 0.70 and verify backdrop contribution manually.
- [Material output differs across macOS releases] → Keep the contrast scrim independent of the renderer and test both implementations.
- [A transparent panel exposes rectangular backing or a black tooltip outline] → Clip the hosting layer to the shared radius and disable the window shadow.

## Migration Plan

Remove the Theme model, settings accessor, picker, and theme-specific tests. Existing `app.theme` defaults are ignored; no data migration is needed. Replace Light/Dark switching checks with fixed-Dark appearance and rendering checks.
