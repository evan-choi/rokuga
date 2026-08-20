import AppKit
import KeyboardShortcuts
import SettingsKit
import SwiftUI

struct SettingsView: View {
    @StateObject private var model = SettingsModel()
    @ObservedObject private var appState = AppState.shared
    @State private var paneHeight: CGFloat?

    private var locked: Bool {
        appState.recordingState.isActive
    }

    var body: some View {
        TabView {
            GeneralPane(model: model, locked: locked)
                .animatedPaneHeight($paneHeight)
                .tabItem { Label("General", systemImage: "gearshape") }
            RecordingPane(model: model)
                .animatedPaneHeight($paneHeight)
                .tabItem { Label("Recording", systemImage: "record.circle") }
                .disabled(locked)
            AudioPane(model: model)
                .animatedPaneHeight($paneHeight)
                .tabItem { Label("Audio", systemImage: "speaker.wave.2") }
                .disabled(locked)
            MousePane(model: model)
                .animatedPaneHeight($paneHeight)
                .tabItem { Label("Mouse", systemImage: "cursorarrow.motionlines") }
                .disabled(locked)
            ShortcutsPane()
                .animatedPaneHeight($paneHeight)
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            OutputPane(model: model)
                .animatedPaneHeight($paneHeight)
                .tabItem { Label("Output", systemImage: "folder") }
                .disabled(locked)
        }
        .frame(width: 460)
        .overlay(alignment: .bottom) {
            if locked {
                Text("Settings are locked while recording")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 6)
            }
        }
    }
}

private struct GeneralPane: View {
    @ObservedObject var model: SettingsModel
    let locked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsRow(Text("Language")) {
                Picker("Language", selection: $model.appLanguage) {
                    Text("System Default").tag(AppLanguage.system)
                    Text("English").tag(AppLanguage.english)
                    Text("Korean").tag(AppLanguage.korean)
                    Text("Japanese").tag(AppLanguage.japanese)
                    Text("Simplified Chinese").tag(AppLanguage.simplifiedChinese)
                }
                .labelsHidden()
                .disabled(locked)
            }
            SettingsRow {
                Toggle("Launch at login", isOn: $model.launchAtLogin)
            }
            SettingsRow {
                Toggle("Show floating thumbnail after recording", isOn: $model.showFloatingThumbnail)
            }
            SettingsRow(Text("Countdown")) {
                Picker("Countdown", selection: $model.countdown) {
                    Text("Off").tag(CountdownDuration.off)
                    Text(verbatim: "3s").tag(CountdownDuration.three)
                    Text(verbatim: "5s").tag(CountdownDuration.five)
                    Text(verbatim: "10s").tag(CountdownDuration.ten)
                }
                .labelsHidden()
            }
            Divider()
            SettingsRow {
                HStack {
                    Spacer()
                    Button("Reset All Settings…", action: model.resetAll)
                        .disabled(locked)
                }
            }
        }
        .padding(20)
    }
}

private struct RecordingPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsRow(Text("Default mode")) {
                Picker("Default mode", selection: $model.recordingMode) {
                    Text("Selected Area").tag(RecordingMode.selectedArea)
                    Text("Full Screen").tag(RecordingMode.fullScreen)
                    Text("Window").tag(RecordingMode.window)
                }
                .labelsHidden()
            }
            SettingsRow {
                Toggle("Hide desktop icons in recordings", isOn: $model.excludeDesktopIcons)
            }
        }
        .padding(20)
    }
}

private struct AudioPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsRow {
                Toggle("Record system audio", isOn: $model.captureSystemAudio)
            }
            SettingsRow {
                Toggle("Record microphone", isOn: $model.captureMicrophone)
            }
            SettingsRow(Text("Audio quality")) {
                Picker("Audio quality", selection: $model.audioBitrate) {
                    ForEach(AudioBitrate.allCases, id: \.self) { bitrate in
                        Text(verbatim: "\(bitrate.rawValue) kbps").tag(bitrate)
                    }
                }
                .labelsHidden()
            }
            if model.captureSystemAudio, model.captureMicrophone {
                SettingsRow(Text("Audio tracks")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Picker("Audio tracks", selection: $model.audioTrackLayout) {
                            Text("Mixed").tag(AudioTrackLayout.mixed)
                            Text("Separate")
                                .tag(AudioTrackLayout.separate)
                                .disabled(model.containerFormat == .mp4)
                        }
                        .labelsHidden()
                        if model.containerFormat == .mp4 {
                            Label {
                                Text("Separate tracks require MOV.")
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.yellow)
                            }
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        } else if model.audioTrackLayout == .separate {
                            Text("Separate tracks are intended for editing.\nSome players may play only one track.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(20)
    }
}

private struct MousePane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsRow {
                Toggle("Show cursor", isOn: $model.showCursor)
            }
            SettingsRow {
                Toggle("Animate clicks", isOn: $model.animateClicks)
            }
        }
        .padding(20)
    }
}

struct ShortcutsPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsRow(Text("Open Recording Toolbar")) {
                KeyboardShortcuts.Recorder(for: .summonToolbar)
                    .keyboardShortcutsConflictPolicy(.init(systemShortcut: .allow))
                    .accessibilityLabel(Text("Open Recording Toolbar"))
            }
        }
        .padding(20)
    }
}

private struct OutputPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsRow(Text("Save to")) {
                HStack {
                    Text(model.outputFolderPath)
                        .truncationMode(.middle)
                        .lineLimit(1)
                    Button("Choose…", action: model.chooseOutputFolder)
                }
            }
            SettingsRow(Text("Codec")) {
                Picker("Codec", selection: $model.videoCodec) {
                    Text(verbatim: "H.264 (AVC)").tag(VideoCodec.h264)
                    Text(verbatim: "H.265 (HEVC)").tag(VideoCodec.hevc)
                }
                .labelsHidden()
            }
            SettingsRow(Text("Format")) {
                Picker("Format", selection: $model.containerFormat) {
                    Text(verbatim: "MP4").tag(ContainerFormat.mp4)
                    Text(verbatim: "MOV").tag(ContainerFormat.mov)
                }
                .labelsHidden()
            }
            SettingsRow(Text("Frame rate")) {
                Picker("Frame rate", selection: $model.frameRate) {
                    Text(verbatim: "30 fps").tag(FrameRate.fps30)
                    Text(verbatim: "60 fps").tag(FrameRate.fps60)
                    Text("Match Display").tag(FrameRate.matchDisplay)
                }
                .labelsHidden()
            }
            SettingsRow(Text("Frame rate mode")) {
                Picker("Frame rate mode", selection: $model.frameRateMode) {
                    Text("Variable (VFR)").tag(FrameRateMode.variable)
                    Text("Constant (CFR)").tag(FrameRateMode.constant)
                }
                .labelsHidden()
            }
            SettingsRow(Text("Quality")) {
                HStack(spacing: 8) {
                    Slider(value: qualityBinding, in: 0 ... 100, step: 5) {
                        Text("Quality")
                    }
                    .labelsHidden()
                    Text(verbatim: "\(model.videoQuality)")
                        .monospacedDigit()
                        .fixedSize()
                        .frame(minWidth: 30, alignment: .trailing)
                }
            }
        }
        .padding(20)
    }

    private var qualityBinding: Binding<Double> {
        Binding(
            get: { Double(model.videoQuality) },
            set: { model.videoQuality = Int($0) }
        )
    }
}

private struct SettingsRow<Content: View>: View {
    private let label: Text?
    private let content: Content

    init(_ label: Text? = nil, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            ZStack(alignment: .trailing) {
                if let label {
                    label
                }
            }
            .frame(width: 120, alignment: .trailing)

            content
                .frame(width: 230, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

/// SwiftUI's Settings `TabView` snaps the window to each pane's size, unlike AppKit's
/// `NSTabViewController` which animates it. Pinning every pane to one shared height and
/// animating that value makes the window frame follow smoothly instead.
private struct AnimatedPaneHeight: ViewModifier {
    @Binding var sharedHeight: CGFloat?
    @State private var naturalHeight: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { apply(proxy.size.height) }
                        .onChange(of: proxy.size.height) { apply($0) }
                }
            )
            .frame(height: sharedHeight ?? naturalHeight, alignment: .top)
            .clipped()
    }

    private func apply(_ height: CGFloat) {
        naturalHeight = height
        guard height > 0, sharedHeight != height else { return }
        if sharedHeight == nil {
            sharedHeight = height
        } else {
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.3)) {
                sharedHeight = height
            }
        }
    }
}

private extension View {
    func animatedPaneHeight(_ height: Binding<CGFloat?>) -> some View {
        modifier(AnimatedPaneHeight(sharedHeight: height))
    }
}
