import SwiftUI
import CaptureKit
import SettingsKit

@main
struct RokugaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Rokuga", systemImage: "record.circle") {
            MenuBarContentView()
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

struct MenuBarContentView: View {
    var body: some View {
        Button("recording.toolbar.open") {
            // Toolbar panel arrives in task 4.2.
        }
        .keyboardShortcut("6", modifiers: [.shift, .command])

        Divider()

        Button("menu.settings") {
            // Settings window arrives in task 9.3.
        }
        .keyboardShortcut(",", modifiers: .command)
        .disabled(true)

        Divider()

        Button("menu.quit") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
