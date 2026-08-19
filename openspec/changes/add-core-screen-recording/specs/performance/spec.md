# Spec: performance

## ADDED Requirements

### Requirement: Resource-efficient frame transport
The default capture-to-encoder path SHALL reuse IOSurface-backed pixel buffers from ScreenCaptureKit through the optional compositor and VideoToolbox hardware encoding. Software video encoding MUST NOT exist in the recording path.

A candidate MAY add a buffer copy or CPU readback only when it preserves the same resolution, cadence, codec, effect fidelity, and file integrity, and warm-up plus at least five untraced runs show a median CPU or memory improvement of 3% or more. Drop rate, A/V drift, latency, memory growth, and the other resource MUST NOT regress. The accepted benchmark comparison SHALL remain in the performance artifacts.

#### Scenario: Hardware encode only
- **WHEN** any recording runs on any supported Mac
- **THEN** video encoding uses the hardware encoder (VideoToolbox), never a software fallback

#### Scenario: Default path avoids copies
- **WHEN** no measured exception has been accepted
- **THEN** captured surfaces reach the compositor and encoder without full-frame CPU readback

#### Scenario: Copy candidate lowers total resource use
- **WHEN** a candidate introduces a buffer copy or CPU readback
- **THEN** it is accepted only with a preserved output contract, at least 3% median CPU or memory improvement over five untraced runs, and no regression in the other required metrics

### Requirement: Frame integrity
Recordings SHALL be lag-free: at the configured FPS, dropped or duplicated frames MUST stay below 0.1% over any 10-minute window on Apple Silicon baseline hardware (M1, 8 GB) at up to 4K60, and A/V drift MUST stay below 40 ms over one hour. If the encoder cannot keep up, the app SHALL degrade mouse-effect quality first (per design D4) and only then lower capture rate — never freeze, stutter, or silently corrupt the file.

A/V drift is the change in relative offset between synchronized audio and visual content markers over the measured interval. Track start/end or duration differences SHALL be reported separately as endpoint skew and MUST NOT be labeled as clock drift.

#### Scenario: Sustained 4K60
- **WHEN** a 10-minute 4K60 recording runs on baseline hardware
- **THEN** dropped/duplicated frames are below 0.1% and audio stays in sync (< 40 ms drift)

#### Scenario: Overload degradation order
- **WHEN** sustained encoder back-pressure is detected
- **THEN** effect quality degrades first, capture FPS second, and the recording continues without a gap; the applied degradation is reported after the recording ends

### Requirement: System responsiveness during recording
Recording MUST NOT lag the machine: the app SHALL never block the ScreenCaptureKit delivery thread or the main thread with synchronous work, and total CPU overhead of the app during a 1080p60 screen recording SHALL stay ≤ 20% of one core on baseline hardware (≤ 35% at 4K60). Memory SHALL stay bounded (steady-state ≤ 400 MB during recording, independent of duration), and disk writes SHALL stream incrementally — no growing in-memory buffer.

#### Scenario: Foreground app unaffected
- **WHEN** the user records a 60 FPS game or scrolls rapidly during capture
- **THEN** the recorded app's own frame rate and input latency show no measurable degradation caused by the recorder

#### Scenario: 8-hour recording
- **WHEN** a recording runs for 8 hours
- **THEN** memory usage remains at steady state (no growth trend) and the file finalizes normally

### Requirement: Interaction latency
UI interactions SHALL feel instant: toolbar summon → visible in ≤ 150 ms; record click → first captured frame in ≤ 500 ms (excluding countdown); stop → playable file in ≤ 2 s for recordings up to 1 hour; trim editor scrubbing SHALL track the pointer at display refresh rate; passthrough trim export of any length SHALL complete in ≤ 3 s.

#### Scenario: Instant start
- **WHEN** the user clicks record with countdown disabled
- **THEN** capture begins within 500 ms and the first frame of the file corresponds to the screen at click time

#### Scenario: Fast finalize
- **WHEN** the user stops a 1-hour recording
- **THEN** the finalized playable file is ready within 2 seconds

### Requirement: Performance regression gates
The performance budgets above SHALL be enforced by automated benchmarks in CI (capture smoke + encode throughput + memory watermark), failing the build when a budget regresses by more than 10%.

#### Scenario: Regression blocks merge
- **WHEN** a change pushes 4K60 dropped frames above budget on the benchmark runner
- **THEN** CI fails with a report naming the regressed metric
