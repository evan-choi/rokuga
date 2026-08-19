import AppKit
import EncoderKit
import KeyboardShortcuts
import SettingsKit
import SwiftUI

struct SettingsView: View {
    @StateObject private var model = SettingsModel()
    @ObservedObject private var appState = AppState.shared
    @State private var paneHeight: CGFloat?

    private var locked: Bool { appState.recordingState.isActive }

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
        Form {
            Toggle("Launch at login", isOn: $model.launchAtLogin)
            Toggle("Show floating thumbnail after recording", isOn: $model.showFloatingThumbnail)
            Picker("Countdown", selection: $model.countdown) {
                Text("Off").tag(CountdownDuration.off)
                Text(verbatim: "3s").tag(CountdownDuration.three)
                Text(verbatim: "5s").tag(CountdownDuration.five)
                Text(verbatim: "10s").tag(CountdownDuration.ten)
            }
            Divider()
            HStack {
                Spacer()
                Button("Reset All Settings…", action: model.resetAll)
                    .disabled(locked)
            }
        }
        .padding(20)
    }
}

private struct RecordingPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Picker("Default mode", selection: $model.recordingMode) {
                Text("Selected Area").tag(RecordingMode.selectedArea)
                Text("Full Screen").tag(RecordingMode.fullScreen)
                Text("Window").tag(RecordingMode.window)
            }
            Toggle("Hide desktop icons in recordings", isOn: $model.excludeDesktopIcons)
        }
        .padding(20)
    }
}

private struct AudioPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Toggle("Record system audio", isOn: $model.captureSystemAudio)
            Toggle("Record microphone", isOn: $model.captureMicrophone)
            Picker("Audio quality", selection: $model.audioBitrate) {
                ForEach(AudioBitrate.allCases, id: \.self) { bitrate in
                    Text(verbatim: "\(bitrate.rawValue) kbps").tag(bitrate)
                }
            }
        }
        .padding(20)
    }
}

private struct MousePane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Toggle("Show cursor", isOn: $model.showCursor)
            Picker("Pointer style", selection: $model.pointerStyle) {
                Text("System").tag(PointerStyle.system)
                Text("Dot").tag(PointerStyle.dot)
            }
            .disabled(!model.showCursor)
            Toggle("Highlight cursor", isOn: $model.highlightCursor)
            Toggle("Animate clicks", isOn: $model.animateClicks)
        }
        .padding(20)
    }
}

struct ShortcutsPane: View {
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Open Recording Toolbar", name: .summonToolbar)
        }
        .padding(20)
    }
}

private struct OutputPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            LabeledContent("Save to") {
                HStack {
                    Text(model.outputFolderPath)
                        .truncationMode(.middle)
                        .lineLimit(1)
                    Button("Choose…", action: model.chooseOutputFolder)
                }
            }
            Picker("Codec", selection: $model.videoCodec) {
                Text(verbatim: "H.264 (AVC)").tag(VideoCodec.h264)
                Text(verbatim: "H.265 (HEVC)").tag(VideoCodec.hevc)
            }
            Picker("Format", selection: $model.containerFormat) {
                Text(verbatim: "MP4").tag(ContainerFormat.mp4)
                Text(verbatim: "MOV").tag(ContainerFormat.mov)
            }
            Picker("Frame rate", selection: $model.frameRate) {
                Text(verbatim: "30 fps").tag(FrameRate.fps30)
                Text(verbatim: "60 fps").tag(FrameRate.fps60)
            }
            Picker("Frame rate mode", selection: $model.frameRateMode) {
                Text("Variable (VFR)").tag(FrameRateMode.variable)
                Text("Constant (CFR)").tag(FrameRateMode.constant)
            }
            LabeledContent("Quality") {
                HStack(spacing: 8) {
                    Slider(value: qualityBinding, in: 0...100, step: 5) {
                        Text("Quality")
                    }
                    .labelsHidden()
                    Text(verbatim: "\(model.videoQuality)")
                        .monospacedDigit()
                        .fixedSize()
                        .frame(minWidth: 30, alignment: .trailing)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Estimated size")
                        .font(.headline)
                    Spacer()
                    Text(verbatim: "≈ \(estimatedSize)")
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                }
                estimateSummary
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Actual size varies with screen activity.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
            .padding(.top, 8)
        }
        .padding(20)
    }

    private var qualityBinding: Binding<Double> {
        Binding(
            get: { Double(model.videoQuality) },
            set: { model.videoQuality = Int($0) }
        )
    }

    private var estimatedSize: String {
        let videoBitrate = RateControl.averageVideoBitrate(
            width: 1920,
            height: 1080,
            fps: model.frameRate.rawValue,
            quality: model.videoQuality,
            codec: model.videoCodec
        )
        let audioBitrate = model.captureSystemAudio || model.captureMicrophone
            ? model.audioBitrate.rawValue * 1_000
            : 0
        let bytesPerMinute = Int64(videoBitrate + audioBitrate) * 60 / 8
        return ByteCountFormatter.string(fromByteCount: bytesPerMinute, countStyle: .file)
    }

    private var estimateSummary: Text {
        let codec = model.videoCodec == .hevc ? "HEVC" : "H.264"
        let format = model.containerFormat.rawValue.uppercased()
        let frameRateMode = model.frameRateMode == .constant ? "CFR" : "VFR"
        return Text("1920×1080 · 1 min")
            + Text(verbatim: " · \(codec) · \(format) · \(model.frameRate.rawValue) fps · "
                + "\(frameRateMode) · Q\(model.videoQuality)")
    }
}

/// Legacy Settings opener for macOS 13 only.
/// On macOS 14+ this selector no longer exists; use the `openSettings`
/// environment action instead (see `SettingsMenuItem`).
@MainActor
enum SettingsOpener {
    static func open() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
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
