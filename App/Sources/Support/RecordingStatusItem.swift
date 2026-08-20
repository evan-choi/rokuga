import AppKit
import Combine

/// Menu-bar presence while recording: a stop icon with a live elapsed-time readout.
/// A single click stops the recording immediately — this must be an `NSStatusItem`
/// because the SwiftUI `MenuBarExtra` can only open a menu on click.
@MainActor
final class RecordingStatusItemController {
    private weak var appState: AppState?
    private var statusItem: NSStatusItem?
    private var cancellables: Set<AnyCancellable> = []

    init(appState: AppState) {
        self.appState = appState
        appState.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        refresh()
    }

    private func refresh() {
        guard let appState else { return }
        if appState.recordingState.isActive {
            if statusItem == nil {
                statusItem = makeItem()
            }
            update(with: appState)
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private func makeItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "stop.circle.fill",
                accessibilityDescription: L10n.string("Stop Recording")
            )
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            button.target = self
            button.action = #selector(stopClicked)
        }
        return item
    }

    private func update(with appState: AppState) {
        guard let button = statusItem?.button else { return }
        button.title = " \(appState.elapsedLabel)"
        button.isEnabled = appState.recordingState == .recording
    }

    @objc private func stopClicked() {
        appState?.stopRecording()
    }
}
