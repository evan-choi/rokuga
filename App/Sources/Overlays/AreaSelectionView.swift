import AppKit

enum RegionMetrics {
    static let handleRadius: CGFloat = 4.5
    static let handleHitRadius: CGFloat = 12
    static let minimumEdge: CGFloat = 50
}

enum RegionHandle: CaseIterable {
    case topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight

    var movesLeft: Bool { [.topLeft, .left, .bottomLeft].contains(self) }
    var movesRight: Bool { [.topRight, .right, .bottomRight].contains(self) }
    var movesTop: Bool { [.topLeft, .top, .topRight].contains(self) }
    var movesBottom: Bool { [.bottomLeft, .bottom, .bottomRight].contains(self) }

    func position(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .top: return CGPoint(x: rect.midX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .left: return CGPoint(x: rect.minX, y: rect.midY)
        case .right: return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottom: return CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }
}

/// Visual-only region chrome: dim + punched rectangle + dashed border + grips + size badge.
/// Lives in a click-through panel; all mouse handling happens in `RegionInteractionView`.
final class AreaSelectionView: NSView {
    var region: CGRect {
        didSet { needsDisplay = true }
    }

    /// Only the region's host display draws the size badge; its off-screen clamp
    /// would otherwise produce ghost badges on neighboring displays.
    var showsBadge = false {
        didSet { needsDisplay = true }
    }

    init(frame: NSRect, region: CGRect) {
        self.region = region
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.setFillColor(NSColor.black.withAlphaComponent(0.4).cgColor)
        ctx.fill(bounds)

        ctx.saveGState()
        ctx.setBlendMode(.clear)
        ctx.fill(region)
        ctx.restoreGState()

        ctx.saveGState()
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(1.5)
        ctx.setLineDash(phase: 0, lengths: [6, 4])
        ctx.stroke(region)
        ctx.restoreGState()

        for handle in RegionHandle.allCases {
            let center = handle.position(in: region)
            let rect = CGRect(
                x: center.x - RegionMetrics.handleRadius,
                y: center.y - RegionMetrics.handleRadius,
                width: RegionMetrics.handleRadius * 2,
                height: RegionMetrics.handleRadius * 2
            )
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillEllipse(in: rect)
            ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.35).cgColor)
            ctx.setLineWidth(1)
            ctx.strokeEllipse(in: rect)
        }

        if showsBadge {
            drawBadge(
                text: "\(Int(region.width)) × \(Int(region.height))",
                centerX: region.midX,
                y: max(region.minY - 26, 8)
            )
        }
    }

    private func drawBadge(text: String, centerX: CGFloat, y: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attributes)
        let padding: CGFloat = 8
        let badge = CGRect(
            x: centerX - size.width / 2 - padding,
            y: y,
            width: size.width + padding * 2,
            height: size.height + 8
        )
        let path = CGPath(roundedRect: badge, cornerWidth: badge.height / 2, cornerHeight: badge.height / 2, transform: nil)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.addPath(path)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.72).cgColor)
        ctx.fillPath()
        text.draw(at: CGPoint(x: badge.minX + padding, y: badge.minY + 4), withAttributes: attributes)
    }
}

/// Mouse surface for the region: move by dragging inside, resize via the 8 grips.
/// Sized to the region plus the grip hit margin so everything outside stays click-through.
/// Drag math uses global coordinates because this view's window moves during the drag.
final class RegionInteractionView: NSView {
    var onRegionEdit: ((CGRect) -> Void)?
    var onEditEnd: (() -> Void)?

    /// Region in global CG (top-left) coordinates.
    var region: CGRect = .zero {
        didSet { window?.invalidateCursorRects(for: self) }
    }

    private var dragMode: DragMode = .none
    private var mouseAtDragStart: CGPoint?
    private var regionAtDragStart: CGRect?
    private var cursorPushed = false

    private enum DragMode: Equatable {
        case none
        case moving
        case resizing(RegionHandle)
    }

    init() {
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// `region` mapped into this (flipped) view's coordinates via the window's global frame.
    private var regionInView: CGRect {
        guard let window else { return .zero }
        let windowCG = ScreenCoords.cgRect(fromCocoa: window.frame)
        return region.offsetBy(dx: -windowCG.minX, dy: -windowCG.minY)
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        let point = convert(event.locationInWindow, from: nil)
        mouseAtDragStart = NSEvent.mouseLocation
        regionAtDragStart = region

        if let handle = handleHit(at: point) {
            dragMode = .resizing(handle)
            push(Self.cursor(for: handle))
        } else if regionInView.contains(point) {
            dragMode = .moving
            push(.closedHand)
        } else {
            dragMode = .none
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = regionAtDragStart, let mouseStart = mouseAtDragStart else { return }
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - mouseStart.x
        let dy = mouseStart.y - mouse.y // global Cocoa (bottom-left) → top-left region space

        switch dragMode {
        case .moving:
            onRegionEdit?(start.offsetBy(dx: dx, dy: dy))
        case let .resizing(handle):
            onRegionEdit?(resize(start, handle: handle, dx: dx, dy: dy))
        case .none:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        popCursorIfNeeded()
        let wasEditing = dragMode != .none
        dragMode = .none
        mouseAtDragStart = nil
        regionAtDragStart = nil
        if wasEditing {
            onEditEnd?()
        }
    }

    private func push(_ cursor: NSCursor) {
        cursor.push()
        cursorPushed = true
    }

    private func popCursorIfNeeded() {
        if cursorPushed {
            NSCursor.pop()
            cursorPushed = false
        }
    }

    // MARK: Cursors

    override func resetCursorRects() {
        let inner = regionInView.insetBy(dx: RegionMetrics.handleHitRadius, dy: RegionMetrics.handleHitRadius)
        if !inner.isEmpty {
            addCursorRect(inner, cursor: .openHand)
        }
        for handle in RegionHandle.allCases {
            let center = handle.position(in: regionInView)
            addCursorRect(
                CGRect(
                    x: center.x - RegionMetrics.handleHitRadius,
                    y: center.y - RegionMetrics.handleHitRadius,
                    width: RegionMetrics.handleHitRadius * 2,
                    height: RegionMetrics.handleHitRadius * 2
                ),
                cursor: Self.cursor(for: handle)
            )
        }
    }

    private static let diagonalNWSE = diagonalCursor(symbol: "arrow.up.left.and.arrow.down.right")
    private static let diagonalNESW = diagonalCursor(symbol: "arrow.up.right.and.arrow.down.left")

    private static func cursor(for handle: RegionHandle) -> NSCursor {
        if #available(macOS 15.0, *) {
            let position: NSCursor.FrameResizePosition
            switch handle {
            case .topLeft: position = .topLeft
            case .top: position = .top
            case .topRight: position = .topRight
            case .left: position = .left
            case .right: position = .right
            case .bottomLeft: position = .bottomLeft
            case .bottom: position = .bottom
            case .bottomRight: position = .bottomRight
            }
            return .frameResize(position: position, directions: .all)
        }
        switch handle {
        case .left, .right: return .resizeLeftRight
        case .top, .bottom: return .resizeUpDown
        case .topLeft, .bottomRight: return diagonalNWSE
        case .topRight, .bottomLeft: return diagonalNESW
        }
    }

    private static func diagonalCursor(symbol: String) -> NSCursor {
        let side: CGFloat = 24
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            guard let base = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 14, weight: .bold)) else { return false }
            let origin = NSPoint(
                x: (rect.width - base.size.width) / 2,
                y: (rect.height - base.size.height) / 2
            )
            // White halo behind the black glyph keeps the cursor visible over the dim.
            for delta in [(-1.0, 0.0), (1.0, 0.0), (0.0, -1.0), (0.0, 1.0)] {
                tinted(base, .white).draw(at: NSPoint(x: origin.x + delta.0, y: origin.y + delta.1), from: .zero, operation: .sourceOver, fraction: 1)
            }
            tinted(base, .black).draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: side / 2, y: side / 2))
    }

    private static func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    // MARK: Geometry

    private func handleHit(at point: CGPoint) -> RegionHandle? {
        RegionHandle.allCases.first { handle in
            let center = handle.position(in: regionInView)
            return hypot(point.x - center.x, point.y - center.y) <= RegionMetrics.handleHitRadius
        }
    }

    private func resize(_ rect: CGRect, handle: RegionHandle, dx: CGFloat, dy: CGFloat) -> CGRect {
        var minX = rect.minX
        var minY = rect.minY
        var maxX = rect.maxX
        var maxY = rect.maxY
        let edge = RegionMetrics.minimumEdge

        if handle.movesLeft { minX = min(minX + dx, maxX - edge) }
        if handle.movesRight { maxX = max(maxX + dx, minX + edge) }
        if handle.movesTop { minY = min(minY + dy, maxY - edge) }
        if handle.movesBottom { maxY = max(maxY + dy, minY + edge) }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
