import AppKit
import CaptureKit
import SettingsKit
import SwiftUI

/// Region-selection overlay (task 4.5): drag to select, resize by 8 handles, move by dragging inside, hover-snap to windows, per-display persistence.
/// Completion receives the crop in display-local points (SCStream `sourceRect` space) or nil on cancel.
@MainActor
final class RegionSelectionController {
    private let panel: CapturePanel
    private let display: DisplayTarget
    private let settings: SettingsStore
    private let completion: (CGRect?) -> Void
    private let model: RegionSelectionModel

    init(display: DisplayTarget, settings: SettingsStore, completion: @escaping (CGRect?) -> Void) {
        self.display = display
        self.settings = settings
        self.completion = completion

        let saved = settings.selectedRegions[String(display.displayID)]
        model = RegionSelectionModel(displaySize: display.frame.size, initialRegion: saved, displayID: display.displayID)

        panel = CapturePanel(contentRect: display.frame, level: .screenSaver)
        panel.isMovableByWindowBackground = false

        let controllerBox = WeakBox<RegionSelectionController>()
        panel.contentView = NSHostingView(
            rootView: RegionSelectionView(model: model) { region in
                controllerBox.value?.finish(with: region)
            }
        )
        panel.onEscape = { [weak self] in self?.finish(with: nil) }
        controllerBox.value = self

        Task { await loadSnapCandidates() }
    }

    func present() {
        panel.setFrame(display.frame, display: true)
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.registerForCaptureExclusion()
        NSCursor.crosshair.set()
    }

    private func finish(with region: CGRect?) {
        NSCursor.arrow.set()
        panel.close()
        if let region {
            settings.selectedRegions[String(display.displayID)] = region
            completion(flippedToDisplayLocal(region))
        } else {
            completion(nil)
        }
    }

    /// SwiftUI coordinates are top-left based within the overlay, which already matches SCStream's `sourceRect` orientation.
    private func flippedToDisplayLocal(_ rect: CGRect) -> CGRect {
        rect.integral
    }

    private func loadSnapCandidates() async {
        guard let content = try? await ShareableContentService.currentContent() else { return }
        let displayFrame = display.frame
        let candidates = ShareableContentService.windowTargets(from: content)
            .map(\.frame)
            .filter { displayFrame.intersects($0) }
            .map { global -> CGRect in
                CGRect(
                    x: global.minX - displayFrame.minX,
                    y: global.minY - displayFrame.minY,
                    width: global.width,
                    height: global.height
                )
            }
        model.snapCandidates = candidates
    }
}

final class WeakBox<T: AnyObject> {
    weak var value: T?
}

@MainActor
final class RegionSelectionModel: ObservableObject {
    @Published var region: CGRect?
    @Published var hoveredSnap: CGRect?
    @Published var loupePoint: CGPoint?
    var snapCandidates: [CGRect] = []
    let displaySize: CGSize
    let displayID: CGDirectDisplayID

    init(displaySize: CGSize, initialRegion: CGRect?, displayID: CGDirectDisplayID = CGMainDisplayID()) {
        self.displaySize = displaySize
        self.displayID = displayID
        region = initialRegion
    }

    func clamp(_ rect: CGRect) -> CGRect {
        var r = rect.standardized
        r.origin.x = max(0, min(r.origin.x, displaySize.width - r.width))
        r.origin.y = max(0, min(r.origin.y, displaySize.height - r.height))
        r.size.width = min(r.width, displaySize.width - r.origin.x)
        r.size.height = min(r.height, displaySize.height - r.origin.y)
        return r
    }

    func snapCandidate(at point: CGPoint) -> CGRect? {
        snapCandidates
            .filter { $0.contains(point) }
            .min { $0.width * $0.height < $1.width * $1.height }
    }
}

struct RegionSelectionView: View {
    @ObservedObject var model: RegionSelectionModel
    let onConfirm: (CGRect?) -> Void

    @State private var dragOrigin: CGPoint?
    @State private var dragMode: DragMode = .none
    @State private var regionAtDragStart: CGRect?

    enum DragMode: Equatable {
        case none
        case creating
        case moving
        case resizing(Handle)
    }

    enum Handle: CaseIterable, Equatable {
        case topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight
    }

    var body: some View {
        GeometryReader { _ in
            ZStack {
                dimLayer
                if let snap = model.hoveredSnap, model.region == nil {
                    snapHighlight(snap)
                }
                if let region = model.region {
                    selectionChrome(region)
                }
                if let loupePoint = model.loupePoint {
                    PixelLoupeView(point: loupePoint, displayID: model.displayID, displaySize: model.displaySize)
                }
                instructionBadge
            }
            .contentShape(Rectangle())
            .gesture(mainGesture)
            .onContinuousHover { phase in
                guard model.region == nil else { return }
                switch phase {
                case let .active(point):
                    model.hoveredSnap = model.snapCandidate(at: point)
                case .ended:
                    model.hoveredSnap = nil
                }
            }
            .onTapGesture {
                if let snap = model.hoveredSnap, model.region == nil {
                    model.region = model.clamp(snap)
                }
            }
        }
        .ignoresSafeArea()
    }

    private var dimLayer: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.35)))
            if let region = model.region {
                context.blendMode = .clear
                context.fill(Path(region), with: .color(.black))
            }
        }
        .allowsHitTesting(false)
    }

    private func snapHighlight(_ rect: CGRect) -> some View {
        Rectangle()
            .stroke(Color.accentColor, lineWidth: 2)
            .background(Color.accentColor.opacity(0.12))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func selectionChrome(_ region: CGRect) -> some View {
        Rectangle()
            .stroke(Color.white, lineWidth: 1.5)
            .frame(width: region.width, height: region.height)
            .position(x: region.midX, y: region.midY)
            .allowsHitTesting(false)

        sizeBadge(region)

        ForEach(Handle.allCases, id: \.self) { handle in
            let point = position(of: handle, in: region)
            Circle()
                .fill(Color.white)
                .frame(width: 9, height: 9)
                .position(point)
                .allowsHitTesting(false)
        }

        confirmBar(region)
    }

    private func sizeBadge(_ region: CGRect) -> some View {
        Text(verbatim: "\(Int(region.width)) × \(Int(region.height))")
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.black.opacity(0.7)))
            .foregroundStyle(.white)
            .position(x: region.midX, y: max(region.minY - 18, 14))
            .allowsHitTesting(false)
    }

    private func confirmBar(_ region: CGRect) -> some View {
        HStack(spacing: 10) {
            Button("Cancel") { onConfirm(nil) }
                .keyboardShortcut(.cancelAction)
            Button("Record") { onConfirm(model.region) }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(.red)
        }
        .padding(10)
        .background(GlassBackground(cornerRadius: 12))
        .position(x: region.midX, y: min(region.maxY + 34, model.displaySize.height - 30))
    }

    private var instructionBadge: some View {
        Group {
            if model.region == nil {
                Text("Drag to select an area — click a window to snap")
                    .font(.system(size: 12))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.6)))
                    .foregroundStyle(.white.opacity(0.85))
                    .position(x: model.displaySize.width / 2, y: 40)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: Drag machinery

    private var mainGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if dragOrigin == nil {
                    beginDrag(at: value.startLocation)
                }
                updateDrag(to: value.location)
                if case .creating = dragMode {
                    model.loupePoint = value.location
                } else if case .resizing = dragMode {
                    model.loupePoint = value.location
                }
            }
            .onEnded { _ in
                dragOrigin = nil
                regionAtDragStart = nil
                dragMode = .none
                model.loupePoint = nil
            }
    }

    private func beginDrag(at point: CGPoint) {
        dragOrigin = point
        regionAtDragStart = model.region

        if let region = model.region {
            if let handle = handleHit(at: point, in: region) {
                dragMode = .resizing(handle)
            } else if region.insetBy(dx: -6, dy: -6).contains(point) {
                dragMode = .moving
            } else {
                dragMode = .creating
                model.region = nil
                regionAtDragStart = nil
            }
        } else {
            dragMode = .creating
        }
    }

    private func updateDrag(to point: CGPoint) {
        guard let origin = dragOrigin else { return }
        switch dragMode {
        case .creating:
            model.region = model.clamp(
                CGRect(
                    x: min(origin.x, point.x),
                    y: min(origin.y, point.y),
                    width: abs(point.x - origin.x),
                    height: abs(point.y - origin.y)
                )
            )
        case .moving:
            guard let start = regionAtDragStart else { return }
            var moved = start
            moved.origin.x += point.x - origin.x
            moved.origin.y += point.y - origin.y
            model.region = model.clamp(moved)
        case let .resizing(handle):
            guard let start = regionAtDragStart else { return }
            model.region = model.clamp(resize(start, handle: handle, dx: point.x - origin.x, dy: point.y - origin.y))
        case .none:
            break
        }
    }

    private func handleHit(at point: CGPoint, in region: CGRect) -> Handle? {
        Handle.allCases.first { handle in
            let center = position(of: handle, in: region)
            return hypot(point.x - center.x, point.y - center.y) <= 12
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
