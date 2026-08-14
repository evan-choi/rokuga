import AppKit
import CaptureKit
import SettingsKit
import SwiftUI

/// First-run flow (task 9.1): output folder → screen-recording permission probe →
/// guided denial recovery with a System Settings deep link.
@MainActor
final class OnboardingController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let model = OnboardingModel()
    private let onComplete: () -> Void

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 400),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.center()
        super.init()
        window.delegate = self
        window.contentView = NSHostingView(
            rootView: OnboardingView(model: model) { [weak self] in
                SettingsStore.shared.onboardingCompleted = true
                self?.window.close()
                self?.onComplete()
            }
        )
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class OnboardingModel: ObservableObject {
    enum Step {
        case welcome
        case outputFolder
        case screenPermission
    }

    @Published var step: Step = .welcome
    @Published var folderPath = OutputFolderStore.currentFolder().path
    @Published var permissionGranted: Bool?
    @Published var probing = false

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = OutputFolderStore.currentFolder()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        OutputFolderStore.setFolder(url)
        folderPath = url.path
    }

    func probePermission() {
        probing = true
        Task { @MainActor in
            permissionGranted = await ShareableContentService.hasScreenRecordingPermission()
            probing = false
        }
    }

    func openScreenRecordingSettings() {
        PermissionLinks.openScreenRecording()
    }
}

@MainActor
enum PermissionLinks {
    static func openScreenRecording() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    static func openMicrophone() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    private static func open(_ string: String) {
        if let url = URL(string: string) {
            NSWorkspace.shared.open(url)
        }
    }
}

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .frame(width: 520, height: 400)
    }

    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .welcome:
            VStack(spacing: 14) {
                Image(systemName: "record.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.red)
                Text("Welcome to Rokuga")
                    .font(.title.bold())
                Text("Free, native screen recording at 60 fps.\nNo watermarks, no time limits.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding(32)
        case .outputFolder:
            VStack(spacing: 14) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                Text("Where should recordings go?")
                    .font(.title2.bold())
                Text(model.folderPath)
                    .font(.system(size: 12, design: .monospaced))
                    .truncationMode(.middle)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                Button("Choose Folder…", action: model.chooseFolder)
            }
            .padding(32)
        case .screenPermission:
            VStack(spacing: 14) {
                Image(systemName: model.permissionGranted == true ? "checkmark.shield.fill" : "shield.lefthalf.filled")
                    .font(.system(size: 48))
                    .foregroundStyle(model.permissionGranted == true ? .green : .orange)
                Text("Screen Recording Permission")
                    .font(.title2.bold())
                permissionBody
            }
            .padding(32)
            .onAppear { model.probePermission() }
        }
    }

    @ViewBuilder
    private var permissionBody: some View {
        switch model.permissionGranted {
        case .some(true):
            Text("Permission granted. You're ready to record.")
                .foregroundStyle(.secondary)
        case .some(false):
            VStack(spacing: 10) {
                Text("macOS requires you to allow screen recording in System Settings, then relaunch Rokuga.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Open System Settings…", action: model.openScreenRecordingSettings)
                Button("Check Again", action: model.probePermission)
            }
        case nil:
            ProgressView()
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            switch model.step {
            case .welcome:
                Button("Continue") { model.step = .outputFolder }
                    .keyboardShortcut(.defaultAction)
            case .outputFolder:
                Button("Continue") { model.step = .screenPermission }
                    .keyboardShortcut(.defaultAction)
            case .screenPermission:
                Button(model.permissionGranted == true ? "Start Recording" : "Finish Anyway", action: onDone)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
    }
}
