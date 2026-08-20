import AppKit
import Combine
import ServiceManagement
import SettingsKit

/// Observable façade over `SettingsStore` so panes get immediate-apply bindings (task 9.3).
@MainActor
final class SettingsModel: ObservableObject {
    private let store = SettingsStore.shared

    var appLanguage: AppLanguage {
        get { store.appLanguage }
        set {
            guard newValue != store.appLanguage else { return }
            objectWillChange.send()
            store.appLanguage = newValue
        }
    }

    var launchAtLogin: Bool {
        get { store.launchAtLogin }
        set {
            objectWillChange.send()
            store.launchAtLogin = newValue
            LaunchAtLogin.set(enabled: newValue)
        }
    }

    var showFloatingThumbnail: Bool {
        get { store.showFloatingThumbnail }
        set { update { $0.showFloatingThumbnail = newValue } }
    }

    var countdown: CountdownDuration {
        get { store.countdown }
        set { update { $0.countdown = newValue } }
    }

    var recordingMode: RecordingMode {
        get { store.recordingMode }
        set { update { $0.recordingMode = newValue } }
    }

    var excludeDesktopIcons: Bool {
        get { store.excludeDesktopIcons }
        set { update { $0.excludeDesktopIcons = newValue } }
    }

    var captureSystemAudio: Bool {
        get { store.captureSystemAudio }
        set { update { $0.captureSystemAudio = newValue } }
    }

    var captureMicrophone: Bool {
        get { store.captureMicrophone }
        set { update { $0.captureMicrophone = newValue } }
    }

    var audioBitrate: AudioBitrate {
        get { store.audioBitrate }
        set { update { $0.audioBitrate = newValue } }
    }

    var audioTrackLayout: AudioTrackLayout {
        get { store.audioTrackLayout }
        set { update { $0.audioTrackLayout = newValue } }
    }

    var showCursor: Bool {
        get { store.showCursor }
        set { update { $0.showCursor = newValue } }
    }

    var animateClicks: Bool {
        get { store.animateClicks }
        set { update { $0.animateClicks = newValue } }
    }

    var videoCodec: VideoCodec {
        get { store.videoCodec }
        set { update { $0.videoCodec = newValue } }
    }

    var containerFormat: ContainerFormat {
        get { store.containerFormat }
        set { update { $0.containerFormat = newValue } }
    }

    var frameRate: FrameRate {
        get { store.frameRate }
        set { update { $0.frameRate = newValue } }
    }

    var frameRateMode: FrameRateMode {
        get { store.frameRateMode }
        set { update { $0.frameRateMode = newValue } }
    }

    var videoQuality: Int {
        get { store.videoQuality }
        set { update { $0.videoQuality = newValue } }
    }

    var outputFolderPath: String {
        OutputFolderStore.displayPath()
    }

    func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = OutputFolderStore.currentFolder()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        objectWillChange.send()
        OutputFolderStore.setFolder(url)
    }

    /// Reset All (task 9.4): preferences only — recordings on disk are never touched.
    func resetAll() {
        let alert = NSAlert()
        alert.messageText = L10n.string("Reset all settings?")
        alert.informativeText = L10n.string("Preferences return to their defaults. Your recordings are not affected.")
        alert.addButton(withTitle: L10n.string("Reset"))
        alert.addButton(withTitle: L10n.string("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        objectWillChange.send()
        store.resetAll()
        LaunchAtLogin.set(enabled: store.launchAtLogin)
    }

    private func update(_ mutate: (SettingsStore) -> Void) {
        objectWillChange.send()
        mutate(store)
    }
}

enum LaunchAtLogin {
    static func set(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("SMAppService failed: %@", error.localizedDescription)
        }
    }
}
