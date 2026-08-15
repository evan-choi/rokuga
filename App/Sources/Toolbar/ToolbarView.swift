import CaptureKit
import SettingsKit
import SwiftUI

struct ToolbarView: View {
    @ObservedObject var appState: AppState
    @AppStorage(SettingsStore.Key.recordingMode.rawValue) private var modeRaw = RecordingMode.selectedArea.rawValue
    @State private var showsOptions = false

    private var mode: RecordingMode {
        RecordingMode(rawValue: modeRaw) ?? .selectedArea
    }

    var body: some View {
        HStack(spacing: 14) {
            modeButtons
            Divider().frame(height: 28)
            optionsButton
            Spacer(minLength: 8)
            recordButton
        }
        .padding(.horizontal, 18)
        .frame(width: 560, height: 64)
        .background(GlassBackground(cornerRadius: 18))
        .preferredColorScheme(.dark)
    }

    private var modeButtons: some View {
        HStack(spacing: 6) {
            modeButton(.selectedArea, symbol: "rectangle.dashed", label: "Selected Area")
            modeButton(.fullScreen, symbol: "rectangle.inset.filled", label: "Full Screen")
            modeButton(.window, symbol: "macwindow", label: "Window")
        }
    }

    private func modeButton(_ target: RecordingMode, symbol: String, label: LocalizedStringKey) -> some View {
        Button {
            modeRaw = target.rawValue
            appState.selectionModeChanged()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                Text(label)
                    .font(.system(size: 10))
            }
            .frame(width: 76, height: 46)
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .foregroundStyle(mode == target ? Color.white : Color.white.opacity(0.55))
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(mode == target ? Color.white.opacity(0.14) : .clear)
        )
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(mode == target ? .isSelected : [])
    }

    private var optionsButton: some View {
        Button {
            showsOptions.toggle()
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 15, weight: .medium))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.white.opacity(0.7))
        .accessibilityLabel(Text("Options"))
        .popover(isPresented: $showsOptions) {
            OptionsPopoverView()
        }
    }

    private var recordButton: some View {
        Button {
            appState.requestRecord()
        } label: {
            HStack(spacing: 8) {
                Circle().fill(Color.red).frame(width: 10, height: 10)
                Text("Record")
                    .font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 18)
            .frame(height: 38)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(Capsule().fill(Color.white.opacity(0.12)))
        .keyboardShortcut(.defaultAction)
        .accessibilityLabel(Text("Record"))
    }
}
