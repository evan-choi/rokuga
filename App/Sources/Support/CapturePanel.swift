import AppKit
import CaptureKit
import SwiftUI

/// NSHostingView that lets the first click on a non-key panel start SwiftUI gestures immediately (system capture overlays never require a focus click).
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
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

    override func close() {
        CaptureExcludedWindows.shared.unregister(CGWindowID(windowNumber))
        super.close()
    }
}
