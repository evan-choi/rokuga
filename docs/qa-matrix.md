# QA Matrix (task 10.5)

## Automated coverage

| Axis | Covered by | Status |
| --- | --- | --- |
| macOS 14 / 15 (arm64) | CI `test` job (`macos-14`, `macos-15`) | ✅ every push/PR |
| Unit + integration suites | `swift test` (45 tests: capture, encoder, audio output, splice clock, mixer, rate control, settings, trim, effects) | ✅ CI |
| Performance budgets | `rokuga-bench` + `scripts/bench-gate.py` (PR: 1080p60; nightly: 4K60 10 min) | ✅ CI |
| Zero-copy record path | `scripts/audit-zero-copy.sh` + xctrace recipe | ✅ CI (static) |
| Localization (ko/ja/zh-Hans) | `scripts/lint-localization.py` + `scripts/l10n-screenshots.sh` | ✅ CI / artifacts |
| Accessibility fallbacks | Reduce Transparency (`GlassBackground`), Reduce Motion paths, VoiceOver labels | ✅ code-level |

## Manual hardware passes (release checklist)

GitHub retired hosted macOS 13 and Intel runners, so these run on physical
hardware before each tagged release. Record results in the release PR.

| # | Configuration | What to verify | Result |
| --- | --- | --- | --- |
| 1 | macOS 13.3, Apple Silicon, 1 display | Selected Area, Full Screen, and Window recording with system audio; trim and export | ☐ |
| 2 | macOS 13.3, Intel, 1 display | Same + HEVC/H.264 hardware encode | ☐ |
| 3 | macOS 14, Intel, 2 displays (mixed scale) | Region selection per display, loupe accuracy, toolbar summon on mouse display | ☐ |
| 4 | macOS 15, Apple Silicon, 3 displays (1× + 2×) | Display unplug mid-recording, cursor compositor across scale factors | ☐ |
| 5 | Any, VoiceOver enabled | Toolbar → record → stop → preview → trim editor fully by keyboard/VO | ☐ |
| 6 | Any, Reduce Transparency + Reduce Motion | Solid panel fallbacks, no animated transitions | ☐ |
| 7 | Any, 8 h soak (`rokuga-bench throughput --seconds 28800`) | Memory ≤ 400 MB steady, zero drops | ☐ |
