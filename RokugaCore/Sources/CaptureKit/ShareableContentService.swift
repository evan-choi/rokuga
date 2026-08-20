import ScreenCaptureKit

/// Queries ScreenCaptureKit for capturable content and recording permission.
public enum ShareableContentService {
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
}
