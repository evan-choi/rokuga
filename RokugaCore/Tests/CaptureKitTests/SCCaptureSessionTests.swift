import CoreGraphics
import CoreMedia
import EncoderKit
import Foundation
import ScreenCaptureKit
import SettingsKit
import XCTest
@testable import CaptureKit

private struct NullSink: MediaSink {
    func start() async throws {}
    func append(_ sampleBuffer: CMSampleBuffer, of kind: MediaKind) {}
    func markPaused() {}
    func markResumed() {}
    func finish() async throws -> URL {
        URL(fileURLWithPath: "/dev/null")
    }

    func cancel() async {}
}

final class SCCaptureSessionTests: XCTestCase {
    func testCaptureMetricsCountsGapsAndDuplicates() {
        let metrics = CaptureMetrics(frameRate: 60)

        metrics.recordVideoCallback()
        metrics.recordCompleteVideoFrame(pts: .zero)
        metrics.recordVideoCallback()
        metrics.recordCompleteVideoFrame(pts: .zero)
        metrics.recordVideoCallback()
        metrics.recordCompleteVideoFrame(pts: CMTime(seconds: 0.1, preferredTimescale: 600))
        metrics.recordIncompleteVideoFrame()
        metrics.recordInvalidSample()
        metrics.recordAudioCallback()

        let snapshot = metrics.currentSnapshot()
        XCTAssertEqual(snapshot.videoCallbacks, 3)
        XCTAssertEqual(snapshot.completeVideoFrames, 3)
        XCTAssertEqual(snapshot.incompleteVideoFrames, 1)
        XCTAssertEqual(snapshot.invalidSamples, 1)
        XCTAssertEqual(snapshot.audioCallbacks, 1)
        XCTAssertEqual(snapshot.duplicatePTS, 1)
        XCTAssertEqual(snapshot.gapPTS, 1)
        XCTAssertEqual(snapshot.missingVideoFrames, 5)
        XCTAssertEqual(snapshot.maxPTSGapSeconds, 0.1, accuracy: 0.001)
        XCTAssertNotNil(snapshot.firstCompleteFrameUptimeNanoseconds)
    }

    func testStreamConfigurationCapturesSRGBWithBGRAFormat() {
        withSettings { settings in
            let session = SCCaptureSession(
                target: .display(
                    DisplayTarget(
                        displayID: 1,
                        frame: CGRect(x: 0, y: 0, width: 800, height: 600),
                        pixelWidth: 1600,
                        pixelHeight: 1200
                    ),
                    crop: nil
                ),
                configuration: CaptureConfiguration.fromSettings(settings, frameRate: 144),
                sink: NullSink(),
                onInterruption: { _ in }
            )

            let config = session.makeStreamConfiguration()

            XCTAssertEqual(config.pixelFormat, kCVPixelFormatType_32BGRA)
            XCTAssertEqual(config.colorSpaceName as String, CGColorSpace.sRGB as String)
            XCTAssertEqual(config.width, 1600)
            XCTAssertEqual(config.height, 1200)
            XCTAssertEqual(config.minimumFrameInterval, CMTime(value: 1, timescale: 144))
        }
    }

    func testStreamConfigurationUsesNativeClickEffects() throws {
        guard #available(macOS 15.0, *) else {
            throw XCTSkip("ScreenCaptureKit native click effects require macOS 15")
        }

        withSettings { settings in
            settings.showCursor = false
            settings.animateClicks = true
            let configuration = CaptureConfiguration.fromSettings(settings)
            let session = SCCaptureSession(
                target: .display(
                    DisplayTarget(
                        displayID: 1,
                        frame: CGRect(x: 0, y: 0, width: 800, height: 600),
                        pixelWidth: 1600,
                        pixelHeight: 1200
                    ),
                    crop: nil
                ),
                configuration: configuration,
                sink: NullSink(),
                onInterruption: { _ in }
            )

            let config = session.makeStreamConfiguration()

            XCTAssertFalse(config.showsCursor)
            XCTAssertTrue(config.showMouseClicks)
        }
    }

    func testSystemPointerAndClickIndicatorUseNativeConfiguration() {
        withSettings { settings in
            settings.showCursor = true
            settings.animateClicks = true

            let configuration = CaptureConfiguration.fromSettings(settings)

            XCTAssertTrue(configuration.showsCursor)
            XCTAssertTrue(configuration.showMouseClicks)
        }
    }

    func testCursorAndClickIndicatorCanBeDisabledIndependently() {
        withSettings { settings in
            settings.showCursor = false
            settings.animateClicks = false

            let configuration = CaptureConfiguration.fromSettings(settings)

            XCTAssertFalse(configuration.showsCursor)
            XCTAssertFalse(configuration.showMouseClicks)
        }
    }

    private func withSettings(_ body: (SettingsStore) -> Void) {
        let suiteName = "SCCaptureSessionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        body(SettingsStore(defaults: defaults))
    }
}
