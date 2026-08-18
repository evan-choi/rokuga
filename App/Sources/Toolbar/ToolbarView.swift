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
        .captureWindowChrome()
        .hiddenFocusRing()
    }

    private var cancelButton: some View {
        Button {
            ToolbarTooltipPresenter.shared.hide()
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
        .captureTooltip("Cancel")
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
            ToolbarTooltipPresenter.shared.hide()
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
        .captureTooltip(label)
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
            ToolbarTooltipPresenter.shared.hide()
            showsOptions.toggle()
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 13.5, weight: .medium))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.primary)
        .captureTooltip("Options")
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
            ToolbarTooltipPresenter.shared.hide()
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

private extension View {
    func captureTooltip(_ label: LocalizedStringKey) -> some View {
        background(TooltipTrackingView(label: label))
    }
}

private struct TooltipTrackingView: NSViewRepresentable {
    let label: LocalizedStringKey

    func makeNSView(context: Context) -> TooltipTrackingNSView {
        TooltipTrackingNSView(label: label)
    }

    func updateNSView(_ view: TooltipTrackingNSView, context: Context) {
        view.label = label
    }

    static func dismantleNSView(_ view: TooltipTrackingNSView, coordinator: ()) {
        ToolbarTooltipPresenter.shared.hide()
    }
}

private final class TooltipTrackingNSView: NSView {
    var label: LocalizedStringKey

    init(label: LocalizedStringKey) {
        self.label = label
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        ToolbarTooltipPresenter.shared.show(label, relativeTo: self)
    }

    override func mouseExited(with event: NSEvent) {
        ToolbarTooltipPresenter.shared.hide()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
final class ToolbarTooltipPresenter {
    static let shared = ToolbarTooltipPresenter()

    private var panel: CapturePanel?

    func show(_ label: LocalizedStringKey, relativeTo anchor: NSView) {
        hide()
        guard let toolbarWindow = anchor.window else { return }
        let hostingView = NSHostingView(
            rootView: Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .captureWindowChrome(cornerRadius: CaptureWindowChrome.tooltipCornerRadius)
                .fixedSize()
        )
        let size = hostingView.fittingSize
        let tooltipPanel = panel ?? makePanel(size: size)
        tooltipPanel.contentView = hostingView
        tooltipPanel.setContentSize(size)
        tooltipPanel.clipContent(toRoundedRect: CaptureWindowChrome.tooltipCornerRadius)

        let anchorRect = toolbarWindow.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        guard let screen = toolbarWindow.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame.insetBy(dx: 4, dy: 4)
        let gap: CGFloat = 8
        let x = min(max(anchorRect.midX - size.width / 2, visible.minX), visible.maxX - size.width)
        let preferredY = toolbarWindow.frame.maxY + gap
        let y = preferredY + size.height <= visible.maxY
            ? preferredY
            : toolbarWindow.frame.minY - size.height - gap

        tooltipPanel.setFrameOrigin(NSPoint(x: x, y: y))
        tooltipPanel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel(size: NSSize) -> CapturePanel {
        let panel = CapturePanel(
            contentRect: NSRect(origin: .zero, size: size),
            level: ToolbarPanelController.popoverLevel,
            showsWindowShadow: false
        )
        panel.ignoresMouseEvents = true
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .none
        panel.registerForCaptureExclusion()
        self.panel = panel
        return panel
    }
}

private struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragView {
        WindowDragView()
    }

    func updateNSView(_ view: WindowDragView, context: Context) {}
}

private final class WindowDragView: ActiveCursorView {
    private var isDragging = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        refreshActiveCursor()
        window?.performDrag(with: event)
        isDragging = false
        refreshActiveCursor()
    }

    override func activeCursor(at point: NSPoint) -> NSCursor {
        isDragging ? .closedHand : .openHand
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
