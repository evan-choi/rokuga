import AppKit
import CaptureKit
import SettingsKit

/// Region-selection overlay (task 4.5): drag to select, resize by 8 handles, move by dragging inside, per-display persistence.
/// Lives alongside the toolbar (system capture grammar): the toolbar's record button or Return starts recording; Esc dismisses everything.
@MainActor
final class RegionSelectionController {
    private let panel: CapturePanel
    private var dimPanels: [CapturePanel] = []
    private let view: AreaSelectionView
    let display: DisplayTarget

    init(
        display: DisplayTarget,
        settings: SettingsStore,
        onRecordRequested: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.display = display

        view = AreaSelectionView(
            frame: NSRect(origin: .zero, size: display.frame.size),
            displayID: display.displayID
        )
        view.region = settings.selectedRegions[String(display.displayID)]
        view.onRegionChanged = { region in
            settings.selectedRegions[String(display.displayID)] = region
        }

        panel = CapturePanel(contentRect: display.frame, level: .screenSaver)
        panel.isMovableByWindowBackground = false
        panel.contentView = view
        panel.onEscape = onCancel
        panel.onReturn = onRecordRequested

        // Area mode dims every display; the marquee lives on the target display only.
        for screen in NSScreen.screens where screen.frame != display.frame {
            let dimPanel = CapturePanel(contentRect: screen.frame, level: .screenSaver)
            dimPanel.ignoresMouseEvents = true
            dimPanel.isMovableByWindowBackground = false
            let dimView = DimView(frame: NSRect(origin: .zero, size: screen.frame.size))
            dimView.dimmed = true
            dimPanel.contentView = dimView
            dimPanels.append(dimPanel)
        }
    }

    /// Current crop in display-local top-left points (SCStream `sourceRect` space — the flipped view shares it).
    var currentRegion: CGRect? {
        view.region?.integral
    }

    func present() {
        panel.setFrame(display.frame, display: true)
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.registerForCaptureExclusion()
        for dimPanel in dimPanels {
            dimPanel.orderFrontRegardless()
            dimPanel.registerForCaptureExclusion()
        }
        NSCursor.crosshair.set()
    }

    func close() {
        NSCursor.arrow.set()
        panel.close()
        dimPanels.forEach { $0.close() }
        dimPanels = []
    }
}
