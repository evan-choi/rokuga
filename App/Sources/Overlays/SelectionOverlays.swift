import AppKit
import CaptureKit

enum ScreenCoords {
    static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.maxY ?? 0
    }

    /// Global CG (top-left) rect → global Cocoa (bottom-left) rect.
    static func cocoaRect(fromCG rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func cgPoint(fromCocoa point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    /// Global Cocoa (bottom-left) rect → global CG (top-left) rect.
    static func cgRect(fromCocoa rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func displayTarget(for screen: NSScreen) -> DisplayTarget? {
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        else { return nil }
        let mode = CGDisplayCopyDisplayMode(displayID)
        return DisplayTarget(
            displayID: displayID,
            frame: screen.frame,
            pixelWidth: mode?.pixelWidth ?? Int(screen.frame.width),
            pixelHeight: mode?.pixelHeight ?? Int(screen.frame.height)
        )
    }
}

private enum SelectionCursors {
    static let clickToRecord: NSCursor = {
        guard let image = NSImage(named: NSImage.Name("ScreenshotWindowCursor")) else {
            return .crosshair
        }
        image.size = NSSize(width: 32, height: 32)
        return NSCursor(image: image, hotSpot: NSPoint(x: 16, y: 16))
    }()
}

/// Front-to-back window geometry for hover hit-testing, refreshed at most every 0.25 s.
final class WindowHitTester {
    private var cache: [(target: WindowTarget, cgFrame: CGRect)] = []
    private var lastRefresh: TimeInterval = 0

    func window(atCGPoint point: CGPoint) -> (target: WindowTarget, cgFrame: CGRect)? {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastRefresh > 0.25 {
            refresh()
            lastRefresh = now
        }
        return cache.first { $0.cgFrame.contains(point) }
    }

    private func refresh() {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return }

        let ownPID = getpid()
        cache = list.compactMap { info in
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat]
            else { return nil }
            let frame = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )
            guard frame.width >= 50, frame.height >= 50 else { return nil }
            let target = WindowTarget(
                windowID: windowID,
                title: info[kCGWindowName as String] as? String,
                appName: info[kCGWindowOwnerName as String] as? String,
                appBundleID: nil,
                appPID: pid,
                frame: frame
            )
            return (target, frame)
        }
    }
}

class SelectionTrackingView: ActiveCursorView {
    var onMouseMoved: (() -> Void)?
    var onMouseDown: (() -> Void)?
    var selectionCursor: NSCursor? {
        didSet {
            refreshActiveCursor()
        }
    }

    var selectionCursorRects: [NSRect] = [] {
        didSet {
            refreshActiveCursor()
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseMoved(with event: NSEvent) {
        onMouseMoved?()
        super.mouseMoved(with: event)
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseMoved?()
        super.mouseEntered(with: event)
    }

    override func mouseDown(with event: NSEvent) { onMouseDown?() }

    @discardableResult
    func reapplySelectionCursor() -> Bool {
        refreshActiveCursor()
    }

    override func activeCursor(at point: NSPoint) -> NSCursor {
        guard selectionCursorRects.contains(where: { $0.contains(point) }),
              let selectionCursor
        else { return .arrow }
        return selectionCursor
    }
}

/// Window mode selection layer: translucent highlight follows the hovered window; click records it.
@MainActor
final class WindowHoverController {
    private var panels: [CapturePanel] = []
    private var highlightViews: [HoverHighlightView] = []
    private let hitTester = WindowHitTester()
    private let onPick: (WindowTarget) -> Void
    private(set) var hoveredWindow: WindowTarget?

    init(onPick: @escaping (WindowTarget) -> Void) {
        self.onPick = onPick
        for screen in NSScreen.screens {
            let panel = CapturePanel(contentRect: screen.frame, level: .screenSaver)
            panel.isMovableByWindowBackground = false
            let view = HoverHighlightView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.selectionCursor = SelectionCursors.clickToRecord
            view.onMouseMoved = { [weak self] in self?.updateHover() }
            view.onMouseDown = { [weak self] in self?.pick() }
            panel.contentView = view
            panels.append(panel)
            highlightViews.append(view)
        }
    }

    func present() {
        for panel in panels {
            panel.orderFrontRegardless()
            panel.registerForCaptureExclusion()
        }
        updateHover()
        refreshCursor()
    }

    func close() {
        panels.forEach { $0.close() }
        panels = []
        NSCursor.arrow.set()
    }

    func refreshCursor() {
        _ = highlightViews.first { $0.reapplySelectionCursor() }
    }

    private func updateHover() {
        let cgPoint = ScreenCoords.cgPoint(fromCocoa: NSEvent.mouseLocation)
        let hit = hitTester.window(atCGPoint: cgPoint)
        hoveredWindow = hit?.target

        let cocoaFrame = hit.map { ScreenCoords.cocoaRect(fromCG: $0.cgFrame) }
        for (panel, view) in zip(panels, highlightViews) {
            if let cocoaFrame, panel.frame.intersects(cocoaFrame) {
                let highlightRect = cocoaFrame.offsetBy(dx: -panel.frame.minX, dy: -panel.frame.minY)
                view.highlightRect = highlightRect
                view.selectionCursorRects = [highlightRect]
            } else {
                view.highlightRect = nil
                view.selectionCursorRects = []
            }
        }
    }

    private func pick() {
        if let hoveredWindow {
            onPick(hoveredWindow)
        }
    }
}

final class HoverHighlightView: SelectionTrackingView {
    var highlightRect: CGRect? {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let highlightRect else { return }
        NSColor.systemBlue.withAlphaComponent(0.25).setFill()
        let path = NSBezierPath(roundedRect: highlightRect, xRadius: 10, yRadius: 10)
        path.fill()
        NSColor.systemBlue.withAlphaComponent(0.6).setStroke()
        path.lineWidth = 2
        path.stroke()
    }
}

/// Full Screen mode selection layer: dims every display except the one under the pointer; click records it.
@MainActor
final class DisplaySelectController {
    private struct DisplayPanel {
        let panel: CapturePanel
        let view: DimView
        let screen: NSScreen
    }

    private var panels: [DisplayPanel] = []
    private let onPick: (DisplayTarget) -> Void
    private(set) var hoveredDisplay: DisplayTarget?

    init(onPick: @escaping (DisplayTarget) -> Void) {
        self.onPick = onPick
        for screen in NSScreen.screens {
            let panel = CapturePanel(contentRect: screen.frame, level: .screenSaver)
            panel.ignoresMouseEvents = false
            panel.isMovableByWindowBackground = false
            let view = DimView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.selectionCursor = SelectionCursors.clickToRecord
            view.selectionCursorRects = [view.bounds]
            view.onMouseMoved = { [weak self] in self?.updateHover() }
            view.onMouseDown = { [weak self] in self?.pick(screen: screen) }
            panel.contentView = view
            panels.append(DisplayPanel(panel: panel, view: view, screen: screen))
        }
    }

    func present() {
        for entry in panels {
            entry.panel.orderFrontRegardless()
            entry.panel.registerForCaptureExclusion()
        }
        updateHover()
        refreshCursor()
    }

    func close() {
        panels.forEach { $0.panel.close() }
        panels = []
        NSCursor.arrow.set()
    }

    func refreshCursor() {
        _ = panels.first { $0.view.reapplySelectionCursor() }
    }

    private func updateHover() {
        let mouse = NSEvent.mouseLocation
        for entry in panels {
            let isHovered = NSMouseInRect(mouse, entry.screen.frame, false)
            entry.view.dimmed = !isHovered
            if isHovered {
                hoveredDisplay = ScreenCoords.displayTarget(for: entry.screen)
            }
        }
    }

    private func pick(screen: NSScreen) {
        if let target = ScreenCoords.displayTarget(for: screen) {
            onPick(target)
        }
    }
}

final class DimView: SelectionTrackingView {
    var dimmed = false {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        // A fully transparent borderless panel is skipped by WindowServer hit testing.
        // One alpha step keeps the selected display clickable without visibly dimming it.
        let alpha: CGFloat = dimmed ? 0.45 : 1.0 / 255.0
        NSColor.black.withAlphaComponent(alpha).setFill()
        bounds.fill()
    }
}

/// Recording-time punch-through for Selected Area: click-through dim with a clear hole over the captured region.
@MainActor
final class PunchOverlayController {
    private let panel: CapturePanel

    init(display: DisplayTarget, region: CGRect) {
        panel = CapturePanel(
            contentRect: display.frame,
            level: .screenSaver,
            showsWindowShadow: false
        )
        panel.ignoresMouseEvents = true
        panel.isMovableByWindowBackground = false
        let view = PunchView(frame: NSRect(origin: .zero, size: display.frame.size))
        view.hole = region
        panel.contentView = view
    }

    func present() {
        panel.orderFrontRegardless()
        panel.registerForCaptureExclusion()
    }

    func close() {
        panel.close()
    }
}

final class PunchView: NSView {
    /// Captured region in display-local top-left coordinates (SCStream `sourceRect` space).
    var hole: CGRect = .zero

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
        ctx.fill(bounds)
        ctx.setBlendMode(.clear)
        ctx.fill(hole)
    }
}
