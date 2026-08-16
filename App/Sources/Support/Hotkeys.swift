import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let summonToolbar = Self("summonToolbar", default: .init(.six, modifiers: [.command, .shift]))
    static let toggleRecording = Self("toggleRecording", default: .init(.two, modifiers: [.command, .shift]))
}

@MainActor
enum Hotkeys {
    static func bind(to appState: AppState) {
        KeyboardShortcuts.onKeyUp(for: .summonToolbar) { [weak appState] in
            appState?.summonToolbar()
        }
        KeyboardShortcuts.onKeyUp(for: .toggleRecording) { [weak appState] in
            appState?.toggleRecording()
        }
    }
}
