import AppKit
import CaptureKit
import SettingsKit
import SwiftUI

@main
struct RokugaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var appState = AppState.shared

    var body: some Scene {
        // While recording, this SwiftUI item is swapped out for RecordingStatusItemController's
        // plain NSStatusItem so a single click can stop immediately (menus can't do that).
        MenuBarExtra(isInserted: .constant(!appState.recordingState.isActive)) {
            MenuBarContentView(appState: appState)
        } label: {
            Image(systemName: "record.circle")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var recordingStatusItem: RecordingStatusItemController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if DarkAppearanceVerificationRunner.runIfRequested() { return }
        if DarkRenderingVerificationRunner.runIfRequested() { return }
        recordingStatusItem = RecordingStatusItemController(appState: .shared)
        _ = L10nScreenshotRunner.runIfRequested()
    }

    /// Quit-while-recording guard (task 5.2): confirm, then finalize safely before terminating.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let appState = AppState.shared
        guard appState.recordingState.isActive else { return .terminateNow }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = String(localized: "Stop recording and quit?")
        alert.informativeText = String(localized: "The current recording will be saved before Rokuga quits.")
        alert.addButton(withTitle: String(localized: "Save & Quit"))
        alert.addButton(withTitle: String(localized: "Cancel"))

        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }

        Task {
            _ = try? await appState.coordinator.stop()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

struct MenuBarContentView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Button("Open Recording Toolbar") {
            appState.summonToolbar()
        }
        .keyboardShortcut("6", modifiers: [.shift, .command])

        Divider()

        Button("Open Last Recording") {
            appState.openLastRecording()
        }
        .disabled(appState.lastRecordingURL == nil)

        Button("Open Output Folder") {
            NSWorkspace.shared.open(OutputFolderStore.currentFolder())
        }

        Divider()

        SettingsMenuItem()

        Divider()

        Button("Quit Rokuga") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}

/// Menu item that opens the Settings scene.
/// macOS 14+ removed the `showSettingsWindow:` selector path, so the official
/// `openSettings` environment action must be used there.
struct SettingsMenuItem: View {
    var body: some View {
        if #available(macOS 14.0, *) {
            ModernSettingsMenuItem()
        } else {
            Button("Settings…") {
                SettingsOpener.open()
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}

@available(macOS 14.0, *)
private struct ModernSettingsMenuItem: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .keyboardShortcut(",", modifiers: .command)
    }
}
