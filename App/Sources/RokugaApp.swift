import AppKit
import CaptureKit
import SettingsKit
import SwiftUI

@main
struct RokugaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var appState = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(appState: appState)
        } label: {
            MenuBarLabel(appState: appState)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Task { @MainActor in
            ThemeApplier.apply(SettingsStore.shared.theme)
        }
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

struct MenuBarLabel: View {
    @ObservedObject var appState: AppState

    var body: some View {
        if appState.recordingState.isActive {
            HStack(spacing: 4) {
                Image(systemName: appState.recordingState == .paused ? "pause.circle.fill" : "record.circle.fill")
                Text(appState.elapsedLabel)
                    .monospacedDigit()
            }
        } else {
            Image(systemName: "record.circle")
        }
    }
}

struct MenuBarContentView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        if appState.recordingState.isActive {
            recordingMenu
        } else {
            idleMenu
        }
    }

    @ViewBuilder
    private var idleMenu: some View {
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

        Button("Settings…") {
            SettingsOpener.open()
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit Rokuga") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    @ViewBuilder
    private var recordingMenu: some View {
        Text(verbatim: "● \(appState.elapsedLabel)")

        Divider()

        Button(appState.recordingState == .paused ? "Resume Recording" : "Pause Recording") {
            appState.pauseOrResume()
        }
        .keyboardShortcut("4", modifiers: [.shift, .command])

        Button("Stop Recording") {
            appState.stopRecording()
        }
        .keyboardShortcut("2", modifiers: [.shift, .command])
    }
}
