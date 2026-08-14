import AppKit
import SwiftUI

@MainActor
final class ToolbarPanelController {
    private let panel: CapturePanel
    private static let panelSize = NSSize(width: 560, height: 64)
    private static let bottomMargin: CGFloat = 96

    init(appState: AppState) {
        panel = CapturePanel(contentRect: NSRect(origin: .zero, size: Self.panelSize))
        panel.contentView = NSHostingView(
            rootView: ToolbarView(appState: appState)
                .environmentObject(appState)
        )
        panel.onEscape = { [weak self] in self?.hide() }
    }

    /// Bottom-center of the display the mouse pointer is on (user requirement t=172).
    func showAtMouseDisplay() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }

        let origin = NSPoint(
            x: visible.midX - Self.panelSize.width / 2,
            y: visible.minY + Self.bottomMargin
        )
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.registerForCaptureExclusion()
    }

    func hide() {
        panel.orderOut(nil)
    }
}
