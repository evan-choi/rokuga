import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let summonToolbar = Self("summonToolbar", default: .init(.six, modifiers: [.command, .shift]))
}

@MainActor
enum Hotkeys {
    static func bind(to appState: AppState) {
        KeyboardShortcuts.onKeyUp(for: .summonToolbar) { [weak appState] in
            appState?.summonToolbar()
        }
    }
}
