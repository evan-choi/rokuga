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
                .appLocale()
        } label: {
            Image(systemName: "record.circle")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .appLocale()
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
        #if ROKUGA_PERF
            if ToolbarLatencyRunner.runIfRequested() {
                return
            }
        #endif
        if DarkAppearanceVerificationRunner.runIfRequested() {
            return
        }
        if DarkRenderingVerificationRunner.runIfRequested() {
            return
        }
        recordingStatusItem = RecordingStatusItemController(appState: .shared)
        _ = L10nScreenshotRunner.runIfRequested()
    }

    /// Quit-while-recording guard (task 5.2): confirm, then finalize safely before terminating.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let appState = AppState.shared
        guard appState.recordingState.isActive else { return .terminateNow }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L10n.string("Stop recording and quit?")
        alert.informativeText = L10n.string("The current recording will be saved before Rokuga quits.")
        alert.addButton(withTitle: L10n.string("Save & Quit"))
        alert.addButton(withTitle: L10n.string("Cancel"))

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

struct SettingsMenuItem: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .keyboardShortcut(",", modifiers: .command)
    }
}

enum L10n {
    private static let supportedLanguageCodes = AppLanguage.allCases.compactMap(\.languageCode)

    static func locale(for language: AppLanguage) -> Locale {
        Locale(identifier: languageCode(for: language))
    }

    static func string(_ key: String) -> String {
        let code = languageCode(for: SettingsStore.shared.appLanguage)
        guard code != "en",
              let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    private static func languageCode(for language: AppLanguage) -> String {
        if let code = language.languageCode {
            return code
        }
        let systemLanguages = UserDefaults.standard
            .persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String]
        return Bundle.preferredLocalizations(
            from: supportedLanguageCodes,
            forPreferences: systemLanguages ?? Locale.preferredLanguages
        ).first ?? "en"
    }
}

private struct AppLocaleModifier: ViewModifier {
    @AppStorage(SettingsStore.Key.appLanguage.rawValue) private var languageRaw = AppLanguage.system.rawValue

    func body(content: Content) -> some View {
        content.environment(
            \.locale,
            L10n.locale(for: AppLanguage(rawValue: languageRaw) ?? .system)
        )
    }
}

extension View {
    func appLocale() -> some View {
        modifier(AppLocaleModifier())
    }
}

#if ROKUGA_PERF
    @MainActor
    private enum ToolbarLatencyRunner {
        private static let repetitions = 5

        static func runIfRequested() -> Bool {
            guard CommandLine.arguments.contains("--perf-toolbar-latency") else { return false }
            Task { await run() }
            return true
        }

        private static func run() async {
            let appState = AppState.shared
            var seconds: [Double] = []

            for _ in 0 ..< repetitions {
                appState.dismissToolbar()
                await nextMainQueueTurn()

                let started = DispatchTime.now().uptimeNanoseconds
                appState.summonToolbar()
                await nextMainQueueTurn()
                guard appState.toolbarController?.isVisible == true else {
                    FileHandle.standardError.write(Data("error: toolbar did not become visible\n".utf8))
                    exit(1)
                }
                seconds.append(Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000)
            }

            appState.dismissToolbar()
            let result = ToolbarLatencyResult(
                command: "toolbar-latency",
                mode: String(describing: appState.settings.recordingMode),
                seconds: seconds
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            do {
                let data = try encoder.encode(result)
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("error: \(error)\n".utf8))
                exit(1)
            }
        }

        private static func nextMainQueueTurn() async {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }

    private struct ToolbarLatencyResult: Encodable {
        let command: String
        let mode: String
        let seconds: [Double]
    }
#endif
