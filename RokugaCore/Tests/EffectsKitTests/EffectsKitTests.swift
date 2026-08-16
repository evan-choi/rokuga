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
        XCTAssertEqual(monitor.currentLevel, .noClickAnimations)
        for _ in 0 ..< 10 {
            monitor.record(frameSeconds: 0.01)
        }
        XCTAssertEqual(monitor.currentLevel, .noHighlight)
        for _ in 0 ..< 10 {
            monitor.record(frameSeconds: 0.01)
        }
        XCTAssertEqual(monitor.currentLevel, .nativeCursor)
    }

    func testNeverRecoversWithinRecording() {
        let monitor = FrameBudgetMonitor(budgetSeconds: 0.002, windowSize: 5)
        for _ in 0 ..< 5 {
            monitor.record(frameSeconds: 0.01)
        }
        XCTAssertEqual(monitor.currentLevel, .noClickAnimations)
        for _ in 0 ..< 100 {
            monitor.record(frameSeconds: 0.0001)
        }
        XCTAssertEqual(monitor.currentLevel, .noClickAnimations)
    }
}

final class ClickRippleTests: XCTestCase {
    func testActiveClicksProduceProgress() {
        let now: TimeInterval = 100
        let clicks: [(time: TimeInterval, location: CGPoint)] = [
            (time: 99.9, location: CGPoint(x: 5, y: 5)),
            (time: 99.75, location: CGPoint(x: 8, y: 8))
        ]
        let progresses = ClickRipple.progresses(clicks: clicks, now: now)
        XCTAssertEqual(progresses.count, 2)
        XCTAssertEqual(progresses[0].progress, 0.2, accuracy: 0.001)
        XCTAssertEqual(progresses[1].progress, 0.5, accuracy: 0.001)
    }

    func testExpiredAndFutureClicksAreDropped() {
        let now: TimeInterval = 100
        let clicks: [(time: TimeInterval, location: CGPoint)] = [
            (time: 99.0, location: .zero),
            (time: 101.0, location: .zero)
        ]
        XCTAssertTrue(ClickRipple.progresses(clicks: clicks, now: now).isEmpty)
    }

    func testRingUsesCompactSizeAndHoldsBeforeFading() {
        XCTAssertEqual(ClickRipple.radius * 2, 80, accuracy: 0.001)
        XCTAssertEqual(ClickRipple.opacity(at: 0), 1, accuracy: 0.001)
        XCTAssertEqual(ClickRipple.opacity(at: 0.4), 1, accuracy: 0.001)
        XCTAssertEqual(ClickRipple.opacity(at: 0.7), 0.5, accuracy: 0.001)
        XCTAssertEqual(ClickRipple.opacity(at: 1), 0, accuracy: 0.001)
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
            sampler: FakeSampler(sampledSnapshot: CursorSnapshot(location: .zero, image: nil))
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
            sampler: FakeSampler(sampledSnapshot: CursorSnapshot(location: CGPoint(x: 64, y: 64), image: nil))
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

    func testClickRingUsesAntialiasedBlackAndWhiteStrokes() throws {
        let options = CursorEffectOptions(showCursor: false, pointerStyle: .system, highlight: false, animateClicks: true)
        let geometry = FrameGeometry(
            contentRect: CGRect(x: 0, y: 0, width: 256, height: 256),
            pixelSize: CGSize(width: 256, height: 256)
        )
        let snapshot = CursorSnapshot(
            location: CGPoint(x: 128, y: 128),
            image: nil,
            clicks: [(time: 99.9, location: CGPoint(x: 128, y: 128))]
        )

        let overlays = CursorOverlayRenderer.render(
            snapshot: snapshot,
            options: options,
            geometry: geometry,
            level: .full,
            now: 100
        )
        let overlay = try XCTUnwrap(overlays.first)
        let data = try XCTUnwrap(overlay.image.dataProvider?.data as Data?)
        let centerOffset = (overlay.image.height / 2) * overlay.image.bytesPerRow + (overlay.image.width / 2) * 4

        var hasBlack = false
        var hasWhite = false
        var hasAntialiasedEdge = false
        var radialBands: [Int] = []
        data.withUnsafeBytes { bytes in
            let pixels = bytes.bindMemory(to: UInt8.self)
            for offset in stride(from: 0, to: pixels.count, by: 4) {
                let blue = pixels[offset]
                let green = pixels[offset + 1]
                let red = pixels[offset + 2]
                let alpha = pixels[offset + 3]
                hasBlack = hasBlack || (alpha > 240 && red < 16 && green < 16 && blue < 16)
                hasWhite = hasWhite || (alpha > 240 && red > 240 && green > 240 && blue > 240)
                hasAntialiasedEdge = hasAntialiasedEdge || (alpha > 0 && alpha < 240)
            }

            let centerRow = (overlay.image.height / 2) * overlay.image.bytesPerRow
            for x in 0 ..< (overlay.image.width / 2) {
                let offset = centerRow + x * 4
                let blue = pixels[offset]
                let green = pixels[offset + 1]
                let red = pixels[offset + 2]
                let alpha = pixels[offset + 3]
                let band: Int = if alpha > 200, red > 200, green > 200, blue > 200 {
                    1
                } else if alpha > 200, red < 32, green < 32, blue < 32 {
                    -1
                } else {
                    0
                }
                if band != 0, radialBands.last != band {
                    radialBands.append(band)
                }
            }
        }

        XCTAssertTrue(hasBlack, "click ring should include an opaque black outer stroke")
        XCTAssertTrue(hasWhite, "click ring should include an opaque white outline")
        XCTAssertTrue(hasAntialiasedEdge, "click ring edge should contain partially covered pixels")
        XCTAssertEqual(Array(radialBands.prefix(3)), [1, -1, 1], "click ring should be white-black-white from edge to center")
        XCTAssertEqual(data[centerOffset + 3], 0, "click ring should not fill its center")
    }

    func testOnlyLatestClickRingRemainsAfterCursorLeavesFrame() throws {
        let options = CursorEffectOptions(showCursor: false, pointerStyle: .system, highlight: false, animateClicks: true)
        let geometry = FrameGeometry(
            contentRect: CGRect(x: 0, y: 0, width: 256, height: 256),
            pixelSize: CGSize(width: 256, height: 256)
        )
        let snapshot = CursorSnapshot(
            location: CGPoint(x: 1000, y: 1000),
            image: nil,
            clicks: [
                (time: 99.8, location: CGPoint(x: 64, y: 64)),
                (time: 99.9, location: CGPoint(x: 128, y: 128))
            ]
        )

        let overlays = CursorOverlayRenderer.render(
            snapshot: snapshot,
            options: options,
            geometry: geometry,
            level: .full,
            now: 100
        )

        let clickOverlay = try XCTUnwrap(overlays.first)
        XCTAssertEqual(overlays.count, 1)
        XCTAssertEqual(clickOverlay.rect.midX, 128, accuracy: 0.001)
        XCTAssertEqual(clickOverlay.rect.midY, 128, accuracy: 0.001)
    }

    func testBudgetExhaustionTriggersNativeFallbackOnce() throws {
        let options = CursorEffectOptions(showCursor: true, pointerStyle: .dot, highlight: true, animateClicks: true)
        let budget = FrameBudgetMonitor(budgetSeconds: 0.000000001, windowSize: 1)
        for _ in 0 ..< 3 {
            budget.record(frameSeconds: 1)
        }
        XCTAssertEqual(budget.currentLevel, .nativeCursor)

        let expectation = expectation(description: "fallback")
        expectation.expectedFulfillmentCount = 1
        let compositor = CursorCompositor(
            options: options,
            geometry: FrameGeometry(contentRect: CGRect(x: 0, y: 0, width: 64, height: 64), pixelSize: CGSize(width: 64, height: 64)),
            sampler: FakeSampler(sampledSnapshot: CursorSnapshot(location: .zero, image: nil)),
            budget: budget,
            onDegradeToNativeCursor: { expectation.fulfill() }
        )
        let input = try makeSampleBuffer(width: 64, height: 64)
        XCTAssertTrue(compositor.composite(input) === input)
        XCTAssertTrue(compositor.composite(input) === input)
        wait(for: [expectation], timeout: 1)
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
