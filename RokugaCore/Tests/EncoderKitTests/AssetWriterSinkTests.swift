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

    private func makeConfiguration(capturesSystemAudio: Bool = false) -> EncoderConfiguration {
        EncoderConfiguration(
            codec: .h264,
            container: .mp4,
            width: 640,
            height: 360,
            frameRate: .fps30,
            quality: 60,
            audioBitrate: .kbps128,
            capturesSystemAudio: capturesSystemAudio,
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

    private func makeSystemAudioSampleBuffer(pts: CMTime, frames: AVAudioFrameCount = 1_600) throws -> CMSampleBuffer {
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(
                pcmFormat: AudioMixer.canonicalFormat,
                frameCapacity: frames
            )
        )
        buffer.frameLength = frames
        for channel in 0..<Int(buffer.format.channelCount) {
            guard let samples = buffer.floatChannelData?[channel] else { continue }
            for frame in 0..<Int(frames) {
                samples[frame] = 0.1
            }
        }
        return try XCTUnwrap(AudioSampleBufferFactory.sampleBuffer(from: buffer, presentationTime: pts))
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
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertTrue(audioTracks.isEmpty)
        let size = try await videoTracks[0].load(.naturalSize)
        XCTAssertEqual(Int(size.width), 640)
        XCTAssertEqual(Int(size.height), 360)
    }

    func testWritesSystemAudioTrackWhenEnabled() async throws {
        let sink = AssetWriterSink(
            outputURL: outputURL,
            configuration: makeConfiguration(capturesSystemAudio: true)
        )
        try await sink.start()

        for frame in 0..<30 {
            sink.append(
                try makeVideoSampleBuffer(pts: CMTime(value: CMTimeValue(frame), timescale: 30)),
                of: .video
            )
            sink.append(
                try makeSystemAudioSampleBuffer(pts: CMTime(value: CMTimeValue(frame * 1_600), timescale: 48_000)),
                of: .systemAudio
            )
            try await Task.sleep(nanoseconds: 33_000_000)
        }

        let url = try await sink.finish()
        let asset = AVAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(audioTracks.count, 1)
        let duration = try await audioTracks[0].load(.timeRange).duration
        XCTAssertEqual(duration.seconds, 1.0, accuracy: 0.2)
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
