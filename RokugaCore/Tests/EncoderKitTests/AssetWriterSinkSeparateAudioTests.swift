import AVFoundation
import CoreMedia
import Foundation
import SettingsKit
import XCTest
@testable import EncoderKit

extension AssetWriterSinkTests {
    func makeAudioSampleBuffer(
        pts: CMTime,
        frames: AVAudioFrameCount = 1600,
        amplitude: Float = 0.1,
        frequency: Double? = nil
    ) throws -> CMSampleBuffer {
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(
                pcmFormat: AudioMixer.canonicalFormat,
                frameCapacity: frames
            )
        )
        buffer.frameLength = frames
        for channel in 0 ..< Int(buffer.format.channelCount) {
            guard let samples = buffer.floatChannelData?[channel] else { continue }
            for frame in 0 ..< Int(frames) {
                if let frequency {
                    samples[frame] = amplitude * Float(sin(2 * Double.pi * frequency * Double(frame) / 48000))
                } else {
                    samples[frame] = amplitude
                }
            }
        }
        return try XCTUnwrap(AudioSampleBufferFactory.sampleBuffer(from: buffer, presentationTime: pts))
    }

    private func useMOVOutputURL() {
        outputURL = outputURL.deletingPathExtension().appendingPathExtension("mov")
    }

    private func audioTrackTitle(_ track: AVAssetTrack) async throws -> String? {
        let metadata = try await track.load(.metadata)
        guard let title = metadata.first(where: { $0.identifier == .quickTimeMetadataTitle }) else { return nil }
        return try await title.load(.stringValue)
    }

    private func audioTrackLanguageTag(_ track: AVAssetTrack) async throws -> String? {
        let metadata = try await track.load(.metadata)
        guard let title = metadata.first(where: { $0.identifier == .quickTimeMetadataTitle }) else { return nil }
        return title.extendedLanguageTag
    }

    private func audioSampleRate(_ track: AVAssetTrack) async throws -> Double {
        let descriptions = try await track.load(.formatDescriptions)
        let description = try XCTUnwrap(descriptions.first)
        return try XCTUnwrap(CMAudioFormatDescriptionGetStreamBasicDescription(description)).pointee.mSampleRate
    }

    private func decodedRMS(of track: AVAssetTrack, in asset: AVAsset) throws -> Double {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsNonInterleaved: false
            ]
        )
        XCTAssertTrue(reader.canAdd(output))
        reader.add(output)
        XCTAssertTrue(reader.startReading())

        var squareSum = 0.0
        var sampleCount = 0
        while let sampleBuffer = output.copyNextSampleBuffer(),
              let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
            let length = CMBlockBufferGetDataLength(dataBuffer)
            var samples = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            let status = samples.withUnsafeMutableBytes { bytes in
                CMBlockBufferCopyDataBytes(
                    dataBuffer,
                    atOffset: 0,
                    dataLength: length,
                    destination: bytes.baseAddress!
                )
            }
            XCTAssertEqual(status, kCMBlockBufferNoErr)
            for sample in samples {
                squareSum += Double(sample * sample)
            }
            sampleCount += samples.count
        }
        XCTAssertEqual(reader.status, .completed)
        return sqrt(squareSum / Double(max(sampleCount, 1)))
    }

    func testWritesSeparateMOVTracksWithStableIdentityAndIsolatedSignals() async throws {
        useMOVOutputURL()
        let sink = AssetWriterSink(
            outputURL: outputURL,
            configuration: makeConfiguration(
                capturesSystemAudio: true,
                capturesMicrophone: true,
                container: .mov,
                audioTrackLayout: .separate
            )
        )
        try await sink.start()

        for frame in 0 ..< 30 {
            let videoPTS = CMTime(value: CMTimeValue(frame), timescale: 30)
            let audioPTS = CMTime(value: CMTimeValue(frame * 1600), timescale: 48000)
            try sink.append(makeVideoSampleBuffer(pts: videoPTS), of: .video)
            try sink.append(
                makeAudioSampleBuffer(pts: audioPTS, amplitude: 0.1, frequency: 300),
                of: .systemAudio
            )
            try sink.append(
                makeAudioSampleBuffer(pts: audioPTS, amplitude: 0.6, frequency: 900),
                of: .microphone
            )
            try await Task.sleep(nanoseconds: 33_000_000)
        }

        let url = try await sink.finish()
        let header = try Data(contentsOf: url).prefix(12)
        XCTAssertEqual(String(bytes: header.dropFirst(8), encoding: .utf8), "qt  ")

        let asset = AVAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(tracks.count, 2)
        let systemTitle = try await audioTrackTitle(tracks[0])
        let microphoneTitle = try await audioTrackTitle(tracks[1])
        let systemLanguageTag = try await audioTrackLanguageTag(tracks[0])
        let microphoneLanguageTag = try await audioTrackLanguageTag(tracks[1])
        let systemSampleRate = try await audioSampleRate(tracks[0])
        let microphoneSampleRate = try await audioSampleRate(tracks[1])
        XCTAssertEqual(systemTitle, "System Audio")
        XCTAssertEqual(microphoneTitle, "Microphone")
        XCTAssertEqual(systemLanguageTag, "und")
        XCTAssertEqual(microphoneLanguageTag, "und")
        XCTAssertEqual(systemSampleRate, 48000)
        XCTAssertEqual(microphoneSampleRate, 48000)

        let systemRMS = try decodedRMS(of: tracks[0], in: asset)
        let microphoneRMS = try decodedRMS(of: tracks[1], in: asset)
        XCTAssertGreaterThan(systemRMS, 0.04)
        XCTAssertLessThan(systemRMS, 0.12)
        XCTAssertGreaterThan(microphoneRMS, 0.3)
        XCTAssertLessThan(microphoneRMS, 0.5)
    }

    func testSeparateMOVWritesOneTitledTrackForOneSource() async throws {
        let cases: [(kind: MediaKind, title: String)] = [
            (.systemAudio, "System Audio"),
            (.microphone, "Microphone")
        ]

        for item in cases {
            let capturesSystemAudio: Bool
            let capturesMicrophone: Bool
            switch item.kind {
            case .systemAudio:
                capturesSystemAudio = true
                capturesMicrophone = false
            case .microphone:
                capturesSystemAudio = false
                capturesMicrophone = true
            case .video:
                continue
            }

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("rokuga-single-track-test-\(UUID().uuidString).mov")
            defer { try? FileManager.default.removeItem(at: url) }
            let sink = AssetWriterSink(
                outputURL: url,
                configuration: makeConfiguration(
                    capturesSystemAudio: capturesSystemAudio,
                    capturesMicrophone: capturesMicrophone,
                    container: .mov,
                    audioTrackLayout: .separate
                )
            )
            try await sink.start()
            for frame in 0 ..< 10 {
                try sink.append(
                    makeVideoSampleBuffer(pts: CMTime(value: CMTimeValue(frame), timescale: 30)),
                    of: .video
                )
                try sink.append(
                    makeAudioSampleBuffer(pts: CMTime(value: CMTimeValue(frame * 1600), timescale: 48000)),
                    of: item.kind
                )
                try await Task.sleep(nanoseconds: 33_000_000)
            }

            let outputURL = try await sink.finish()
            let tracks = try await AVAsset(url: outputURL).loadTracks(withMediaType: .audio)
            XCTAssertEqual(tracks.count, 1)
            let title = try await audioTrackTitle(XCTUnwrap(tracks.first))
            XCTAssertEqual(title, item.title)
        }
    }

    func testAudioOutputSettingsUseConfiguredBitrate() {
        let sink = AssetWriterSink(
            outputURL: outputURL,
            configuration: makeConfiguration(audioBitrate: .kbps320)
        )
        XCTAssertEqual(sink.audioOutputSettings()[AVEncoderBitRateKey] as? Int, 320_000)
    }

    func testSeparateTracksUseSharedPauseSplice() async throws {
        useMOVOutputURL()
        let sink = AssetWriterSink(
            outputURL: outputURL,
            configuration: makeConfiguration(
                capturesSystemAudio: true,
                capturesMicrophone: true,
                container: .mov,
                audioTrackLayout: .separate
            )
        )
        try await sink.start()

        for frame in 0 ..< 8 {
            let videoPTS = CMTime(value: CMTimeValue(frame), timescale: 30)
            let audioPTS = CMTime(value: CMTimeValue(frame * 1600), timescale: 48000)
            try sink.append(makeVideoSampleBuffer(pts: videoPTS), of: .video)
            try sink.append(makeAudioSampleBuffer(pts: audioPTS), of: .systemAudio)
            try sink.append(makeAudioSampleBuffer(pts: audioPTS, amplitude: 0.3), of: .microphone)
            try await Task.sleep(nanoseconds: 33_000_000)
        }
        sink.markPaused()
        sink.markResumed()
        for frame in 0 ..< 8 {
            let videoPTS = CMTime(value: 300 + CMTimeValue(frame), timescale: 30)
            let audioPTS = CMTime(value: 480_000 + CMTimeValue(frame * 1600), timescale: 48000)
            try sink.append(makeVideoSampleBuffer(pts: videoPTS), of: .video)
            try sink.append(makeAudioSampleBuffer(pts: audioPTS), of: .systemAudio)
            try sink.append(makeAudioSampleBuffer(pts: audioPTS, amplitude: 0.3), of: .microphone)
            try await Task.sleep(nanoseconds: 33_000_000)
        }

        let url = try await sink.finish()
        let asset = AVAsset(url: url)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let videoTrack = try XCTUnwrap(videoTracks.first)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(audioTracks.count, 2)
        let videoDuration = try await videoTrack.load(.timeRange).duration.seconds
        for track in audioTracks {
            let duration = try await track.load(.timeRange).duration.seconds
            XCTAssertLessThan(duration, 1)
            XCTAssertEqual(duration, videoDuration, accuracy: 0.12)
        }
    }

    func testSeparateTrackBurstDoesNotBlockOrStopOtherInput() async throws {
        useMOVOutputURL()
        let sink = AssetWriterSink(
            outputURL: outputURL,
            configuration: makeConfiguration(
                capturesSystemAudio: true,
                capturesMicrophone: true,
                container: .mov,
                audioTrackLayout: .separate
            )
        )
        try await sink.start()
        try sink.append(makeVideoSampleBuffer(pts: .zero), of: .video)
        for chunk in 0 ..< 300 {
            let pts = CMTime(value: CMTimeValue(chunk * 1600), timescale: 48000)
            if chunk < 150 {
                try sink.append(makeAudioSampleBuffer(pts: pts), of: .systemAudio)
            }
            if chunk >= 150 || chunk.isMultiple(of: 25) {
                try sink.append(makeAudioSampleBuffer(pts: pts, amplitude: 0.5), of: .microphone)
            }
        }
        try sink.append(makeVideoSampleBuffer(pts: CMTime(seconds: 10, preferredTimescale: 600)), of: .video)

        let url = try await sink.finish()
        let asset = AVAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(tracks.count, 2)
        XCTAssertGreaterThan(try decodedRMS(of: tracks[1], in: asset), 0.2)
        let microphoneRange = try await tracks[1].load(.timeRange)
        XCTAssertGreaterThan(microphoneRange.duration.seconds, 4.5)
    }

    func testSeparateCancelRemovesPartialFile() async throws {
        useMOVOutputURL()
        let sink = AssetWriterSink(
            outputURL: outputURL,
            configuration: makeConfiguration(
                capturesSystemAudio: true,
                capturesMicrophone: true,
                container: .mov,
                audioTrackLayout: .separate
            )
        )
        try await sink.start()
        try sink.append(makeVideoSampleBuffer(pts: .zero), of: .video)
        try sink.append(makeAudioSampleBuffer(pts: .zero), of: .systemAudio)
        try sink.append(makeAudioSampleBuffer(pts: .zero), of: .microphone)
        await sink.cancel()
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testStartFailureRemovesPartialOutput() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rokuga-start-failure-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        outputURL = directory.appendingPathComponent("recording.mov")
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        let sink = AssetWriterSink(
            outputURL: outputURL,
            configuration: makeConfiguration(
                capturesSystemAudio: true,
                capturesMicrophone: true,
                container: .mov,
                audioTrackLayout: .separate
            )
        )
        do {
            try await sink.start()
            XCTFail("start must fail when the output cannot be created")
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
        }
    }
}
