# QA Matrix (task 10.5)

## Automated coverage

| Axis | Covered by | Status |
| --- | --- | --- |
| macOS 15 (arm64) | CI `test` job (`macos-15`) | ✅ every push/PR |
| Unit + integration suites | `swift test` (51 tests: capture, encoder, audio output, splice clock, mixer, rate control, settings, trim) | ✅ CI |
| Performance measurements | `RokugaPerf` + `scripts/perf.sh` | Local, on demand |
| Zero-copy record path | `scripts/audit-zero-copy.sh` + xctrace recipe | Local, on demand |
| Localization (ko/ja/zh-Hans) | `scripts/lint-localization.py` + `scripts/l10n-screenshots.sh` | ✅ CI / artifacts |
| Accessibility fallbacks | Reduce Transparency (`GlassBackground`), Reduce Motion paths, VoiceOver labels | ✅ code-level |
| Fixed Dark inheritance | Debug app `--verify-dark-appearance` | Pass on macOS 26.5.2 |
| Dark glass contrast and accessibility palette | Debug app `--verify-dark-rendering` | Pass on macOS 26.5.2; text ≥ 4.5:1 and controls ≥ 3:1 |

The glass verifier composites the app's explicit sRGB scrim tokens and AppKit-resolved
semantic label, selection, and control colors over `#FFFFFF`, `#000000`, and
`#0066FF`. It checks normal text against 4.5:1, graphical controls against
3:1, opaque Reduce Transparency surfaces, and the stronger Increase Contrast
scrim.

The localized screenshot harness renders toolbar, popover, settings, and editor
surfaces under the fixed Dark appearance. Live-window QA still verifies native
lensing below the scrim because off-screen view caching omits the system glass
material.

## Manual hardware passes (release checklist)

Hosted runners do not cover Intel or multi-display configurations, so these run
on physical hardware before each tagged release. Record results in the release PR.

| # | Configuration | What to verify | Result |
| --- | --- | --- | --- |
| 1 | macOS 15, Apple Silicon, 1 display | Selected Area, Full Screen, and Window recording with system audio; trim and export | ☐ |
| 2 | macOS 15, Intel, 1 display | Same + HEVC/H.264 hardware encode | ☐ |
| 3 | macOS 15, Intel, 2 displays (mixed scale) | Region selection per display, loupe accuracy, toolbar summon on mouse display | ☐ |
| 4 | macOS 15, Apple Silicon, 3 displays (1× + 2×) | Display unplug mid-recording, native cursor and click capture | ☐ |
| 5 | Any, VoiceOver enabled | Toolbar → record → stop → preview → trim editor fully by keyboard/VO | ☐ |
| 6 | Any, Reduce Transparency + Reduce Motion | Solid panel fallbacks, no animated transitions | ☐ |
| 7 | Any, 8 h soak (`./scripts/perf.sh record --scenario 4k-audio --seconds 28800 --warmup off`) | Memory ≤ 400 MB steady, zero drops | ☐ |
| 8 | macOS 15–25, system Light and Dark | Rokuga remains Dark; `NSVisualEffectView` stays active beneath the explicit scrim over white, black, and high-chroma content; rounded boundaries remain visible; Reduce Transparency uses the solid Dark palette | Pending |
| 9 | macOS 26+, system Light and Dark | Rokuga remains Dark; untinted native Liquid Glass stays visibly active beneath the explicit scrim; controls remain legible over white and black content | Pending |
