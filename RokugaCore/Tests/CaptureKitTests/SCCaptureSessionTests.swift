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
    func testCaptureMetricsCountsGapsDuplicatesAndCompositeTime() {
        let metrics = CaptureMetrics(frameRate: 60)

        metrics.recordVideoCallback()
        metrics.recordCompleteVideoFrame(pts: .zero, compositeSeconds: 0.001)
        metrics.recordVideoCallback()
        metrics.recordCompleteVideoFrame(pts: .zero, compositeSeconds: 0.002)
        metrics.recordVideoCallback()
        metrics.recordCompleteVideoFrame(pts: CMTime(seconds: 0.1, preferredTimescale: 600), compositeSeconds: nil)
        metrics.recordIncompleteVideoFrame()
        metrics.recordInvalidSample()
        metrics.recordAudioCallback()
        metrics.recordEffectDegradation()

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
        XCTAssertEqual(snapshot.compositeCalls, 2)
        XCTAssertEqual(snapshot.compositeSeconds, 0.003, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.effectDegradations, 1)
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

    func testSystemPointerRemainsNativeWhenEffectsAreEnabled() {
        withSettings { settings in
            settings.showCursor = true
            settings.pointerStyle = .system
            settings.highlightCursor = true
            settings.animateClicks = true

            let configuration = CaptureConfiguration.fromSettings(settings)

            XCTAssertTrue(configuration.showsCursor)
            XCTAssertTrue(configuration.cursorEffects.needsCompositor)
        }
    }

    func testDotPointerDisablesNativeCursorAndKeepsCompositor() {
        withSettings { settings in
            settings.showCursor = true
            settings.pointerStyle = .dot
            settings.highlightCursor = false
            settings.animateClicks = false

            let configuration = CaptureConfiguration.fromSettings(settings)

            XCTAssertFalse(configuration.showsCursor)
            XCTAssertTrue(configuration.cursorEffects.compositesPointer)
            XCTAssertTrue(configuration.cursorEffects.needsCompositor)
        }
    }

    func testHiddenPointerDisablesBothCursorOwners() {
        withSettings { settings in
            settings.showCursor = false
            settings.pointerStyle = .system
            settings.highlightCursor = false
            settings.animateClicks = false

            let configuration = CaptureConfiguration.fromSettings(settings)

            XCTAssertFalse(configuration.showsCursor)
            XCTAssertFalse(configuration.cursorEffects.needsCompositor)
        }
    }

    func testFrameMetadataTracksMovingWindowAndSurfacePlacement() throws {
        let frameInfo: [SCStreamFrameInfo: Any] = [
            .screenRect: CGRect(x: 120, y: 80, width: 640, height: 480),
            .contentRect: CGRect(x: 10, y: 20, width: 320, height: 240),
            .scaleFactor: CGFloat(2)
        ]

        let geometry = try XCTUnwrap(SCCaptureSession.frameGeometry(
            frameInfo: frameInfo,
            pixelSize: CGSize(width: 800, height: 600)
        ))

        XCTAssertEqual(geometry.contentRect, CGRect(x: 120, y: 80, width: 640, height: 480))
        XCTAssertEqual(geometry.pixelContentRect, CGRect(x: 20, y: 40, width: 640, height: 480))
        XCTAssertEqual(
            geometry.pixelPosition(of: CGPoint(x: 440, y: 320)),
            CGPoint(x: 340, y: 280)
        )
    }

    private func withSettings(_ body: (SettingsStore) -> Void) {
        let suiteName = "SCCaptureSessionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        body(SettingsStore(defaults: defaults))
    }
}
