import CoreGraphics
import Foundation

/// Registry of window IDs that must never appear in a recording (countdown overlay, region-selection overlay, toolbar, floating thumbnail).
/// UI layers register their windows here; the content-filter builder excludes them unconditionally, independent of the user's own-windows toggle.
public final class CaptureExcludedWindows: @unchecked Sendable {
    public static let shared = CaptureExcludedWindows()

    private let lock = NSLock()
    private var windowIDs: Set<CGWindowID> = []

    public init() {}

    public func register(_ windowID: CGWindowID) {
        lock.withLock { _ = windowIDs.insert(windowID) }
    }

    public func unregister(_ windowID: CGWindowID) {
        lock.withLock { _ = windowIDs.remove(windowID) }
    }

    public var all: Set<CGWindowID> {
        lock.withLock { windowIDs }
    }
}
