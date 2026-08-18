# Spec: permissions-onboarding

## ADDED Requirements

### Requirement: First-run setup
On first launch, the app SHALL run a short setup flow that: (1) confirms or changes the default output folder (~/Movies/Rokuga), and (2) requests the Screen & System Audio Recording permission with an explanation of why it is needed. The flow MUST be completable in under a minute and MUST NOT be shown again once completed.

#### Scenario: First launch
- **WHEN** the user launches the app for the first time
- **THEN** the setup flow appears, and after completion the app remains available from the menu bar without opening the recording toolbar automatically

#### Scenario: Setup not repeated
- **WHEN** the user relaunches the app after completing setup
- **THEN** the setup flow does not appear and the app remains available from the menu bar

### Requirement: Permission-gated actions
The app MUST check the relevant macOS permission before starting any recording: Screen & System Audio Recording for screen modes, Microphone when mic capture is enabled. If a permission is missing, the app MUST NOT fail silently — it SHALL show a guidance panel explaining which permission is needed and why, with a button that opens the exact System Settings pane.

#### Scenario: Screen permission missing
- **WHEN** the user starts a screen recording without Screen Recording permission
- **THEN** no recording starts; a panel explains the requirement and a button opens System Settings → Privacy & Security → Screen & System Audio Recording

#### Scenario: Microphone permission missing
- **WHEN** mic capture is enabled without Microphone permission
- **THEN** the app requests the permission; if denied, recording can proceed with the mic disabled and the user is clearly informed

#### Scenario: Permission revoked mid-recording
- **WHEN** Screen Recording permission is revoked while a recording is in progress
- **THEN** the footage captured so far is finalized as a playable file (per failure-safe finalization), and the next record attempt shows the permission guidance panel instead of failing silently


### Requirement: Permission state recovery
The app SHALL detect when a previously granted permission has been revoked and degrade gracefully: affected controls show a warning state, and following macOS behavior that requires an app relaunch after granting Screen Recording permission, the app MUST offer a one-click relaunch.

#### Scenario: Revoked while running
- **WHEN** the user revokes Screen Recording permission while the app is running
- **THEN** the next recording attempt shows the guidance panel instead of failing with a generic error

#### Scenario: Relaunch after grant
- **WHEN** the user grants Screen Recording permission from the guidance panel
- **THEN** the app offers "Relaunch Now" and returns to the previous mode after relaunching

### Requirement: Onboarding clarity
All permission prompts and guidance panels MUST state what the permission enables in user terms, and MUST NOT request permissions before they are relevant (the microphone permission is requested only when mic capture is first enabled).

#### Scenario: Deferred microphone request
- **WHEN** the user completes first-run setup without enabling the microphone
- **THEN** no Microphone permission prompt has been shown
