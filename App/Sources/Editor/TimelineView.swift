import AppKit
import Combine
import SwiftUI
import TrimKit

/// AppKit timeline (tasks 8.1/8.5): thumbnail strip with lazy per-band tiles, keyframe ticks,
/// draggable keep-range handles, playhead, pinch/⌘-scroll anchored zoom inside an NSScrollView pan.
struct TimelineRepresentable: NSViewRepresentable {
    @ObservedObject var model: TrimEditorModel

    func makeNSView(context: Context) -> TimelineScrollView {
        let scrollView = TimelineScrollView(model: model)
        context.coordinator.bind(scrollView: scrollView, model: model)
        return scrollView
    }

    func updateNSView(_ view: TimelineScrollView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        private var cancellables: Set<AnyCancellable> = []

        func bind(scrollView: TimelineScrollView, model: TrimEditorModel) {
            model.objectWillChange
                .receive(on: DispatchQueue.main)
                .sink { [weak scrollView] in
                    scrollView?.modelDidChange()
                }
                .store(in: &cancellables)
        }
    }
}

final class TimelineScrollView: NSScrollView {
    private let timelineView: TimelineNSView
    private unowned let model: TrimEditorModel
    private var lastZoom: Double

    init(model: TrimEditorModel) {
        self.model = model
        timelineView = TimelineNSView(model: model)
        lastZoom = model.pointsPerSecond
        super.init(frame: .zero)
        documentView = timelineView
        hasHorizontalScroller = true
        hasVerticalScroller = false
        horizontalScrollElasticity = .allowed
        drawsBackground = false
        allowsMagnification = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func magnify(with event: NSEvent) {
        zoomAnchored(factor: 1 + event.magnification, at: event)
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            zoomAnchored(factor: 1 + event.scrollingDeltaY * 0.01, at: event)
            return
        }
        super.scrollWheel(with: event)
    }

    private func zoomAnchored(factor: Double, at event: NSEvent) {
        let locationInDoc = timelineView.convert(event.locationInWindow, from: nil)
        let anchorSeconds = Double(locationInDoc.x) / model.pointsPerSecond
        let anchorXInClip = contentView.convert(locationInDoc, from: timelineView).x

        model.zoom(by: factor)
        layoutDocument()

        let newAnchorX = anchorSeconds * model.pointsPerSecond
        let originX = max(0, newAnchorX - Double(anchorXInClip))
        contentView.scroll(to: NSPoint(x: originX, y: 0))
        reflectScrolledClipView(contentView)
    }

    func modelDidChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.lastZoom != self.model.pointsPerSecond {
                self.lastZoom = self.model.pointsPerSecond
            }
            self.layoutDocument()
            self.timelineView.needsDisplay = true
        }
    }

    private func layoutDocument() {
        let width = max(model.duration * model.pointsPerSecond, contentSize.width)
        timelineView.frame = NSRect(x: 0, y: 0, width: width, height: contentSize.height)
    }

    override func layout() {
        super.layout()
        layoutDocument()
    }
}

final class TimelineNSView: ActiveCursorView {
    private unowned let model: TrimEditorModel
    private var tileImages: [ThumbnailStrip.TileKey: CGImage] = [:]
    private var pendingTiles: Set<ThumbnailStrip.TileKey> = []
    private var dragging: TrimEditorModel.Handle?

    private static let tileWidth: CGFloat = 80
    private static let handleWidth: CGFloat = 10

    init(model: TrimEditorModel) {
        self.model = model
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    private var pps: CGFloat { CGFloat(model.pointsPerSecond) }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, model.duration > 0 else { return }
        drawTiles(in: ctx, dirtyRect: dirtyRect)
        drawKeyframeTicks(in: ctx)
        drawSelection(in: ctx)
        drawPlayhead(in: ctx)
    }

    private func drawTiles(in ctx: CGContext, dirtyRect: NSRect) {
        let band = ThumbnailStrip.band(forPointsPerSecond: model.pointsPerSecond)
        let secondsPerTile = ThumbnailStrip.secondsPerTile(band: band, tileWidth: Self.tileWidth)
        let tileW = CGFloat(secondsPerTile) * pps

        let firstIndex = max(0, Int(dirtyRect.minX / tileW))
        let lastIndex = min(Int(ceil(model.duration / secondsPerTile)), Int(dirtyRect.maxX / tileW) + 1)
        guard firstIndex <= lastIndex else { return }

        for index in firstIndex...lastIndex {
            let key = ThumbnailStrip.TileKey(band: band, index: index)
            let rect = NSRect(x: CGFloat(index) * tileW, y: 8, width: tileW, height: bounds.height - 22)
            if let image = tileImages[key] {
                ctx.saveGState()
                ctx.translateBy(x: 0, y: rect.maxY + rect.minY)
                ctx.scaleBy(x: 1, y: -1)
                ctx.draw(image, in: rect)
                ctx.restoreGState()
            } else {
                ctx.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
                ctx.fill(rect)
                requestTile(key)
            }
        }
    }

    private func requestTile(_ key: ThumbnailStrip.TileKey) {
        guard !pendingTiles.contains(key) else { return }
        pendingTiles.insert(key)
        let strip = model.thumbnails
        Task { @MainActor [weak self] in
            let image = await strip.tile(for: key)
            guard let self else { return }
            self.pendingTiles.remove(key)
            if let image {
                self.tileImages[key] = image
                self.needsDisplay = true
            }
        }
    }

    private func drawKeyframeTicks(in ctx: CGContext) {
        ctx.setFillColor(NSColor.systemYellow.withAlphaComponent(0.75).cgColor)
        for keyframe in model.keyframes {
            let x = CGFloat(keyframe) * pps
            ctx.fill(CGRect(x: x - 0.5, y: bounds.height - 11, width: 1.5, height: 7))
        }
    }

    private func drawSelection(in ctx: CGContext) {
        let startX = CGFloat(model.startSeconds) * pps
        let endX = CGFloat(model.endSeconds) * pps
        let stripRect = NSRect(x: 0, y: 8, width: bounds.width, height: bounds.height - 22)

        ctx.setFillColor(NSColor.black.withAlphaComponent(0.6).cgColor)
        ctx.fill(CGRect(x: 0, y: stripRect.minY, width: startX, height: stripRect.height))
        ctx.fill(CGRect(x: endX, y: stripRect.minY, width: bounds.width - endX, height: stripRect.height))

        let selection = CGRect(x: startX, y: stripRect.minY, width: endX - startX, height: stripRect.height)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(2)
        ctx.stroke(selection)

        for x in [startX, endX] {
            let handle = CGRect(x: x - Self.handleWidth / 2, y: stripRect.minY - 2, width: Self.handleWidth, height: stripRect.height + 4)
            let path = CGPath(roundedRect: handle, cornerWidth: 3, cornerHeight: 3, transform: nil)
            ctx.addPath(path)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillPath()
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.5).cgColor)
            ctx.fill(CGRect(x: x - 0.75, y: stripRect.midY - 8, width: 1.5, height: 16))
        }
    }

    private func drawPlayhead(in ctx: CGContext) {
        let x = CGFloat(model.playheadSeconds) * pps
        ctx.setFillColor(NSColor.systemRed.cgColor)
        ctx.fill(CGRect(x: x - 1, y: 0, width: 2, height: bounds.height))
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let startX = CGFloat(model.startSeconds) * pps
        let endX = CGFloat(model.endSeconds) * pps

        if abs(point.x - startX) <= Self.handleWidth {
            dragging = .start
        } else if abs(point.x - endX) <= Self.handleWidth {
            dragging = .end
        } else {
            dragging = nil
            model.seek(to: Double(point.x) / model.pointsPerSecond)
        }
        refreshActiveCursor()
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let seconds = Double(point.x) / model.pointsPerSecond
        if let handle = dragging {
            model.setHandle(handle, seconds: seconds, snap: true)
        } else {
            model.seek(to: seconds)
        }
        refreshActiveCursor()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        dragging = nil
        refreshActiveCursor()
    }

    override func activeCursor(at point: NSPoint) -> NSCursor {
        if dragging != nil {
            return .resizeLeftRight
        }
        let startX = CGFloat(model.startSeconds) * pps
        let endX = CGFloat(model.endSeconds) * pps
        return abs(point.x - startX) <= Self.handleWidth || abs(point.x - endX) <= Self.handleWidth
            ? .resizeLeftRight
            : .arrow
    }
}
