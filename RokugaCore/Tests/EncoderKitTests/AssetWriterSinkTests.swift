import AVFoundation
import CoreMedia
import XCTest
@testable import EncoderKit
import SettingsKit

final class AssetWriterSinkTests: XCTestCase {
    private var outputURL: URL!

    override func setUp() {
        super.setUp()
        outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rokuga-sink-test-\(UUID().uuidString).mp4")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: outputURL)
        super.tearDown()
    }

    private func makeConfiguration() -> EncoderConfiguration {
        EncoderConfiguration(
            codec: .h264,
            container: .mp4,
            width: 640,
            height: 360,
            frameRate: .fps30,
            quality: 60,
            audioBitrate: .kbps128,
            capturesSystemAudio: false,
            capturesMicrophone: false
        )
    }

    private func makeVideoSampleBuffer(pts: CMTime, width: Int = 640, height: Int = 360) throws -> CMSampleBuffer {
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary,
            &pixelBuffer
        )
        let buffer = try XCTUnwrap(pixelBuffer)

        var formatDescription: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: buffer,
            formatDescriptionOut: &formatDescription
        )

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: buffer,
            formatDescription: try XCTUnwrap(formatDescription),
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        return try XCTUnwrap(sampleBuffer)
    }

    /// Real-time pacing: the sink drops frames when the encoder is not ready, exactly like live capture, so tests must feed at source cadence.
    private func appendPaced(_ sink: AssetWriterSink, frames: Range<Int>, ptsOffset: CMTimeValue = 0) async throws {
        for frame in frames {
            let pts = CMTime(value: ptsOffset + CMTimeValue(frame), timescale: 30)
            sink.append(try makeVideoSampleBuffer(pts: pts), of: .video)
            try await Task.sleep(nanoseconds: 33_000_000)
        }
    }

    func testWritesPlayableFile() async throws {
        let sink = AssetWriterSink(outputURL: outputURL, configuration: makeConfiguration())
        try await sink.start()

        try await appendPaced(sink, frames: 0..<30)

        let url = try await sink.finish()
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let statistics = sink.statisticsSnapshot()
        XCTAssertGreaterThanOrEqual(statistics.videoFramesAppended, 25)

        let asset = AVAsset(url: url)
        let duration = try await asset.load(.duration)
        XCTAssertEqual(duration.seconds, 1.0, accuracy: 0.2)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(videoTracks.count, 1)
        let size = try await videoTracks[0].load(.naturalSize)
        XCTAssertEqual(Int(size.width), 640)
        XCTAssertEqual(Int(size.height), 360)
    }

    func testPauseProducesGaplessOutput() async throws {
        let sink = AssetWriterSink(outputURL: outputURL, configuration: makeConfiguration())
        try await sink.start()

        try await appendPaced(sink, frames: 0..<15)
        sink.markPaused()
        sink.markResumed()
        // Source clock jumped 10 seconds while paused.
        try await appendPaced(sink, frames: 0..<15, ptsOffset: 300)

        let url = try await sink.finish()
        let duration = try await AVAsset(url: url).load(.duration)
        XCTAssertLessThan(duration.seconds, 1.5, "10s pause gap must be spliced out")
        XCTAssertGreaterThan(duration.seconds, 0.6)
    }

    func testCancelRemovesPartialFile() async throws {
        let sink = AssetWriterSink(outputURL: outputURL, configuration: makeConfiguration())
        try await sink.start()
        sink.append(try makeVideoSampleBuffer(pts: .zero), of: .video)
        await sink.cancel()
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testFinishWithoutStartThrows() async {
        let sink = AssetWriterSink(outputURL: outputURL, configuration: makeConfiguration())
        do {
            _ = try await sink.finish()
            XCTFail("finish before start must throw")
        } catch { /* expected */ }
    }
}
