import CoreMedia
import CoreVideo
import XCTest
@testable import EffectsKit

final class FrameBudgetMonitorTests: XCTestCase {
    func testStaysAtFullLevelUnderBudget() {
        let monitor = FrameBudgetMonitor(budgetSeconds: 0.002, windowSize: 10)
        for _ in 0 ..< 50 {
            monitor.record(frameSeconds: 0.0005)
        }
        XCTAssertEqual(monitor.currentLevel, .full)
    }

    func testDegradesStepwiseWhenOverBudget() {
        let monitor = FrameBudgetMonitor(budgetSeconds: 0.002, windowSize: 10)
        for _ in 0 ..< 10 {
            monitor.record(frameSeconds: 0.01)
        }
        XCTAssertEqual(monitor.currentLevel, .noHighlight)
        for _ in 0 ..< 10 {
            monitor.record(frameSeconds: 0.01)
        }
        XCTAssertEqual(monitor.currentLevel, .cursorOnly)
    }

    func testNeverRecoversWithinRecording() {
        let monitor = FrameBudgetMonitor(budgetSeconds: 0.002, windowSize: 5)
        for _ in 0 ..< 5 {
            monitor.record(frameSeconds: 0.01)
        }
        XCTAssertEqual(monitor.currentLevel, .noHighlight)
        for _ in 0 ..< 100 {
            monitor.record(frameSeconds: 0.0001)
        }
        XCTAssertEqual(monitor.currentLevel, .noHighlight)
    }
}

final class CursorEffectOptionsTests: XCTestCase {
    func testSystemPointerRemainsNativeWhenHighlightNeedsCompositing() {
        let options = CursorEffectOptions(showCursor: true, pointerStyle: .system, highlight: true, animateClicks: false)

        XCTAssertTrue(options.usesNativeSystemCursor)
        XCTAssertFalse(options.compositesPointer)
        XCTAssertTrue(options.needsCompositor)
        XCTAssertFalse(options.isPassthrough)
    }

    func testNativeClickEffectsBypassCompositor() {
        let options = CursorEffectOptions(showCursor: false, pointerStyle: .system, highlight: false, animateClicks: true)

        XCTAssertFalse(options.usesNativeSystemCursor)
        XCTAssertFalse(options.needsCompositor)
        XCTAssertTrue(options.isPassthrough)
    }

    func testDotPointerHasSingleEffectsKitOwner() {
        let options = CursorEffectOptions(showCursor: true, pointerStyle: .dot, highlight: false, animateClicks: false)

        XCTAssertFalse(options.usesNativeSystemCursor)
        XCTAssertTrue(options.compositesPointer)
        XCTAssertTrue(options.needsCompositor)
    }

    func testHiddenCursorWithoutEffectsBypassesCompositor() {
        let options = CursorEffectOptions(showCursor: false, pointerStyle: .system, highlight: false, animateClicks: false)

        XCTAssertFalse(options.usesNativeSystemCursor)
        XCTAssertTrue(options.isPassthrough)
    }
}

final class FrameGeometryTests: XCTestCase {
    func testMapsGlobalPointIntoFramePixels() {
        let geometry = FrameGeometry(
            contentRect: CGRect(x: 100, y: 50, width: 800, height: 600),
            pixelSize: CGSize(width: 1600, height: 1200)
        )
        let pixel = geometry.pixelPosition(of: CGPoint(x: 500, y: 350))
        XCTAssertEqual(pixel?.x ?? -1, 800, accuracy: 0.001)
        XCTAssertEqual(pixel?.y ?? -1, 600, accuracy: 0.001)
        XCTAssertEqual(geometry.scale, 2, accuracy: 0.001)
    }

    func testPointsFarOutsideFrameReturnNil() {
        let geometry = FrameGeometry(
            contentRect: CGRect(x: 0, y: 0, width: 100, height: 100),
            pixelSize: CGSize(width: 100, height: 100)
        )
        XCTAssertNil(geometry.pixelPosition(of: CGPoint(x: 500, y: 500)))
    }

    func testMapsNonUniformlyScaledWindowAfterResize() {
        let geometry = FrameGeometry(
            contentRect: CGRect(x: 200, y: 300, width: 100, height: 50),
            pixelSize: CGSize(width: 240, height: 280),
            pixelContentRect: CGRect(x: 20, y: 40, width: 200, height: 200)
        )

        let pixel = geometry.pixelPosition(of: CGPoint(x: 250, y: 325))
        XCTAssertEqual(pixel?.x ?? -1, 120, accuracy: 0.001)
        XCTAssertEqual(pixel?.y ?? -1, 140, accuracy: 0.001)
    }
}

final class CursorStateSamplerTests: XCTestCase {
    private final class SampleSource: @unchecked Sendable {
        private let lock = NSLock()
        private var _location = CGPoint.zero

        var location: CGPoint {
            get { lock.withLock { _location } }
            set { lock.withLock { _location = newValue } }
        }
    }

    func testSamplesPositionAtConfiguredRate() {
        let source = SampleSource()
        source.location = CGPoint(x: 320, y: 240)
        let sampler = CursorStateSampler(
            framesPerSecond: 60,
            locationProvider: { source.location }
        )

        sampler.sampleNow()
        let snapshot = sampler.snapshot()

        XCTAssertEqual(sampler.samplingInterval, 1.0 / 60.0, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.location, source.location)
    }
}

final class CursorCompositorTests: XCTestCase {
    private struct FakeSampler: CursorStateSampling {
        let sampledSnapshot: CursorSnapshot
        func snapshot() -> CursorSnapshot {
            sampledSnapshot
        }
    }

    func testPassthroughOptionsReturnOriginalBuffer() throws {
        let options = CursorEffectOptions(showCursor: true, pointerStyle: .system, highlight: false, animateClicks: false)
        let compositor = CursorCompositor(
            options: options,
            geometry: FrameGeometry(contentRect: CGRect(x: 0, y: 0, width: 64, height: 64), pixelSize: CGSize(width: 64, height: 64)),
            sampler: FakeSampler(sampledSnapshot: CursorSnapshot(location: .zero))
        )
        let input = try makeSampleBuffer(width: 64, height: 64)
        let output = compositor.composite(input)
        XCTAssertTrue(output === input)
    }

    func testDotCursorChangesPixelsAtCursorLocation() throws {
        let options = CursorEffectOptions(showCursor: true, pointerStyle: .dot, highlight: false, animateClicks: false)
        let compositor = CursorCompositor(
            options: options,
            geometry: FrameGeometry(contentRect: CGRect(x: 0, y: 0, width: 128, height: 128), pixelSize: CGSize(width: 128, height: 128)),
            sampler: FakeSampler(sampledSnapshot: CursorSnapshot(location: CGPoint(x: 64, y: 64)))
        )
        let input = try makeSampleBuffer(width: 128, height: 128)
        let output = compositor.composite(input)
        XCTAssertFalse(output === input)

        guard let pixels = CMSampleBufferGetImageBuffer(output) else {
            return XCTFail("no image buffer")
        }
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixels)?.assumingMemoryBound(to: UInt8.self))
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixels)
        let center = base + 64 * bytesPerRow + 64 * 4
        let red = center[2]
        XCTAssertGreaterThan(red, 128, "dot cursor should paint red at the cursor pixel")
    }

    func testCompositingPreservesBasePixelsOutsideOverlay() throws {
        let compositor = CursorCompositor(
            options: CursorEffectOptions(
                showCursor: true,
                pointerStyle: .dot,
                highlight: false,
                animateClicks: false
            ),
            geometry: FrameGeometry(
                contentRect: CGRect(x: 0, y: 0, width: 128, height: 128),
                pixelSize: CGSize(width: 128, height: 128)
            ),
            sampler: FakeSampler(sampledSnapshot: CursorSnapshot(location: CGPoint(x: 64, y: 64)))
        )
        let input = try makeSampleBuffer(width: 128, height: 128)
        let inputPixels = try XCTUnwrap(CMSampleBufferGetImageBuffer(input))
        CVPixelBufferLockBaseAddress(inputPixels, [])
        let inputBase = try XCTUnwrap(CVPixelBufferGetBaseAddress(inputPixels)?.assumingMemoryBound(to: UInt8.self))
        inputBase[0] = 25
        inputBase[1] = 128
        inputBase[2] = 230
        inputBase[3] = 255
        CVPixelBufferUnlockBaseAddress(inputPixels, [])

        let output = compositor.composite(input)
        let outputPixels = try XCTUnwrap(CMSampleBufferGetImageBuffer(output))
        CVPixelBufferLockBaseAddress(outputPixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(outputPixels, .readOnly) }
        let outputBase = try XCTUnwrap(CVPixelBufferGetBaseAddress(outputPixels)?.assumingMemoryBound(to: UInt8.self))

        XCTAssertEqual(Array(UnsafeBufferPointer(start: outputBase, count: 4)), [25, 128, 230, 255])
    }

    func testPerFrameWindowGeometryPlacesDotInsideSurfaceContentRect() throws {
        let options = CursorEffectOptions(showCursor: true, pointerStyle: .dot, highlight: false, animateClicks: false)
        let snapshot = CursorSnapshot(
            location: CGPoint(x: 250, y: 350)
        )
        let overlays = CursorOverlayRenderer.render(
            snapshot: snapshot,
            options: options,
            geometry: FrameGeometry(
                contentRect: CGRect(x: 200, y: 300, width: 100, height: 100),
                pixelSize: CGSize(width: 140, height: 180),
                pixelContentRect: CGRect(x: 20, y: 40, width: 100, height: 100)
            ),
            level: .full
        )

        let cursor = try XCTUnwrap(overlays.first)
        XCTAssertEqual(cursor.rect.midX, 70, accuracy: 0.001)
        XCTAssertEqual(cursor.rect.midY, 90, accuracy: 0.001)
    }

    func testCursorTileFitsRenderedEffects() throws {
        let overlays = CursorOverlayRenderer.render(
            snapshot: CursorSnapshot(location: CGPoint(x: 64, y: 64)),
            options: CursorEffectOptions(
                showCursor: true,
                pointerStyle: .dot,
                highlight: true,
                animateClicks: false
            ),
            geometry: FrameGeometry(
                contentRect: CGRect(x: 0, y: 0, width: 128, height: 128),
                pixelSize: CGSize(width: 256, height: 256)
            ),
            level: .full
        )

        let cursor = try XCTUnwrap(overlays.first)
        XCTAssertEqual(cursor.image.width, 96)
        XCTAssertEqual(cursor.image.height, 96)
    }

    func testBudgetExhaustionKeepsDotVisibleAndSignalsCursorOnlyOnce() throws {
        let options = CursorEffectOptions(showCursor: true, pointerStyle: .dot, highlight: true, animateClicks: true)
        let budget = FrameBudgetMonitor(budgetSeconds: 0.000000001, windowSize: 1)
        for _ in 0 ..< 3 {
            budget.record(frameSeconds: 1)
        }
        XCTAssertEqual(budget.currentLevel, .cursorOnly)

        let expectation = expectation(description: "fallback")
        expectation.expectedFulfillmentCount = 1
        let compositor = CursorCompositor(
            options: options,
            geometry: FrameGeometry(contentRect: CGRect(x: 0, y: 0, width: 64, height: 64), pixelSize: CGSize(width: 64, height: 64)),
            sampler: FakeSampler(sampledSnapshot: CursorSnapshot(location: CGPoint(x: 32, y: 32))),
            budget: budget,
            onDegradeToCursorOnly: { expectation.fulfill() }
        )
        let input = try makeSampleBuffer(width: 64, height: 64)
        XCTAssertFalse(compositor.composite(input) === input)
        XCTAssertFalse(compositor.composite(input) === input)
        wait(for: [expectation], timeout: 1)
    }

    func testCompositedFramePropagatesColorAttachments() throws {
        let options = CursorEffectOptions(showCursor: true, pointerStyle: .dot, highlight: false, animateClicks: false)
        let compositor = CursorCompositor(
            options: options,
            geometry: FrameGeometry(contentRect: CGRect(x: 0, y: 0, width: 128, height: 128), pixelSize: CGSize(width: 128, height: 128)),
            sampler: FakeSampler(sampledSnapshot: CursorSnapshot(location: CGPoint(x: 64, y: 64)))
        )
        let input = try makeSampleBuffer(width: 128, height: 128)
        let inputPixels = try XCTUnwrap(CMSampleBufferGetImageBuffer(input))
        CVBufferSetAttachment(
            inputPixels,
            kCVImageBufferColorPrimariesKey,
            kCVImageBufferColorPrimaries_ITU_R_709_2,
            .shouldPropagate
        )
        CVBufferSetAttachment(
            inputPixels,
            kCVImageBufferTransferFunctionKey,
            kCVImageBufferTransferFunction_sRGB,
            .shouldPropagate
        )

        let output = compositor.composite(input)
        XCTAssertFalse(output === input)
        let outputPixels = try XCTUnwrap(CMSampleBufferGetImageBuffer(output))

        XCTAssertEqual(
            CVBufferCopyAttachment(outputPixels, kCVImageBufferColorPrimariesKey, nil) as? String,
            kCVImageBufferColorPrimaries_ITU_R_709_2 as String
        )
        XCTAssertEqual(
            CVBufferCopyAttachment(outputPixels, kCVImageBufferTransferFunctionKey, nil) as? String,
            kCVImageBufferTransferFunction_sRGB as String
        )
    }

    private func makeSampleBuffer(width: Int, height: Int) throws -> CMSampleBuffer {
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, [
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ] as CFDictionary, &pixelBuffer)
        let buffer = try XCTUnwrap(pixelBuffer)
        CVPixelBufferLockBaseAddress(buffer, [])
        memset(CVPixelBufferGetBaseAddress(buffer), 0, CVPixelBufferGetDataSize(buffer))
        CVPixelBufferUnlockBaseAddress(buffer, [])

        var formatDescription: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: buffer, formatDescriptionOut: &formatDescription)
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 60),
            presentationTimeStamp: .zero,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        try CMSampleBufferCreateForImageBuffer(
            allocator: nil,
            imageBuffer: buffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: XCTUnwrap(formatDescription),
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        return try XCTUnwrap(sampleBuffer)
    }
}
