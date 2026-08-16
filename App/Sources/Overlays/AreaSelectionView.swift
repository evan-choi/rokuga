import AppKit

/// AppKit region-selection surface: SwiftUI drag gestures are unreliable on
/// non-activating borderless panels of an accessory app, so all interaction and
/// drawing happens in plain NSView mouse handlers.
final class AreaSelectionView: NSView {
    var onRegionChanged: ((CGRect) -> Void)?

    var region: CGRect? {
        didSet {
            if let region { onRegionChanged?(region) }
            window?.invalidateCursorRects(for: self)
            needsDisplay = true
        }
    }

    private let displayID: CGDirectDisplayID
    private var dragMode: DragMode = .none
    private var dragOrigin: CGPoint?
    private var regionAtDragStart: CGRect?
    private var loupePoint: CGPoint?

    private static let handleRadius: CGFloat = 4.5
    private static let handleHitRadius: CGFloat = 12
    private static let minimumEdge: CGFloat = 50

    private enum DragMode: Equatable {
        case none
        case creating
        case moving
        case resizing(Handle)
    }

    private enum Handle: CaseIterable {
        case topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight
    }

    init(frame: NSRect, displayID: CGDirectDisplayID) {
        self.displayID = displayID
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

        if let region {
            ctx.saveGState()
            ctx.setBlendMode(.clear)
            ctx.fill(region)
            ctx.restoreGState()

            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(1.5)
            ctx.stroke(region)

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
        } else {
            drawBadge(
                text: String(localized: "Drag to select an area"),
                centerX: bounds.midX,
                y: 32
            )
        }

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

        if let region {
            if let handle = handleHit(at: point, in: region) {
                dragMode = .resizing(handle)
            } else if region.insetBy(dx: -6, dy: -6).contains(point) {
                dragMode = .moving
            } else {
                dragMode = .creating
                self.region = nil
                regionAtDragStart = nil
            }
        } else {
            dragMode = .creating
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = dragOrigin else { return }
        let point = convert(event.locationInWindow, from: nil)

        switch dragMode {
        case .creating:
            region = clamp(
                CGRect(
                    x: min(origin.x, point.x),
                    y: min(origin.y, point.y),
                    width: abs(point.x - origin.x),
                    height: abs(point.y - origin.y)
                )
            )
            loupePoint = point
        case .moving:
            guard let start = regionAtDragStart else { return }
            region = clamp(start.offsetBy(dx: point.x - origin.x, dy: point.y - origin.y))
        case let .resizing(handle):
            guard let start = regionAtDragStart else { return }
            region = clamp(resize(start, handle: handle, dx: point.x - origin.x, dy: point.y - origin.y))
            loupePoint = point
        case .none:
            break
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if dragMode == .creating,
           let region,
           region.width < Self.minimumEdge || region.height < Self.minimumEdge {
            self.region = nil
        }
        dragMode = .none
        dragOrigin = nil
        regionAtDragStart = nil
        loupePoint = nil
        needsDisplay = true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
        guard let region else { return }
        // insetBy/intersection return the null rect (infinite origin) for tiny or
        // non-overlapping rects; addCursorRect asserts isfinite, so guard every rect.
        addFiniteCursorRect(region.insetBy(dx: 6, dy: 6), cursor: .openHand)
        for handle in Handle.allCases {
            let center = position(of: handle, in: region)
            addFiniteCursorRect(
                CGRect(
                    x: center.x - Self.handleHitRadius,
                    y: center.y - Self.handleHitRadius,
                    width: Self.handleHitRadius * 2,
                    height: Self.handleHitRadius * 2
                ),
                cursor: .crosshair
            )
        }
    }

    private func addFiniteCursorRect(_ rect: CGRect, cursor: NSCursor) {
        let clipped = rect.intersection(bounds)
        guard !clipped.isNull, !clipped.isEmpty else { return }
        addCursorRect(clipped, cursor: cursor)
    }

    // MARK: Geometry

    private func clamp(_ rect: CGRect) -> CGRect {
        var r = rect.standardized
        r.origin.x = max(0, min(r.origin.x, bounds.width - r.width))
        r.origin.y = max(0, min(r.origin.y, bounds.height - r.height))
        r.size.width = min(r.width, bounds.width - r.origin.x)
        r.size.height = min(r.height, bounds.height - r.origin.y)
        return r
    }

    private func handleHit(at point: CGPoint, in region: CGRect) -> Handle? {
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
        var r = rect
        switch handle {
        case .topLeft:
            r.origin.x += dx; r.origin.y += dy; r.size.width -= dx; r.size.height -= dy
        case .top:
            r.origin.y += dy; r.size.height -= dy
        case .topRight:
            r.origin.y += dy; r.size.width += dx; r.size.height -= dy
        case .left:
            r.origin.x += dx; r.size.width -= dx
        case .right:
            r.size.width += dx
        case .bottomLeft:
            r.origin.x += dx; r.size.width -= dx; r.size.height += dy
        case .bottom:
            r.size.height += dy
        case .bottomRight:
            r.size.width += dx; r.size.height += dy
        }
        return r
    }
}
