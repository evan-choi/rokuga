## 1. Settings and UI

- [x] 1.1 Add the typed VFR/CFR preference with a VFR default, persistence, reset behavior, and encoder-configuration snapshot
- [x] 1.2 Add the Output-pane frame-rate-mode selector and complete English, Korean, Japanese, and Simplified Chinese catalog entries

## 2. Encoder timing

- [x] 2.1 Preserve adjusted ScreenCaptureKit presentation timestamps without idle-frame synthesis in VFR mode
- [x] 2.2 Emit the latest complete frame at fixed selected-FPS intervals in CFR mode and clean up cadence state across pause, finish, and cancel
- [x] 2.3 Keep CFR frame reuse on the zero-copy path and retain encoder drop accounting

## 3. Verification

- [x] 3.1 Cover preference defaults, round trips, and reset behavior with SettingsKit tests
- [x] 3.2 Cover VFR sparse output, CFR static-frame synthesis, fixed cadence, and CFR audio duration with EncoderKit integration tests
- [x] 3.3 Run core tests, app build, localization completeness, zero-copy audit, and diff checks
