import AppKit
import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            ShortcutsPane()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .frame(width: 420)
    }
}

struct ShortcutsPane: View {
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Open Recording Toolbar", name: .summonToolbar)
            KeyboardShortcuts.Recorder("Start / Stop Recording", name: .toggleRecording)
            KeyboardShortcuts.Recorder("Pause / Resume", name: .pauseResume)
        }
        .padding(20)
    }
}

@MainActor
enum SettingsOpener {
    static func open() {
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}
