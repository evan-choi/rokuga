import CoreGraphics
import Foundation
import ScreenCaptureKit

public struct ExclusionOptions: Equatable, Sendable {
    public var excludeDesktopIcons: Bool

    public init(excludeDesktopIcons: Bool) {
        self.excludeDesktopIcons = excludeDesktopIcons
    }
}

/// Builds `SCContentFilter`s implementing the capture-exclusion spec (task 2.4).
public enum ContentFilterBuilder {
    public static func filter(
        for target: CaptureTarget,
        content: SCShareableContent,
        exclusion: ExclusionOptions,
        overlayRegistry: CaptureExcludedWindows = .shared
    ) -> SCContentFilter? {
        switch target {
        case let .display(displayTarget, _):
            guard let display = content.displays.first(where: { $0.displayID == displayTarget.displayID }) else {
                return nil
            }
            let excluded = excludedWindows(in: content, exclusion: exclusion, overlayRegistry: overlayRegistry)
            return SCContentFilter(display: display, excludingWindows: excluded)

        case let .window(windowTarget):
            guard let window = content.windows.first(where: { $0.windowID == windowTarget.windowID }) else {
                return nil
            }
            return SCContentFilter(desktopIndependentWindow: window)
        }
    }

    /// Union of: overlay windows (always), own-process windows (always), desktop-icon-level windows (toggle).
    static func excludedWindows(
        in content: SCShareableContent,
        exclusion: ExclusionOptions,
        overlayRegistry: CaptureExcludedWindows
    ) -> [SCWindow] {
        let ownPID = getpid()
        let overlayIDs = overlayRegistry.all
        let desktopIconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))

        return content.windows.filter { window in
            if overlayIDs.contains(window.windowID) { return true }
            if window.owningApplication?.processID == ownPID { return true }
            if exclusion.excludeDesktopIcons, window.windowLayer == desktopIconLevel { return true }
            return false
        }
    }
}
