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
        HStack(spacing: 10) {
            modeButtons
            Divider().frame(height: 22)
            optionsButton
            recordButton
        }
        .padding(.horizontal, 12)
        .frame(height: 54)
        .fixedSize()
        .background(GlassBackground(cornerRadius: 16))
        .preferredColorScheme(.dark)
        .hiddenFocusRing()
    }

    private var modeButtons: some View {
        HStack(spacing: 4) {
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
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                Text(label)
                    .font(.system(size: 9.5))
            }
            .frame(width: 66, height: 40)
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .foregroundStyle(mode == target ? Color.white : Color.white.opacity(0.55))
        .background(
            RoundedRectangle(cornerRadius: 9)
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
                .font(.system(size: 13.5, weight: .medium))
                .frame(width: 30, height: 30)
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
            HStack(spacing: 7) {
                Circle().fill(Color.red).frame(width: 9, height: 9)
                Text("Record")
                    .font(.system(size: 12.5, weight: .semibold))
            }
            .padding(.horizontal, 14)
            .frame(height: 32)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(Capsule().fill(Color.white.opacity(0.12)))
        .keyboardShortcut(.defaultAction)
        .accessibilityLabel(Text("Record"))
    }
}
