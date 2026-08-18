# Spec: localization

## ADDED Requirements

### Requirement: Supported languages
The app SHALL ship fully localized in English (base/development language), Korean, Japanese, and Simplified Chinese. Every user-facing string — toolbar, popovers, menus, settings, alerts, notifications, tooltips, onboarding, VoiceOver labels — MUST come from String Catalogs; hardcoded user-facing literals MUST NOT exist (enforced by a CI lint).

#### Scenario: Complete Korean UI
- **WHEN** the app runs in Korean
- **THEN** no English string appears anywhere in the UI, including error alerts and menu bar items

#### Scenario: Missing translation falls back
- **WHEN** a string lacks a translation in the active language
- **THEN** the English base string is shown (never a raw key), and the gap is caught by a CI completeness check before release

### Requirement: Language selection follows the system
The app SHALL use the standard macOS language resolution: the system language list and the per-app language override in System Settings › Language & Region. The app MUST NOT implement its own in-app language picker.

#### Scenario: Per-app override
- **WHEN** the user sets this app to Japanese in System Settings while the system is in English
- **THEN** the app relaunches in Japanese with all surfaces localized

### Requirement: Locale-aware formatting, locale-neutral files
Dates, times, numbers, and file sizes shown in the UI SHALL use system locale formatters. Generated recording file names SHALL remain locale-neutral (`Rokuga 2026-08-15 at 14.22.31.mov`) in every language, so files sort and sync identically across locales. The extension SHALL match the selected container.

#### Scenario: Localized display, stable file name
- **WHEN** a recording finishes on a Japanese-language system
- **THEN** the notification shows a Japanese message with a locale-formatted date, while the file on disk keeps the locale-neutral name pattern

### Requirement: CJK layout integrity
All layouts SHALL accommodate CJK and English text without truncation or overlap: buttons and menu items size to their content, and the toolbar, popover, settings panes, and trim editor MUST render correctly in all four languages (verified per release via localized-screenshot QA).

#### Scenario: No truncation across languages
- **WHEN** the options popover renders in each of the four languages
- **THEN** every label is fully visible with no ellipsis on primary controls and no overlapping elements
