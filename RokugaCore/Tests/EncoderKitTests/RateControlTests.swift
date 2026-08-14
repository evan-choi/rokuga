import XCTest
@testable import EncoderKit

final class RateControlTests: XCTestCase {
    func testBitrateIsMonotonicInQuality() {
        var previous = 0
        for quality in stride(from: 0, through: 100, by: 10) {
            let bitrate = RateControl.averageVideoBitrate(
                width: 1920, height: 1080, fps: 60, quality: quality, codec: .h264
            )
            XCTAssertGreaterThan(bitrate, previous)
            previous = bitrate
        }
    }

    func testHEVCUsesLowerRateThanH264() {
        let h264 = RateControl.averageVideoBitrate(width: 3840, height: 2160, fps: 60, quality: 80, codec: .h264)
        let hevc = RateControl.averageVideoBitrate(width: 3840, height: 2160, fps: 60, quality: 80, codec: .hevc)
        XCTAssertLessThan(hevc, h264)
        XCTAssertEqual(Double(hevc) / Double(h264), 0.65, accuracy: 0.01)
    }

    func testDefaultQuality1080p60LandsInSaneRange() {
        let bitrate = RateControl.averageVideoBitrate(width: 1920, height: 1080, fps: 60, quality: 80, codec: .h264)
        XCTAssertGreaterThan(bitrate, 5_000_000)
        XCTAssertLessThan(bitrate, 30_000_000)
    }

    func testDataRateLimitsShape() {
        let limits = RateControl.dataRateLimits(averageBitrate: 8_000_000)
        XCTAssertEqual(limits.count, 2)
        XCTAssertEqual(limits[0].intValue, Int(8_000_000 * 1.1 / 8.0))
        XCTAssertEqual(limits[1].doubleValue, 1.0)
    }
}
