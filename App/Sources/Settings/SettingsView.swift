import AppKit
import KeyboardShortcuts
import SettingsKit
import SwiftUI

struct SettingsView: View {
    @StateObject private var model = SettingsModel()
    @ObservedObject private var appState = AppState.shared

    private var locked: Bool { appState.recordingState.isActive }

    var body: some View {
        TabView {
            GeneralPane(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
                .disabled(locked)
            RecordingPane(model: model)
                .tabItem { Label("Recording", systemImage: "record.circle") }
                .disabled(locked)
            AudioPane(model: model)
                .tabItem { Label("Audio", systemImage: "speaker.wave.2") }
                .disabled(locked)
            MousePane(model: model)
                .tabItem { Label("Mouse", systemImage: "cursorarrow.motionlines") }
                .disabled(locked)
            ShortcutsPane()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            OutputPane(model: model)
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

    var body: some View {
        Form {
            Picker("Appearance", selection: $model.theme) {
                Text("Auto").tag(Theme.auto)
                Text("Light").tag(Theme.light)
                Text("Dark").tag(Theme.dark)
            }
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
            KeyboardShortcuts.Recorder("Start / Stop Recording", name: .toggleRecording)
            KeyboardShortcuts.Recorder("Pause / Resume", name: .pauseResume)
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
            Slider(value: qualityBinding, in: 0...100, step: 5) {
                Text("Quality")
            } minimumValueLabel: {
                Text(verbatim: "0")
            } maximumValueLabel: {
                Text(verbatim: "100")
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
