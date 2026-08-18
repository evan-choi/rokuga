import AppKit
import SwiftUI

@MainActor
final class ToolbarPanelController {
    static let windowLevel = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
    static let popoverLevel = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)

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
            level: Self.windowLevel,
            showsWindowShadow: false
        )
        panel.contentView = hostingView
        panel.clipContent(toRoundedRect: 16)
        panel.onEscape = { [weak appState] in appState?.dismissToolbar() }
        panel.onReturn = { [weak appState] in appState?.requestRecord() }
    }

    var isVisible: Bool {
        panel.isVisible
    }

    /// Bottom-center of the display the mouse pointer is on (user requirement t=172).
    func showAtMouseDisplay() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        else { return }
        let visible = screen.visibleFrame

        let size = hostingView.fittingSize
        let targetFrame = Self.backingAlignedFrame(
            NSRect(
                x: visible.midX - size.width / 2,
                y: visible.minY + Self.bottomMargin,
                width: size.width,
                height: size.height
            ),
            scale: screen.backingScaleFactor
        )
        panel.setFrame(targetFrame, display: true)
        hostingView.layer?.contentsScale = screen.backingScaleFactor
        hostingView.needsDisplay = true
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.registerForCaptureExclusion()
    }

    func hide() {
        panel.orderOut(nil)
    }

    private static func backingAlignedFrame(_ frame: NSRect, scale: CGFloat) -> NSRect {
        let scale = max(scale, 1)

        func aligned(_ value: CGFloat) -> CGFloat {
            (value * scale).rounded() / scale
        }

        return NSRect(
            x: aligned(frame.origin.x),
            y: aligned(frame.origin.y),
            width: aligned(frame.width),
            height: aligned(frame.height)
        )
    }
}
