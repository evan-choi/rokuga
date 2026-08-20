import CaptureKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let summonToolbar = Self("summonToolbar", initial: .init(.six, modifiers: [.command, .shift]))
    static let cancelPendingCapture = Self("cancelPendingCapture", initial: .init(.escape))
    static let stopRecording = Self("stopRecording", initial: .init(.escape, modifiers: [.command, .control]))
}

@MainActor
enum Hotkeys {
    private static var activeLifecycleShortcut: KeyboardShortcuts.Name?

    static func bind(to appState: AppState) {
        KeyboardShortcuts.onKeyUp(for: .summonToolbar) { [weak appState] in
            appState?.summonToolbar()
        }
        KeyboardShortcuts.onKeyDown(for: .cancelPendingCapture) { [weak appState] in
            appState?.cancelCountdown()
        }
        KeyboardShortcuts.onKeyDown(for: .stopRecording) { [weak appState] in
            appState?.stopRecording()
        }
        KeyboardShortcuts.disable(.cancelPendingCapture, .stopRecording)
    }

    static func update(for state: RecordingState) {
        let nextShortcut: KeyboardShortcuts.Name? = switch state {
        case .preparing, .countdown: .cancelPendingCapture
        case .recording, .paused: .stopRecording
        case .idle, .finishing: nil
        }
        guard nextShortcut != activeLifecycleShortcut else { return }

        if let activeLifecycleShortcut {
            KeyboardShortcuts.disable(activeLifecycleShortcut)
        }
        if let nextShortcut {
            KeyboardShortcuts.enable(nextShortcut)
        }
        activeLifecycleShortcut = nextShortcut
    }
}
