import CoreMedia
import Foundation

/// Rewrites presentation timestamps across pause/resume splices so the output timeline is gapless while A/V sync is preserved (task 3.2).
/// One shared instance retimes every track: the accumulated offset is identical for video and audio.
public struct SpliceClock: Sendable {
    private(set) var accumulatedOffset: CMTime = .zero
    private var lastSourcePTS: CMTime?
    private var lastDuration: CMTime = CMTime(value: 1, timescale: 60)
    private var awaitingResumeAnchor = false

    public init() {}

    public mutating func markPaused() {
        awaitingResumeAnchor = true
    }

    /// Map a source PTS to the gapless output timeline.
    public mutating func adjusted(_ pts: CMTime) -> CMTime {
        if awaitingResumeAnchor, let lastSourcePTS {
            let gap = CMTimeSubtract(CMTimeSubtract(pts, lastSourcePTS), lastDuration)
            if CMTimeCompare(gap, .zero) > 0 {
                accumulatedOffset = CMTimeAdd(accumulatedOffset, gap)
            }
        }
        awaitingResumeAnchor = false
        return CMTimeSubtract(pts, accumulatedOffset)
    }

    /// Record source timing after appending so the next splice can measure its gap.
    public mutating func observe(pts: CMTime, duration: CMTime) {
        if lastSourcePTS.map({ CMTimeCompare(pts, $0) > 0 }) ?? true {
            lastSourcePTS = pts
            if duration.isValid, CMTimeCompare(duration, .zero) > 0 {
                lastDuration = duration
            }
        }
    }
}
