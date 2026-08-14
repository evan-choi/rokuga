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
    @Published var selectedWindowTarget: WindowTarget?

    let settings = SettingsStore.shared
    let coordinator: RecordingCoordinator

    private let targetBox = PendingTargetBox()
    private let diskMonitor = DiskSpaceMonitor()
    private var elapsedTimer: Timer?
    private var recordingStartedAt: Date?
    private var accumulatedSeconds: Int = 0

    var toolbarController: ToolbarPanelController?
    private var countdownController: CountdownOverlayController?
    private var regionController: RegionSelectionController?
    private var thumbnailController: ThumbnailPanelController?
    private var previewController: PreviewPanelController?

    init() {
        let box = targetBox
        coordinator = RecordingCoordinator { _ in
            guard let plan = box.take() else { throw RecordingError.captureSourceLost }
            return plan.makeSession()
        }
        if let path = settings.lastRecordingPath {
            lastRecordingURL = URL(fileURLWithPath: path)
        }
        Hotkeys.bind(to: self)
        Task { await consumeEvents() }
        Task { @MainActor in summonToolbar() }
    }

    func toggleRecording() {
        if recordingState.isActive {
            stopRecording()
        } else if recordingState.canStart {
            requestRecord()
        }
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
                diskMonitor.stop()
                presentPostRecording(for: url)
            case .failed:
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
            startElapsedTimer()
        case .paused:
            stopElapsedTimer(freeze: true)
        case .idle, .finishing:
            countdownController?.dismiss()
            countdownController = nil
            stopElapsedTimer(freeze: false)
        case .preparing, .countdown:
            break
        }
    }

    // MARK: Toolbar

    func summonToolbar() {
        if toolbarController == nil {
            toolbarController = ToolbarPanelController(appState: self)
        }
        toolbarController?.showAtMouseDisplay()
    }

    func dismissToolbar() {
        toolbarController?.hide()
    }

    // MARK: Record flow

    func requestRecord() {
        guard recordingState.canStart else { return }
        let mode = settings.recordingMode
        switch mode {
        case .fullScreen:
            startRecording(target: .display(displayUnderMouse(), crop: nil))
        case .selectedArea:
            presentRegionSelection()
        case .window:
            if let window = selectedWindowTarget {
                startRecording(target: .window(window))
            } else {
                summonToolbar()
            }
        }
    }

    private func presentRegionSelection() {
        dismissToolbar()
        let display = displayUnderMouse()
        regionController = RegionSelectionController(display: display, settings: settings) { [weak self] crop in
            self?.regionController = nil
            guard let self, let crop else {
                self?.summonToolbar()
                return
            }
            self.startRecording(target: .display(display, crop: crop))
        }
        regionController?.present()
    }

    func startRecording(target: CaptureTarget) {
        dismissToolbar()
        let outputURL = OutputFolderStore.newRecordingURL(settings: settings)
        let encoderConfiguration = makeEncoderConfiguration(for: target)
        let captureConfiguration = CaptureConfiguration.fromSettings(settings)
        let coordinator = self.coordinator

        targetBox.fill(
            SessionPlan {
                let sink = AssetWriterSink(outputURL: outputURL, configuration: encoderConfiguration)
                return SCCaptureSession(
                    target: target,
                    configuration: captureConfiguration,
                    sink: sink
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

    func pauseOrResume() {
        Task {
            if recordingState == .recording {
                try? await coordinator.pause()
            } else if recordingState == .paused {
                try? await coordinator.resume()
            }
        }
    }

    func stopRecording() {
        Task { try? await coordinator.stop() }
    }

    func cancelCountdown() {
        Task { await coordinator.cancel() }
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
        // Trim editor window lands in group 8; interim: hand off to the system player.
        NSWorkspace.shared.open(url)
    }

    func recordingWasDeleted(_ url: URL) {
        if lastRecordingURL == url {
            lastRecordingURL = nil
            settings.lastRecordingPath = nil
        }
    }

    func thumbnailDidClose(_ controller: ThumbnailPanelController) {
        if thumbnailController === controller { thumbnailController = nil }
    }

    func previewDidClose(_ controller: PreviewPanelController) {
        if previewController === controller { previewController = nil }
    }

    private func startDiskWatch(outputURL: URL) {
        let coordinator = self.coordinator
        diskMonitor.start(outputFolder: outputURL.deletingLastPathComponent()) { _ in
            Task { try? await coordinator.stop() }
        }
    }

    // MARK: Helpers

    private func makeEncoderConfiguration(for target: CaptureTarget) -> EncoderConfiguration {
        let size = target.sourcePixelSize
        return EncoderConfiguration.fromSettings(settings, sourceWidth: size.width, sourceHeight: size.height)
    }

    func displayUnderMouse() -> DisplayTarget {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        return displayTarget(for: screen)
    }

    private func displayFor(_ target: CaptureTarget) -> DisplayTarget {
        if case let .display(display, _) = target { return display }
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
                guard let self, let startedAt = self.recordingStartedAt else { return }
                self.elapsedSeconds = self.accumulatedSeconds + Int(Date().timeIntervalSince(startedAt))
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
