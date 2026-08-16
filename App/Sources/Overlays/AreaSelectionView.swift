import AppKit

/// AppKit region-selection surface: a dashed punch rectangle that always exists
/// (saved region or centered default). Users resize via the 8 circular grips and
/// move by dragging inside — there is no draw-to-create gesture, matching the
/// system capture grammar.
final class AreaSelectionView: NSView {
    var onRegionChanged: ((CGRect) -> Void)?

    var region: CGRect {
        didSet {
            onRegionChanged?(region)
            window?.invalidateCursorRects(for: self)
            needsDisplay = true
        }
    }

    private let displayID: CGDirectDisplayID
    private var dragMode: DragMode = .none
    private var dragOrigin: CGPoint?
    private var regionAtDragStart: CGRect?
    private var loupePoint: CGPoint?
    private var cursorPushed = false

    private static let handleRadius: CGFloat = 4.5
    private static let handleHitRadius: CGFloat = 12
    private static let minimumEdge: CGFloat = 50

    private enum DragMode: Equatable {
        case none
        case moving
        case resizing(Handle)
    }

    private enum Handle: CaseIterable {
        case topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight

        var movesLeft: Bool { [.topLeft, .left, .bottomLeft].contains(self) }
        var movesRight: Bool { [.topRight, .right, .bottomRight].contains(self) }
        var movesTop: Bool { [.topLeft, .top, .topRight].contains(self) }
        var movesBottom: Bool { [.bottomLeft, .bottom, .bottomRight].contains(self) }
    }

    init(frame: NSRect, displayID: CGDirectDisplayID, initialRegion: CGRect?) {
        self.displayID = displayID
        let fallback = CGRect(
            x: frame.width * 0.25,
            y: frame.height * 0.25,
            width: frame.width * 0.5,
            height: frame.height * 0.5
        ).integral
        self.region = initialRegion ?? fallback
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Drawing

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

        for handle in Handle.allCases {
            let center = position(of: handle, in: region)
            let rect = CGRect(
                x: center.x - Self.handleRadius,
                y: center.y - Self.handleRadius,
                width: Self.handleRadius * 2,
                height: Self.handleRadius * 2
            )
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillEllipse(in: rect)
            ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.35).cgColor)
            ctx.setLineWidth(1)
            ctx.strokeEllipse(in: rect)
        }

        drawBadge(
            text: "\(Int(region.width)) × \(Int(region.height))",
            centerX: region.midX,
            y: max(region.minY - 26, 8)
        )

        if let loupePoint {
            drawLoupe(at: loupePoint, in: ctx)
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

    private func drawLoupe(at point: CGPoint, in ctx: CGContext) {
        guard let sample = LoupeSampler.capture(around: point, displayID: displayID) else { return }

        let side: CGFloat = 110
        let offset: CGFloat = 74
        let x = point.x + (point.x > bounds.width - side - 90 ? -offset - side : offset)
        let y = point.y + (point.y < side + 90 ? offset : -offset - side)
        let circle = CGRect(x: x, y: y, width: side, height: side)

        ctx.saveGState()
        ctx.addEllipse(in: circle)
        ctx.clip()
        ctx.interpolationQuality = .none
        ctx.translateBy(x: 0, y: circle.midY * 2)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(sample, in: CGRect(x: circle.minX, y: circle.midY * 2 - circle.maxY, width: side, height: side))
        ctx.restoreGState()

        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        ctx.setLineWidth(2)
        ctx.strokeEllipse(in: circle)

        let pixel = side / PixelLoupeSampleRect.side
        ctx.setStrokeColor(NSColor.systemRed.cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(CGRect(x: circle.midX - pixel / 2, y: circle.midY - pixel / 2, width: pixel, height: pixel))

        drawBadge(text: "\(Int(point.x)), \(Int(point.y))", centerX: circle.midX, y: circle.maxY + 6)
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        dragOrigin = point
        regionAtDragStart = region

        if let handle = handleHit(at: point) {
            dragMode = .resizing(handle)
            push(Self.cursor(for: handle))
        } else if region.contains(point) {
            dragMode = .moving
            push(.closedHand)
        } else {
            dragMode = .none
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = dragOrigin else { return }
        let point = convert(event.locationInWindow, from: nil)

        switch dragMode {
        case .moving:
            guard let start = regionAtDragStart else { return }
            region = clampPosition(start.offsetBy(dx: point.x - origin.x, dy: point.y - origin.y))
        case let .resizing(handle):
            guard let start = regionAtDragStart else { return }
            region = resize(start, handle: handle, dx: point.x - origin.x, dy: point.y - origin.y)
            loupePoint = point
        case .none:
            break
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        popCursorIfNeeded()
        dragMode = .none
        dragOrigin = nil
        regionAtDragStart = nil
        loupePoint = nil
        needsDisplay = true
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
        addCursorRect(bounds, cursor: .arrow)
        addFiniteCursorRect(region.insetBy(dx: Self.handleHitRadius, dy: Self.handleHitRadius), cursor: .openHand)
        for handle in Handle.allCases {
            let center = position(of: handle, in: region)
            addFiniteCursorRect(
                CGRect(
                    x: center.x - Self.handleHitRadius,
                    y: center.y - Self.handleHitRadius,
                    width: Self.handleHitRadius * 2,
                    height: Self.handleHitRadius * 2
                ),
                cursor: Self.cursor(for: handle)
            )
        }
    }

    private func addFiniteCursorRect(_ rect: CGRect, cursor: NSCursor) {
        let clipped = rect.intersection(bounds)
        guard !clipped.isNull, !clipped.isEmpty else { return }
        addCursorRect(clipped, cursor: cursor)
    }

    private static let diagonalNWSE = diagonalCursor(symbol: "arrow.up.left.and.arrow.down.right")
    private static let diagonalNESW = diagonalCursor(symbol: "arrow.up.right.and.arrow.down.left")

    private static func cursor(for handle: Handle) -> NSCursor {
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

    private func clampPosition(_ rect: CGRect) -> CGRect {
        var r = rect
        r.origin.x = max(0, min(r.origin.x, bounds.width - r.width))
        r.origin.y = max(0, min(r.origin.y, bounds.height - r.height))
        return r
    }

    private func handleHit(at point: CGPoint) -> Handle? {
        Handle.allCases.first { handle in
            let center = position(of: handle, in: region)
            return hypot(point.x - center.x, point.y - center.y) <= Self.handleHitRadius
        }
    }

    private func position(of handle: Handle, in rect: CGRect) -> CGPoint {
        switch handle {
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

    private func resize(_ rect: CGRect, handle: Handle, dx: CGFloat, dy: CGFloat) -> CGRect {
        var minX = rect.minX
        var minY = rect.minY
        var maxX = rect.maxX
        var maxY = rect.maxY
        let edge = Self.minimumEdge

        if handle.movesLeft { minX = min(max(0, minX + dx), maxX - edge) }
        if handle.movesRight { maxX = max(min(bounds.width, maxX + dx), minX + edge) }
        if handle.movesTop { minY = min(max(0, minY + dy), maxY - edge) }
        if handle.movesBottom { maxY = max(min(bounds.height, maxY + dy), minY + edge) }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
