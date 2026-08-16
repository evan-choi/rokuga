import AppKit
import SettingsKit
import SwiftUI

struct OptionsPopoverView: View {
    private enum Layout {
        static let outerPadding: CGFloat = 16
        static let sectionSpacing: CGFloat = 12
        static let titleSpacing: CGFloat = 4
        static let rowSpacing: CGFloat = 4
        static let segmentedControlWidth: CGFloat = 186
        static let width = segmentedControlWidth + outerPadding * 2
    }

    @AppStorage(SettingsStore.Key.countdown.rawValue) private var countdown = CountdownDuration.three.rawValue
    @AppStorage(SettingsStore.Key.frameRate.rawValue) private var frameRate = FrameRate.fps60.rawValue
    @AppStorage(SettingsStore.Key.captureSystemAudio.rawValue) private var systemAudio = true
    @AppStorage(SettingsStore.Key.captureMicrophone.rawValue) private var microphone = false
    @AppStorage(SettingsStore.Key.showCursor.rawValue) private var showCursor = true
    @AppStorage(SettingsStore.Key.animateClicks.rawValue) private var animateClicks = false
    @AppStorage(SettingsStore.Key.showFloatingThumbnail.rawValue) private var showThumbnail = true

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
            section("Save to") {
                Button {
                    chooseOutputFolder()
                } label: {
                    Label(OutputFolderStore.currentFolder().lastPathComponent, systemImage: "folder")
                }
                .accessibilityLabel(Text("Choose output folder"))
            }

            section("Countdown") {
                Picker("Countdown", selection: $countdown) {
                    Text("Off").tag(CountdownDuration.off.rawValue)
                    Text("3s").tag(CountdownDuration.three.rawValue)
                    Text("5s").tag(CountdownDuration.five.rawValue)
                    Text("10s").tag(CountdownDuration.ten.rawValue)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: Layout.segmentedControlWidth)
            }

            section("Frame Rate") {
                Picker("Frame Rate", selection: $frameRate) {
                    Text("30 fps").tag(FrameRate.fps30.rawValue)
                    Text("60 fps").tag(FrameRate.fps60.rawValue)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: Layout.segmentedControlWidth)
            }

            section("Audio") {
                Toggle("System Audio", isOn: $systemAudio)
                Toggle("Microphone", isOn: $microphone)
            }

            section("Mouse") {
                Toggle("Show Cursor", isOn: $showCursor)
                Toggle("Click Animations", isOn: $animateClicks)
            }

            section("After Recording") {
                Toggle("Show Floating Thumbnail", isOn: $showThumbnail)
            }
        }
        .padding(Layout.outerPadding)
        .frame(width: Layout.width)
    }

    private func section(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Layout.titleSpacing) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: Layout.rowSpacing) {
                content()
            }
        }
    }

    private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        SettingsStore.shared.outputFolderBookmark = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }
}
