import AVFoundation
import XCTest
@testable import TrimKit

final class TrimExporterTests: XCTestCase {
    private var fixtureURL: URL!

    override func setUp() async throws {
        fixtureURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("trim-fixture-\(UUID().uuidString).mp4")
        try await writeFixtureMovie(to: fixtureURL, durationSeconds: 2, fps: 30)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fixtureURL)
    }

    func testPassthroughExportKeepsSelectedRange() async throws {
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("trim-out-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: out) }

        let range = TrimRange(
            start: CMTime(seconds: 0.5, preferredTimescale: 600),
            end: CMTime(seconds: 1.5, preferredTimescale: 600)
        )
        try await TrimExporter(sourceURL: fixtureURL).export(kind: .passthrough, range: range, to: out)

        let duration = try await AVURLAsset(url: out).load(.duration).seconds
        XCTAssertEqual(duration, 1.0, accuracy: 0.6)
        XCTAssertTrue(FileManager.default.fileExists(atPath: out.path))
    }

    func testFrameExactExportProducesPlayableFile() async throws {
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("trim-exact-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: out) }

        let range = TrimRange(
            start: CMTime(seconds: 0.4, preferredTimescale: 600),
            end: CMTime(seconds: 1.4, preferredTimescale: 600)
        )
        var lastProgress = 0.0
        try await TrimExporter(sourceURL: fixtureURL).export(kind: .frameExact, range: range, to: out) { lastProgress = $0 }

        XCTAssertEqual(lastProgress, 1.0)
        let asset = AVURLAsset(url: out)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(videoTracks.count, 1)
        let exactDuration = try await asset.load(.duration).seconds
        XCTAssertEqual(exactDuration, 1.0, accuracy: 0.2)
    }

    func testAudioOnlyExportThrowsWithoutAudioTrack() async throws {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("trim-audio.m4a")
        let exporter = TrimExporter(sourceURL: fixtureURL)
        let hasAudio = try await exporter.hasAudioTrack()
        XCTAssertFalse(hasAudio)

        do {
            try await exporter.export(
                kind: .audioOnlyM4A,
                range: TrimRange(start: .zero, end: CMTime(seconds: 1, preferredTimescale: 600)),
                to: out
            )
            XCTFail("expected noAudioTrack")
        } catch let error as TrimExportError {
            XCTAssertEqual(error, .noAudioTrack)
        }
    }

    func testKeyframeIndexFindsSyncSamples() async throws {
        let index = try await KeyframeIndex.load(from: fixtureURL)
        XCTAssertGreaterThanOrEqual(index.seconds.count, 1)
        XCTAssertEqual(index.nearest(to: 0.01) ?? -1, index.seconds[0], accuracy: 0.001)
    }

    func testZoomBandQuantization() {
        XCTAssertEqual(ThumbnailStrip.band(forPointsPerSecond: 8), 3)
        XCTAssertEqual(ThumbnailStrip.band(forPointsPerSecond: 100), 7)
        XCTAssertEqual(ThumbnailStrip.secondsPerTile(band: 3, tileWidth: 80), 10.0, accuracy: 0.001)
    }

    private func writeFixtureMovie(to url: URL, durationSeconds: Int, fps: Int32) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 320,
            AVVideoHeightKey: 240,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 320,
            kCVPixelBufferHeightKey as String: 240,
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        let frameCount = Int(fps) * durationSeconds
        for frame in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            guard let pool = adaptor.pixelBufferPool else { throw TrimExportError.failed("no pool") }
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
            guard let pixelBuffer else { throw TrimExportError.failed("no buffer") }
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            memset(CVPixelBufferGetBaseAddress(pixelBuffer), UInt8(frame % 255).byteSwapped == 0 ? 0 : Int32(frame % 255), CVPixelBufferGetDataSize(pixelBuffer))
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
    }
}
