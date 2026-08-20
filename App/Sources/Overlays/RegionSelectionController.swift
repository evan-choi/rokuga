import AppKit
import CaptureKit
import SettingsKit

/// Region-selection overlay (task 4.5): resize by 8 handles, move by dragging inside, per-display persistence.
/// Lives alongside the toolbar (system capture grammar): the toolbar's record button or Return starts recording; Esc dismisses everything.
///
/// The region lives in global CG (top-left) coordinates and can be dragged across displays,
/// matching the native capture UI. Panels split responsibilities so click-through works per area:
/// - every display gets a full-screen visual panel (`ignoresMouseEvents = true`) drawing the
///   dim/punch/chrome slice that falls on it, so clicks outside the region reach whatever is underneath;
/// - one interaction panel tracks the region (plus grip margin) and explicitly sets
///   `ignoresMouseEvents = false` — otherwise AppKit's per-pixel hit testing would let clicks fall
///   through the transparent punched interior.
///
/// SCStream crops within a single display, so when a drag ends the region snaps into the display
/// it overlaps most — the punched area always equals what would be recorded.
@MainActor
final class RegionSelectionController {
    private struct DisplaySurface {
        let display: DisplayTarget
        let cgFrame: CGRect
        let panel: CapturePanel
        let view: AreaSelectionView
    }

    private var surfaces: [DisplaySurface] = []
    private let interactionPanel: CapturePanel
    private let interactionView: RegionInteractionView
    private let settings: SettingsStore
    private let fallbackDisplay: DisplayTarget
    /// Global CG (top-left); fully inside one display whenever no drag is in progress.
    private var region: CGRect

    var display: DisplayTarget {
        hostSurface()?.display ?? fallbackDisplay
    }

    var currentRegion: CGRect? {
        guard let host = hostSurface() else { return region.integral }
        return region.offsetBy(dx: -host.cgFrame.minX, dy: -host.cgFrame.minY).integral
    }

    init(
        display: DisplayTarget,
        settings: SettingsStore,
        onRecordRequested: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.settings = settings
        fallbackDisplay = display

        let displayCG = ScreenCoords.cgRect(fromCocoa: display.frame)
        let fallbackRegion = CGRect(
            x: display.frame.width * 0.25,
            y: display.frame.height * 0.25,
            width: display.frame.width * 0.5,
            height: display.frame.height * 0.5
        ).integral
        let localRegion = settings.selectedRegions[String(display.displayID)] ?? fallbackRegion
        region = localRegion.offsetBy(dx: displayCG.minX, dy: displayCG.minY)

        for screen in NSScreen.screens {
            guard let target = ScreenCoords.displayTarget(for: screen) else { continue }
            let view = AreaSelectionView(
                frame: NSRect(origin: .zero, size: screen.frame.size),
                region: .zero,
                pointToPixelScale: target.pointToPixelScale
            )
            let panel = CapturePanel(contentRect: screen.frame, level: .screenSaver)
            panel.ignoresMouseEvents = true
            panel.isMovableByWindowBackground = false
            panel.hasShadow = false
            panel.contentView = view
            surfaces.append(DisplaySurface(
                display: target,
                cgFrame: ScreenCoords.cgRect(fromCocoa: screen.frame),
                panel: panel,
                view: view
            ))
        }

        interactionView = RegionInteractionView()
        interactionPanel = CapturePanel(
            contentRect: Self.interactionFrame(for: region),
            level: .screenSaver
        )
        interactionPanel.ignoresMouseEvents = false
        interactionPanel.isMovableByWindowBackground = false
        interactionPanel.hasShadow = false
        interactionPanel.contentView = interactionView
        interactionPanel.onEscape = onCancel
        interactionPanel.onReturn = onRecordRequested

        interactionView.onRegionEdit = { [weak self] newRegion in
            self?.region = newRegion
            self?.syncViews()
        }
        interactionView.onEditEnd = { [weak self] in
            self?.clampIntoHostDisplay()
            self?.persistRegion()
        }

        clampIntoHostDisplay()
    }

    func present() {
        for surface in surfaces {
            surface.panel.orderFrontRegardless()
            surface.panel.registerForCaptureExclusion()
        }
        interactionPanel.orderFrontRegardless()
        // Keep the toolbar key so its native popover retains active chrome.
        // RegionInteractionView accepts first mouse and does not need key-window status.
        interactionPanel.registerForCaptureExclusion()
    }

    func close() {
        surfaces.forEach { $0.panel.close() }
        surfaces = []
        interactionPanel.close()
    }

    private func syncViews() {
        let host = hostSurface()
        for surface in surfaces {
            surface.view.region = region.offsetBy(dx: -surface.cgFrame.minX, dy: -surface.cgFrame.minY)
            surface.view.showsBadge = surface.display.displayID == host?.display.displayID
        }
        interactionView.region = region
        interactionPanel.setFrame(Self.interactionFrame(for: region), display: false)
    }

    private func clampIntoHostDisplay() {
        guard let bounds = hostSurface()?.cgFrame else { return }
        var r = region
        r.size.width = min(r.width, bounds.width)
        r.size.height = min(r.height, bounds.height)
        r.origin.x = max(bounds.minX, min(r.minX, bounds.maxX - r.width))
        r.origin.y = max(bounds.minY, min(r.minY, bounds.maxY - r.height))
        region = r
        syncViews()
    }

    private func persistRegion() {
        guard let host = hostSurface() else { return }
        settings.selectedRegions[String(host.display.displayID)] =
            region.offsetBy(dx: -host.cgFrame.minX, dy: -host.cgFrame.minY)
    }

    private func hostSurface() -> DisplaySurface? {
        let byOverlap = surfaces.max { overlapArea($0) < overlapArea($1) }
        if let byOverlap, overlapArea(byOverlap) > 0 {
            return byOverlap
        }
        let mouse = ScreenCoords.cgPoint(fromCocoa: NSEvent.mouseLocation)
        return surfaces.first { $0.cgFrame.contains(mouse) } ?? surfaces.first
    }

    private func overlapArea(_ surface: DisplaySurface) -> CGFloat {
        let intersection = surface.cgFrame.intersection(region)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }

    private static func interactionFrame(for region: CGRect) -> NSRect {
        let margin = RegionMetrics.handleHitRadius
        return ScreenCoords.cocoaRect(fromCG: region.insetBy(dx: -margin, dy: -margin))
    }
}
