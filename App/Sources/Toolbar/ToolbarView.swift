import AppKit
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
            cancelButton
            modeButtons
            dragHandle
            optionsButton
            recordButton
        }
        .padding(.horizontal, 12)
        .frame(height: 54)
        .fixedSize()
        .background(GlassBackground(cornerRadius: 16))
        .hiddenFocusRing()
    }

    private var cancelButton: some View {
        Button {
            appState.dismissToolbar()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 19, weight: .semibold))
                .frame(width: 30, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.primary)
        .help("Cancel")
        .accessibilityLabel(Text("Cancel"))
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
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 44, height: 36)
                .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.primary)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(mode == target ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor) : .clear)
        )
        .help(label)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(mode == target ? .isSelected : [])
    }

    private var dragHandle: some View {
        ZStack {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1, height: 22)
            WindowDragHandle()
        }
        .frame(width: 13, height: 36)
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
        .foregroundStyle(Color.primary)
        .help("Options")
        .accessibilityLabel(Text("Options"))
        .popover(isPresented: $showsOptions) {
            OptionsPopoverView()
                .background(PopoverWindowLevel(level: ToolbarPanelController.popoverLevel))
                .onDisappear {
                    appState.refreshSelectionCursor()
                }
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
        .foregroundStyle(.primary)
        .background(Capsule().fill(Color(nsColor: .controlBackgroundColor).opacity(0.72)))
        .keyboardShortcut(.defaultAction)
        .accessibilityLabel(Text("Record"))
    }
}

private struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragView {
        WindowDragView()
    }

    func updateNSView(_ view: WindowDragView, context: Context) {}
}

private final class WindowDragView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
}

private struct PopoverWindowLevel: NSViewRepresentable {
    let level: NSWindow.Level

    func makeNSView(context: Context) -> PopoverWindowLevelView {
        let view = PopoverWindowLevelView()
        view.targetLevel = level
        return view
    }

    func updateNSView(_ view: PopoverWindowLevelView, context: Context) {
        view.targetLevel = level
        view.applyWindowLevel()
    }
}

private final class PopoverWindowLevelView: NSView {
    var targetLevel: NSWindow.Level = .normal

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyWindowLevel()
    }

    func applyWindowLevel() {
        window?.level = targetLevel
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
