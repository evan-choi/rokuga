import AppKit
import SwiftUI

@MainActor
final class ToolbarPanelController {
    private let panel: CapturePanel
    private let hostingView: NSHostingView<AnyView>
    private static let bottomMargin: CGFloat = 96

    init(appState: AppState) {
        hostingView = NSHostingView(
            rootView: AnyView(
                ToolbarView(appState: appState)
                    .environmentObject(appState)
            )
        )
        panel = CapturePanel(
            contentRect: NSRect(origin: .zero, size: hostingView.fittingSize),
            level: NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1),
            showsWindowShadow: false
        )
        panel.contentView = hostingView
        panel.onEscape = { [weak appState] in appState?.dismissToolbar() }
        panel.onReturn = { [weak appState] in appState?.requestRecord() }
    }

    var isVisible: Bool {
        panel.isVisible
    }

    /// Bottom-center of the display the mouse pointer is on (user requirement t=172).
    func showAtMouseDisplay() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }

        let size = hostingView.fittingSize
        panel.setFrame(
            NSRect(
                x: visible.midX - size.width / 2,
                y: visible.minY + Self.bottomMargin,
                width: size.width,
                height: size.height
            ),
            display: true
        )
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.registerForCaptureExclusion()
    }

    func hide() {
        panel.orderOut(nil)
    }
}
