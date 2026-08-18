import AppKit
import CaptureKit
import SwiftUI

/// NSHostingView that lets the first click on a non-key panel start SwiftUI gestures immediately (system capture overlays never require a focus click).
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Cursor tracking that remains active for non-key capture panels.
/// AppKit cursor rects are key-window driven, so HUD views resolve the cursor directly.
class ActiveCursorView: NSView {
    private var activeCursorTrackingArea: NSTrackingArea?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let activeCursorTrackingArea {
            removeTrackingArea(activeCursorTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        activeCursorTrackingArea = trackingArea
    }

    override func mouseMoved(with event: NSEvent) {
        applyActiveCursor(for: event)
    }

    override func mouseEntered(with event: NSEvent) {
        applyActiveCursor(for: event)
    }

    override func cursorUpdate(with event: NSEvent) {
        applyActiveCursor(for: event)
    }

    func activeCursor(at point: NSPoint) -> NSCursor {
        .arrow
    }

    @discardableResult
    func refreshActiveCursor() -> Bool {
        guard let window,
              window.isVisible,
              NSWindow.windowNumber(
                  at: NSEvent.mouseLocation,
                  belowWindowWithWindowNumber: 0
              ) == window.windowNumber
        else { return false }

        let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        activeCursor(at: convert(windowPoint, from: nil)).set()
        return true
    }

    private func applyActiveCursor(for event: NSEvent) {
        activeCursor(at: convert(event.locationInWindow, from: nil)).set()
    }
}

/// Non-activating floating panel base for all HUD surfaces (toolbar, countdown, thumbnail).
/// Registers itself in `CaptureExcludedWindows` so it never appears in recordings, and routes Esc to `onEscape`.
class CapturePanel: NSPanel {
    var onEscape: (() -> Void)?
    var onReturn: (() -> Void)?

    init(
        contentRect: NSRect,
        level: NSWindow.Level = .floating,
        showsWindowShadow: Bool = true
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        isReleasedWhenClosed = false
        // Disable for rounded glass surfaces: this shadow follows the rectangular
        // window backing and can appear as black edge lines around their corners.
        hasShadow = showsWindowShadow
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        self.level = level
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53:
            onEscape?()
        case 36, 76:
            if let onReturn {
                onReturn()
            } else {
                super.keyDown(with: event)
            }
        default:
            super.keyDown(with: event)
        }
    }

    func registerForCaptureExclusion() {
        CaptureExcludedWindows.shared.register(CGWindowID(windowNumber))
    }

    /// Clips transparent glass content to its visible rounded surface so the
    /// window backing cannot appear as a rectangular edge or shadow.
    func clipContent(toRoundedRect cornerRadius: CGFloat) {
        guard let contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor
        contentView.layer?.cornerRadius = cornerRadius
        contentView.layer?.cornerCurve = .continuous
        contentView.layer?.masksToBounds = true
        hasShadow = false
        invalidateShadow()
    }

    override func close() {
        CaptureExcludedWindows.shared.unregister(CGWindowID(windowNumber))
        super.close()
    }
}
