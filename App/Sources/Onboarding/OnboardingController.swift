import AppKit
import CaptureKit
import KeyboardShortcuts
import SettingsKit
import SwiftUI

/// First-run flow (task 9.1): output folder → screen-recording permission probe →
/// guided denial recovery with a System Settings deep link.
@MainActor
final class OnboardingController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let model: OnboardingModel
    private let onComplete: () -> Void

    init(steps: [OnboardingModel.Step], onComplete: @escaping () -> Void) {
        model = OnboardingModel(steps: steps)
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
                self?.finish()
                self?.onComplete()
            }
        )
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Marks onboarding done and closes the window without the completion callback —
    /// used when the user starts a recording while onboarding is still on screen.
    func completeSilently() {
        finish()
    }

    var isShowingGetStarted: Bool {
        model.step == .getStarted
    }

    private func finish() {
        SettingsStore.shared.onboardingCompleted = true
        window.close()
    }
}

@MainActor
final class OnboardingModel: ObservableObject {
    enum Step {
        case welcome
        case outputFolder
        case screenPermission
        case getStarted
    }

    let steps: [Step]
    @Published var step: Step
    @Published var folderPath = OutputFolderStore.displayPath()
    @Published var permissionGranted: Bool?
    @Published var probing = false

    init(steps: [Step]) {
        self.steps = steps
        step = steps.first ?? .welcome
    }

    var isLastStep: Bool {
        step == steps.last
    }

    func advance() {
        guard let index = steps.firstIndex(of: step), index + 1 < steps.count else { return }
        step = steps[index + 1]
    }

    /// Unsatisfied requirements, in presentation order. The screen-recording probe runs on every
    /// launch so a revoked permission re-onboards; folder choice and the welcome intro only gate
    /// the very first run.
    static func missingSteps(settings: SettingsStore = .shared) async -> [Step] {
        var missing: [Step] = []
        if !settings.onboardingCompleted, settings.outputFolderBookmark == nil {
            missing.append(.outputFolder)
        }
        if await !ShareableContentService.hasScreenRecordingPermission() {
            missing.append(.screenPermission)
        }
        if !settings.onboardingCompleted {
            missing.insert(.welcome, at: 0)
            missing.append(.getStarted)
        }
        return missing
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = OutputFolderStore.currentFolder()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        OutputFolderStore.setFolder(url)
        folderPath = OutputFolderStore.displayPath(for: url)
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
                Text("Before you start, let's set up a few things\nneeded for screen recording.")
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
        case .getStarted:
            VStack(spacing: 14) {
                Image(systemName: "keyboard")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                Text("You're all set")
                    .font(.title2.bold())
                shortcutCaps
                    .padding(.vertical, 6)
                Text("Press this shortcut anytime to open the recording toolbar and start recording.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding(32)
        }
    }

    private var shortcutCaps: some View {
        let keys = (KeyboardShortcuts.getShortcut(for: .summonToolbar)?.description ?? "⇧⌘6")
            .map(String.init)
        return HStack(spacing: 6) {
            ForEach(keys.indices, id: \.self) { index in
                Text(verbatim: keys[index])
                    .font(.system(size: 19, weight: .medium))
                    .frame(width: 40, height: 40)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
            }
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
            if model.isLastStep {
                Button(doneLabel, action: onDone)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Continue") { model.advance() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }

    private var doneLabel: String {
        if model.step == .screenPermission, model.permissionGranted != true {
            return String(localized: "Finish Anyway")
        }
        return String(localized: "Done")
    }
}
