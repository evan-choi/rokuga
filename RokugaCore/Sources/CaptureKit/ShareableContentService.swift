import CoreGraphics
import Foundation
import ScreenCaptureKit

/// Queries ScreenCaptureKit for capturable displays/windows and normalizes them into picker-ready targets.
public enum ShareableContentService {
    /// Minimum window edge in points for the window picker — filters out tooltips, badges, and other UI debris.
    static let minimumWindowEdge: CGFloat = 50

    public static func currentContent() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    /// Screen-recording permission probe (task 9.1): the shareable-content call fails when TCC permission is missing.
    public static func hasScreenRecordingPermission() async -> Bool {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return true
        } catch {
            return false
        }
    }

    public static func displayTargets(from content: SCShareableContent) -> [DisplayTarget] {
        content.displays.map { display in
            let mode = CGDisplayCopyDisplayMode(display.displayID)
            return DisplayTarget(
                displayID: display.displayID,
                frame: display.frame,
                pixelWidth: mode?.pixelWidth ?? display.width,
                pixelHeight: mode?.pixelHeight ?? display.height
            )
        }
    }

    /// Picker-ready windows: on-screen, normal layer, meaningfully sized, not our own process.
    public static func windowTargets(from content: SCShareableContent) -> [WindowTarget] {
        let ownPID = getpid()
        return content.windows.compactMap { window in
            guard window.isOnScreen,
                  window.windowLayer == 0,
                  window.frame.width >= minimumWindowEdge,
                  window.frame.height >= minimumWindowEdge,
                  let app = window.owningApplication,
                  app.processID != ownPID
            else { return nil }
            return WindowTarget(
                windowID: window.windowID,
                title: window.title?.isEmpty == false ? window.title : nil,
                appName: app.applicationName.isEmpty ? nil : app.applicationName,
                appBundleID: app.bundleIdentifier.isEmpty ? nil : app.bundleIdentifier,
                appPID: app.processID,
                frame: window.frame
            )
        }
        .sorted { lhs, rhs in
            (lhs.appName ?? "") < (rhs.appName ?? "")
        }
    }
}
