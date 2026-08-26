import CoreGraphics
import ScreenCaptureKit

/// Queries ScreenCaptureKit for capturable content and recording permission.
public enum ShareableContentService {
    public static func currentContent() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    /// Checks screen-recording permission without prompting the user.
    public static func hasScreenRecordingPermission() async -> Bool {
        CGPreflightScreenCaptureAccess()
    }
}
