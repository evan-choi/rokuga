import AppKit
import CaptureKit
import SettingsKit
import SwiftUI

@main
struct RokugaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(appState: appState)
        } label: {
            MenuBarLabel(appState: appState)
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
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
            if let url = appState.lastRecordingURL {
                NSWorkspace.shared.open(url)
            }
        }
        .disabled(appState.lastRecordingURL == nil)

        Button("Open Output Folder") {
            NSWorkspace.shared.open(OutputFolderStore.currentFolder())
        }

        Divider()

        Button("Settings…") {
            // Settings window arrives in task 9.3.
        }
        .keyboardShortcut(",", modifiers: .command)
        .disabled(true)

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
