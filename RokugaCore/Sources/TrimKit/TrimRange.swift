import CoreMedia
import Foundation

/// The keep-range selected in the trim editor.
public struct TrimRange: Equatable, Sendable {
    public var start: CMTime
    public var end: CMTime

    public init(start: CMTime, end: CMTime) {
        self.start = start
        self.end = end
    }

    public var duration: CMTime {
        CMTimeSubtract(end, start)
    }

    public var timeRange: CMTimeRange {
        CMTimeRange(start: start, duration: duration)
    }

    /// Clamp to the asset duration and enforce start < end.
    public func clamped(toAssetDuration assetDuration: CMTime) -> TrimRange {
        let clampedStart = CMTimeClampToRange(start, range: CMTimeRange(start: .zero, duration: assetDuration))
        let clampedEnd = CMTimeClampToRange(end, range: CMTimeRange(start: .zero, duration: assetDuration))
        guard CMTimeCompare(clampedStart, clampedEnd) < 0 else {
            return TrimRange(start: .zero, end: assetDuration)
        }
        return TrimRange(start: clampedStart, end: clampedEnd)
    }
}
