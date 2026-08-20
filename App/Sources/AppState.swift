import AppKit
import CaptureKit
import Combine
import EncoderKit
import SettingsKit
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published private(set) var recordingState: RecordingState = .idle
    @Published private(set) var elapsedSeconds: Int = 0
    @Published private(set) var lastRecordingURL: URL?

    let settings = SettingsStore.shared
    let coordinator: RecordingCoordinator

    private let targetBox = PendingTargetBox()
    private let diskMonitor = DiskSpaceMonitor()
    private var elapsedTimer: Timer?
    private var recordingStartedAt: Date?
    private var accumulatedSeconds: Int = 0

    var toolbarController: ToolbarPanelController?
    private var countdownController: CountdownOverlayController?
    private var areaController: RegionSelectionController?
    private var windowHoverController: WindowHoverController?
    private var displaySelectController: DisplaySelectController?
    private var punchController: PunchOverlayController?
    private var thumbnailController: ThumbnailPanelController?
    private var previewController: PreviewPanelController?
    private var trimEditors: [TrimEditorController] = []
    private(set) var activeRecordingURL: URL?

    init() {
        let box = targetBox
        coordinator = RecordingCoordinator { _ in
            guard let plan = box.take() else { throw RecordingError.captureSourceLost }
            return plan.makeSession()
        }
        #if ROKUGA_PERF
            if CommandLine.arguments.contains("--perf-toolbar-latency") {
                return
            }
        #endif
        if let path = settings.lastRecordingPath {
            lastRecordingURL = URL(fileURLWithPath: path)
        }
        Hotkeys.bind(to: self)
        Task { await consumeEvents() }
        Task { @MainActor in
            let missing = await OnboardingModel.missingSteps(settings: settings)
            if missing.isEmpty {
                settings.onboardingCompleted = true
            } else {
                presentOnboarding(steps: missing)
            }
        }
    }

    private var onboardingController: OnboardingController?

    private func presentOnboarding(steps: [OnboardingModel.Step]) {
        onboardingController = OnboardingController(steps: steps) { [weak self] in
            self?.onboardingController = nil
        }
        onboardingController?.present()
    }

    /// Deleted-file recovery (task 7.4): a stale last-recording entry falls back to the output folder.
    func openLastRecording() {
        guard let url = lastRecordingURL, FileManager.default.fileExists(atPath: url.path) else {
            lastRecordingURL = nil
            settings.lastRecordingPath = nil
            NSWorkspace.shared.open(OutputFolderStore.currentFolder())
            return
        }
        NSWorkspace.shared.open(url)
    }

    // MARK: Event pump

    private func consumeEvents() async {
        for await event in await coordinator.events() {
            switch event {
            case let .stateChanged(state):
                applyState(state)
            case let .countdownTick(remaining):
                countdownController?.update(remaining: remaining)
            case let .finished(url):
                lastRecordingURL = url
                settings.lastRecordingPath = url.path
                activeRecordingURL = nil
                diskMonitor.stop()
                presentPostRecording(for: url)
            case .failed:
                activeRecordingURL = nil
                diskMonitor.stop()
            }
        }
    }

    private func applyState(_ state: RecordingState) {
        recordingState = state
        switch state {
        case .recording:
            countdownController?.dismiss()
            countdownController = nil
            onboardingController?.completeSilently()
            onboardingController = nil
            startElapsedTimer()
        case .idle, .finishing:
            countdownController?.dismiss()
            countdownController = nil
            punchController?.close()
            punchController = nil
            stopElapsedTimer(freeze: false)
        case .preparing, .countdown, .paused:
            // Pause is not surfaced in the UI; the state remains only as a core capability.
            break
        }
        Hotkeys.update(for: state, toolbarVisible: toolbarController?.isVisible == true)
    }

    // MARK: Toolbar

    func summonToolbar() {
        // The final onboarding page asks the user to press this very shortcut, so acting on
        // it completes onboarding; earlier pages stay up (permission setup may be unfinished).
        if let onboarding = onboardingController, onboarding.isShowingGetStarted {
            onboarding.completeSilently()
            onboardingController = nil
        }
        guard !recordingState.isActive else { return }
        if toolbarController == nil {
            toolbarController = ToolbarPanelController(appState: self)
        }
        toolbarController?.showAtMouseDisplay()
        refreshSelectionLayer()
        Hotkeys.update(for: recordingState, toolbarVisible: toolbarController?.isVisible == true)
    }

    func dismissToolbar() {
        toolbarController?.hide()
        teardownSelectionLayer()
        Hotkeys.update(for: recordingState, toolbarVisible: false)
    }

    func selectionModeChanged() {
        refreshSelectionLayer()
    }

    func refreshSelectionCursor() {
        windowHoverController?.refreshCursor()
        displaySelectController?.refreshCursor()
    }

    private func refreshSelectionLayer() {
        teardownSelectionLayer()
        guard toolbarController?.isVisible == true else { return }
        switch settings.recordingMode {
        case .selectedArea:
            let controller = RegionSelectionController(
                display: displayUnderMouse(),
                settings: settings,
                onRecordRequested: { [weak self] in self?.requestRecord() },
                onCancel: { [weak self] in self?.dismissToolbar() }
            )
            areaController = controller
            controller.present()
        case .window:
            let controller = WindowHoverController { [weak self] target in
                self?.recordAfterPreflight(target: .window(target))
            }
            windowHoverController = controller
            controller.present()
        case .fullScreen:
            let controller = DisplaySelectController { [weak self] display in
                self?.recordAfterPreflight(target: .display(display, crop: nil))
            }
            displaySelectController = controller
            controller.present()
        }
    }

    private func teardownSelectionLayer() {
        areaController?.close()
        areaController = nil
        windowHoverController?.close()
        windowHoverController = nil
        displaySelectController?.close()
        displaySelectController = nil
    }

    // MARK: Record flow

    func requestRecord() {
        guard recordingState.canStart else { return }
        Task { @MainActor in
            guard let capturesMicrophone = await preflightPermissions() else { return }
            proceedWithRecordFlow(capturesMicrophone: capturesMicrophone)
        }
    }

    /// Per-attempt permission re-check (task 9.2): screen permission is probed every time;
    /// mic permission is requested just-in-time only when mic capture is enabled.
    /// Returns the recording-scoped mic state, or `nil` when recording should not start.
    private func preflightPermissions() async -> Bool? {
        guard await ShareableContentService.hasScreenRecordingPermission() else {
            presentScreenPermissionRecovery()
            return nil
        }
        if settings.captureMicrophone {
            let granted = await MicrophoneCapture.requestPermission()
            if !granted {
                return presentMicDeniedChoice() ? false : nil
            }
            return true
        }
        return false
    }

    private func presentScreenPermissionRecovery() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L10n.string("Screen recording permission required")
        alert.informativeText = L10n.string("Allow Rokuga in System Settings › Privacy & Security › Screen Recording, then relaunch.")
        alert.addButton(withTitle: L10n.string("Open System Settings…"))
        alert.addButton(withTitle: L10n.string("Cancel"))
        if alert.runModal() == .alertFirstButtonReturn {
            PermissionLinks.openScreenRecording()
        }
    }

    /// Returns true when the user chooses to continue recording without the microphone.
    private func presentMicDeniedChoice() -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L10n.string("Microphone access denied")
        alert.informativeText = L10n.string("Record without the microphone, or grant access in System Settings.")
        alert.addButton(withTitle: L10n.string("Record Without Mic"))
        alert.addButton(withTitle: L10n.string("Open System Settings…"))
        alert.addButton(withTitle: L10n.string("Cancel"))
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return true
        case .alertSecondButtonReturn:
            PermissionLinks.openMicrophone()
            return false
        default:
            return false
        }
    }

    private func proceedWithRecordFlow(capturesMicrophone: Bool) {
        switch settings.recordingMode {
        case .selectedArea:
            let display = areaController?.display ?? displayUnderMouse()
            let region = areaController?.currentRegion
                ?? settings.selectedRegions[String(display.displayID)]?.integral
            if let region {
                startRecording(target: .display(display, crop: region), capturesMicrophone: capturesMicrophone)
            } else {
                summonToolbar()
            }
        case .fullScreen:
            let display = displaySelectController?.hoveredDisplay ?? displayUnderMouse()
            startRecording(target: .display(display, crop: nil), capturesMicrophone: capturesMicrophone)
        case .window:
            if let target = windowHoverController?.hoveredWindow {
                startRecording(target: .window(target), capturesMicrophone: capturesMicrophone)
            } else {
                summonToolbar()
            }
        }
    }

    /// Click-to-record from selection layers (window hover / display select) with the same permission preflight.
    private func recordAfterPreflight(target: CaptureTarget) {
        Task { @MainActor in
            guard let capturesMicrophone = await preflightPermissions() else { return }
            startRecording(target: target, capturesMicrophone: capturesMicrophone)
        }
    }

    func startRecording(target: CaptureTarget, capturesMicrophone: Bool) {
        dismissToolbar()
        if case let .display(display, crop) = target, let crop {
            punchController = PunchOverlayController(display: display, region: crop)
            punchController?.present()
        }
        let outputURL = OutputFolderStore.newRecordingURL(settings: settings)
        activeRecordingURL = outputURL
        let frameRate = settings.frameRate.resolved(displayRefreshRate: target.displayRefreshRate)
        var encoderConfiguration = makeEncoderConfiguration(for: target, frameRate: frameRate)
        encoderConfiguration.capturesMicrophone = capturesMicrophone
        let captureConfiguration = CaptureConfiguration.fromSettings(settings, frameRate: frameRate)
        let coordinator = coordinator

        targetBox.fill(
            SessionPlan {
                let sink = AssetWriterSink(outputURL: outputURL, configuration: encoderConfiguration)
                return SCCaptureSession(
                    target: target,
                    configuration: captureConfiguration,
                    sink: sink,
                    microphoneCapture: capturesMicrophone ? MicrophoneCapture() : nil
                ) { _ in
                    Task { await coordinator.handleSessionInterruption() }
                }
            }
        )

        let countdown = settings.countdown
        if countdown != .off {
            countdownController = CountdownOverlayController(display: displayFor(target)) { [weak self] in
                self?.cancelCountdown()
            }
            countdownController?.present()
        }

        Task {
            do {
                try await coordinator.start(mode: settings.recordingMode, countdown: countdown)
                startDiskWatch(outputURL: outputURL)
            } catch {
                NSSound.beep()
            }
        }
    }

    func stopRecording() {
        Task { try? await coordinator.stop() }
    }

    func cancelCountdown() {
        Task { await coordinator.cancel() }
    }

    func cancelPendingCapture() {
        if toolbarController?.isVisible == true {
            dismissToolbar()
        } else {
            cancelCountdown()
        }
    }

    // MARK: Post-recording flow

    private func presentPostRecording(for url: URL) {
        if settings.showFloatingThumbnail {
            thumbnailController = ThumbnailPanelController(recordingURL: url, appState: self)
            thumbnailController?.present()
        } else {
            NotificationFallback.postRecordingSaved(url: url)
        }
    }

    func presentPreview(for url: URL, expandingFrom frame: NSRect?) {
        previewController = PreviewPanelController(recordingURL: url, expandingFrom: frame, appState: self)
    }

    func presentTrimEditor(for url: URL) {
        guard url != activeRecordingURL else {
            NSSound.beep()
            return
        }
        let editor = TrimEditorController(url: url) { [weak self] in
            self?.trimEditors.removeAll { $0.model.url == url }
        }
        trimEditors.append(editor)
        editor.present()
    }

    func recordingWasDeleted(_ url: URL) {
        if lastRecordingURL == url {
            lastRecordingURL = nil
            settings.lastRecordingPath = nil
        }
    }

    func thumbnailDidClose(_ controller: ThumbnailPanelController) {
        if thumbnailController === controller {
            thumbnailController = nil
        }
    }

    func previewDidClose(_ controller: PreviewPanelController) {
        if previewController === controller {
            previewController = nil
        }
    }

    private func startDiskWatch(outputURL: URL) {
        let coordinator = coordinator
        diskMonitor.start(outputFolder: outputURL.deletingLastPathComponent()) { _ in
            Task { try? await coordinator.stop() }
        }
    }

    // MARK: Helpers

    private func makeEncoderConfiguration(for target: CaptureTarget, frameRate: Int) -> EncoderConfiguration {
        let size = target.sourcePixelSize
        return EncoderConfiguration.fromSettings(
            settings,
            sourceWidth: size.width,
            sourceHeight: size.height,
            frameRate: frameRate
        )
    }

    func displayUnderMouse() -> DisplayTarget {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        return displayTarget(for: screen)
    }

    private func displayFor(_ target: CaptureTarget) -> DisplayTarget {
        if case let .display(display, _) = target {
            return display
        }
        return displayUnderMouse()
    }

    private func displayTarget(for screen: NSScreen?) -> DisplayTarget {
        guard let screen,
              let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        else {
            return DisplayTarget(displayID: CGMainDisplayID(), frame: NSScreen.main?.frame ?? .zero, pixelWidth: 1920, pixelHeight: 1080)
        }
        let mode = CGDisplayCopyDisplayMode(displayID)
        return DisplayTarget(
            displayID: displayID,
            frame: screen.frame,
            pixelWidth: mode?.pixelWidth ?? Int(screen.frame.width),
            pixelHeight: mode?.pixelHeight ?? Int(screen.frame.height)
        )
    }

    // MARK: Elapsed time

    private func startElapsedTimer() {
        recordingStartedAt = Date()
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let startedAt = recordingStartedAt else { return }
                elapsedSeconds = accumulatedSeconds + Int(Date().timeIntervalSince(startedAt))
            }
        }
    }

    private func stopElapsedTimer(freeze: Bool) {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        if freeze {
            accumulatedSeconds = elapsedSeconds
        } else {
            accumulatedSeconds = 0
            elapsedSeconds = 0
        }
        recordingStartedAt = nil
    }

    var elapsedLabel: String {
        String(format: "%d:%02d", elapsedSeconds / 60, elapsedSeconds % 60)
    }
}

/// Bridges the UI-built capture plan into the coordinator's session factory across actor boundaries.
final class PendingTargetBox: @unchecked Sendable {
    private let lock = NSLock()
    private var plan: SessionPlan?

    func fill(_ plan: SessionPlan) {
        lock.withLock { self.plan = plan }
    }

    func take() -> SessionPlan? {
        lock.withLock {
            defer { plan = nil }
            return plan
        }
    }
}

struct SessionPlan: Sendable {
    let makeSession: @Sendable () -> CaptureSession
}
