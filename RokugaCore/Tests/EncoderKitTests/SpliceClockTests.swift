import CoreMedia
import XCTest
@testable import EncoderKit

final class SpliceClockTests: XCTestCase {
    private func time(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 600)
    }

    func testNoPauseIsIdentity() {
        var clock = SpliceClock()
        for frame in 0..<10 {
            let pts = time(Double(frame) / 60.0)
            XCTAssertEqual(clock.adjusted(pts), pts)
            clock.observe(pts: pts, duration: time(1.0 / 60.0))
        }
    }

    func testPauseGapIsRemoved() {
        var clock = SpliceClock()
        let frameDuration = time(1.0 / 60.0)

        var lastAdjusted = CMTime.zero
        for frame in 0..<60 {
            let pts = time(Double(frame) / 60.0)
            lastAdjusted = clock.adjusted(pts)
            clock.observe(pts: pts, duration: frameDuration)
        }

        clock.markPaused()

        // Capture resumes 5 seconds of wall time later.
        let resumePTS = time(1.0 + 5.0)
        let adjusted = clock.adjusted(resumePTS)
        let delta = CMTimeSubtract(adjusted, lastAdjusted).seconds
        XCTAssertEqual(delta, 1.0 / 60.0, accuracy: 0.001, "output timeline must continue gaplessly")
    }

    func testSharedOffsetKeepsAVSync() {
        var clock = SpliceClock()
        let frameDuration = time(1.0 / 60.0)

        let videoPTS = time(1.0)
        _ = clock.adjusted(videoPTS)
        clock.observe(pts: videoPTS, duration: frameDuration)

        clock.markPaused()

        let resumeVideoPTS = time(4.0)
        let adjustedVideo = clock.adjusted(resumeVideoPTS)
        clock.observe(pts: resumeVideoPTS, duration: frameDuration)

        // Audio arriving right after resume gets the identical offset.
        let audioPTS = time(4.01)
        let adjustedAudio = clock.adjusted(audioPTS)
        let sourceDelta = CMTimeSubtract(audioPTS, resumeVideoPTS).seconds
        let adjustedDelta = CMTimeSubtract(adjustedAudio, adjustedVideo).seconds
        XCTAssertEqual(sourceDelta, adjustedDelta, accuracy: 0.0001)
    }

    func testMultiplePauses() {
        var clock = SpliceClock()
        let frameDuration = CMTime(value: 1, timescale: 30)
        var sourceFrame: CMTimeValue = 0
        var previousAdjusted: CMTime?

        for _ in 0..<3 {
            for _ in 0..<30 {
                let pts = CMTime(value: sourceFrame, timescale: 30)
                let adjusted = clock.adjusted(pts)
                if let previousAdjusted {
                    let delta = CMTimeSubtract(adjusted, previousAdjusted)
                    XCTAssertEqual(delta, frameDuration)
                }
                previousAdjusted = adjusted
                clock.observe(pts: pts, duration: frameDuration)
                sourceFrame += 1
            }
            clock.markPaused()
            sourceFrame += 225
        }
    }
}
