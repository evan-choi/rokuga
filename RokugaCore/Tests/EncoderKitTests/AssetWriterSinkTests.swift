import AVFoundation
import CoreMedia
import SettingsKit
import XCTest
@testable import EncoderKit

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

    private func makeConfiguration(
        capturesSystemAudio: Bool = false,
        capturesMicrophone: Bool = false,
        frameRateMode: FrameRateMode = .variable,
        codec: VideoCodec = .h264,
        container: ContainerFormat = .mp4,
        width: Int = 640,
        height: Int = 360,
        quality: Int = 60,
        audioBitrate: AudioBitrate = .kbps128,
        audioTrackLayout: AudioTrackLayout = .mixed
    ) -> EncoderConfiguration {
        EncoderConfiguration(
            codec: codec,
            container: container,
            width: width,
            height: height,
            frameRate: 30,
            frameRateMode: frameRateMode,
            quality: quality,
            audioBitrate: audioBitrate,
            capturesSystemAudio: capturesSystemAudio,
            capturesMicrophone: capturesMicrophone,
            audioTrackLayout: audioTrackLayout
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
        try CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: buffer,
            formatDescription: XCTUnwrap(formatDescription),
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        return try XCTUnwrap(sampleBuffer)
    }

    private func makeAudioSampleBuffer(
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

    /// Real-time pacing: the sink drops frames when the encoder is not ready, exactly like live capture, so tests must feed at source cadence.
    private func appendPaced(_ sink: AssetWriterSink, frames: Range<Int>, ptsOffset: CMTimeValue = 0) async throws {
        for frame in frames {
            let pts = CMTime(value: ptsOffset + CMTimeValue(frame), timescale: 30)
            try sink.append(makeVideoSampleBuffer(pts: pts), of: .video)
            try await Task.sleep(nanoseconds: 33_000_000)
        }
    }

    private func videoPresentationTimes(at url: URL) async throws -> [CMTime] {
        let asset = AVAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        XCTAssertTrue(reader.canAdd(output))
        reader.add(output)
        XCTAssertTrue(reader.startReading())

        var times: [CMTime] = []
        while let sampleBuffer = output.copyNextSampleBuffer() {
            times.append(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        }
        XCTAssertEqual(reader.status, .completed)
        return times
    }

    func testMP4NormalizesSeparateAudioTracksToMixed() {
        let configuration = makeConfiguration(
            capturesSystemAudio: true,
            capturesMicrophone: true,
            container: .mp4,
            audioTrackLayout: .separate
        )
        XCTAssertEqual(configuration.audioTrackLayout, .mixed)
    }

    func testMOVPreservesSeparateAudioTracksWithOneSource() {
        let configuration = makeConfiguration(
            capturesSystemAudio: true,
            container: .mov,
            audioTrackLayout: .separate
        )
        XCTAssertEqual(configuration.audioTrackLayout, .separate)
    }

    func testWritesPlayableFile() async throws {
        let sink = AssetWriterSink(outputURL: outputURL, configuration: makeConfiguration())
        try await sink.start()

        try await appendPaced(sink, frames: 0 ..< 30)

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

    func testDetailedStatisticsMeasureReceivedFramesAndQueueWait() async throws {
        let sink = AssetWriterSink(
            outputURL: outputURL,
            configuration: makeConfiguration(),
            collectsDetailedStatistics: true
        )
        try await sink.start()
        try sink.append(makeVideoSampleBuffer(pts: .zero), of: .video)
        try await Task.sleep(nanoseconds: 50_000_000)
        _ = try await sink.finish()

        let statistics = sink.statisticsSnapshot()
        XCTAssertEqual(statistics.videoFramesReceived, 1)
        XCTAssertEqual(statistics.writerQueueSamples, 1)
        XCTAssertGreaterThanOrEqual(statistics.writerQueueWaitSeconds, 0)
        XCTAssertGreaterThanOrEqual(statistics.maxWriterQueueWaitSeconds, 0)
    }

    func testHEVCMainPreservesOddNativeDimensionsAtMaximumQuality() async throws {
        let width = 321
        let height = 181
        let sink = AssetWriterSink(
            outputURL: outputURL,
            configuration: makeConfiguration(
                codec: .hevc,
                container: .mov,
                width: width,
                height: height,
                quality: 100
            )
        )
        try await sink.start()

        for frame in 0 ..< 10 {
            try sink.append(
                makeVideoSampleBuffer(
                    pts: CMTime(value: CMTimeValue(frame), timescale: 30),
                    width: width,
                    height: height
                ),
                of: .video
            )
            try await Task.sleep(nanoseconds: 33_000_000)
        }

        let url = try await sink.finish()
        let tracks = try await AVAsset(url: url).loadTracks(withMediaType: .video)
        let size = try await XCTUnwrap(tracks.first).load(.naturalSize)
        XCTAssertEqual(Int(size.width), width)
        XCTAssertEqual(Int(size.height), height)
        let presentationTimes = try await videoPresentationTimes(at: url)
        XCTAssertFalse(presentationTimes.isEmpty)
    }

    func testOutputFileCarriesSRGBColorTags() async throws {
        for codec in [VideoCodec.h264, VideoCodec.hevc] {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("rokuga-color-test-\(UUID().uuidString).mp4")
            defer { try? FileManager.default.removeItem(at: url) }

            let sink = AssetWriterSink(outputURL: url, configuration: makeConfiguration(codec: codec))
            try await sink.start()
            try await appendPaced(sink, frames: 0 ..< 10)
            _ = try await sink.finish()

            let tracks = try await AVAsset(url: url).loadTracks(withMediaType: .video)
            let formats = try await XCTUnwrap(tracks.first).load(.formatDescriptions)
            let format = try XCTUnwrap(formats.first)
            XCTAssertEqual(
                CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_ColorPrimaries) as? String,
                kCMFormatDescriptionColorPrimaries_ITU_R_709_2 as String,
                "\(codec) primaries"
            )
            XCTAssertEqual(
                CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_TransferFunction) as? String,
                kCMFormatDescriptionTransferFunction_sRGB as String,
                "\(codec) transfer function"
            )
            XCTAssertEqual(
                CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_YCbCrMatrix) as? String,
                kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2 as String,
                "\(codec) YCbCr matrix"
            )
        }
    }

    func testVariableFrameRateDoesNotSynthesizeFrames() async throws {
        let sink = AssetWriterSink(
            outputURL: outputURL,
            configuration: makeConfiguration(frameRateMode: .variable)
        )
        try await sink.start()
        try sink.append(makeVideoSampleBuffer(pts: .zero), of: .video)
        try await Task.sleep(nanoseconds: 100_000_000)
        try sink.append(makeVideoSampleBuffer(pts: CMTime(value: 1, timescale: 5)), of: .video)
        try await Task.sleep(nanoseconds: 100_000_000)

        let url = try await sink.finish()

        XCTAssertEqual(sink.statisticsSnapshot().videoFramesAppended, 2)
        let times = try await videoPresentationTimes(at: url)
        XCTAssertEqual(times.count, 2)
        XCTAssertEqual(CMTimeSubtract(times[1], times[0]).seconds, 0.2, accuracy: 0.001)
    }

    func testVariableFrameRatePreservesStaticRecordingDuration() async throws {
        let sink = AssetWriterSink(
            outputURL: outputURL,
            configuration: makeConfiguration(frameRateMode: .variable)
        )
        try await sink.start()
        try sink.append(makeVideoSampleBuffer(pts: .zero), of: .video)
        try await Task.sleep(nanoseconds: 350_000_000)

        let url = try await sink.finish()

        let duration = try await AVAsset(url: url).load(.duration)
        let presentationTimes = try await videoPresentationTimes(at: url)
        XCTAssertGreaterThan(duration.seconds, 0.25)
        XCTAssertEqual(presentationTimes.count, 1)
    }

    func testConstantFrameRateSynthesizesFramesForStaticContent() async throws {
        let sink = AssetWriterSink(
            outputURL: outputURL,
            configuration: makeConfiguration(frameRateMode: .constant)
        )
        try await sink.start()
        try sink.append(makeVideoSampleBuffer(pts: .zero), of: .video)
        try await Task.sleep(nanoseconds: 350_000_000)

        let url = try await sink.finish()

        XCTAssertGreaterThanOrEqual(sink.statisticsSnapshot().videoFramesAppended, 8)
        let duration = try await AVAsset(url: url).load(.duration)
        XCTAssertGreaterThan(duration.seconds, 0.25)
        let times = try await videoPresentationTimes(at: url)
        XCTAssertGreaterThanOrEqual(times.count, 8)
        for (previous, current) in zip(times, times.dropFirst()) {
            XCTAssertEqual(CMTimeSubtract(current, previous).seconds, 1.0 / 30.0, accuracy: 0.001)
        }
    }

    func testConstantFrameRateKeepsAudioDurationInSync() async throws {
        let sink = AssetWriterSink(
            outputURL: outputURL,
            configuration: makeConfiguration(capturesSystemAudio: true, frameRateMode: .constant)
        )
        try await sink.start()
        try sink.append(makeVideoSampleBuffer(pts: .zero), of: .video)
        let startedAt = DispatchTime.now().uptimeNanoseconds
        for chunk in 0 ..< 11 {
            if chunk > 0 {
                try await Task.sleep(nanoseconds: 33_000_000)
            }
            let elapsed = DispatchTime.now().uptimeNanoseconds - startedAt
            try sink.append(
                makeAudioSampleBuffer(pts: CMTime(value: CMTimeValue(elapsed), timescale: 1_000_000_000)),
                of: .systemAudio
            )
        }

        let url = try await sink.finish()
        let asset = AVAsset(url: url)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let videoTrack = try XCTUnwrap(videoTracks.first)
        let audioTrack = try XCTUnwrap(audioTracks.first)
        let videoDuration = try await videoTrack.load(.timeRange).duration.seconds
        let audioDuration = try await audioTrack.load(.timeRange).duration.seconds

        XCTAssertGreaterThan(videoDuration, 0.25)
        XCTAssertGreaterThan(audioDuration, 0.25)
        XCTAssertEqual(videoDuration, audioDuration, accuracy: 0.08)
    }

    func testWritesSystemAudioTrackWhenEnabled() async throws {
        let sink = AssetWriterSink(
            outputURL: outputURL,
            configuration: makeConfiguration(capturesSystemAudio: true)
        )
        try await sink.start()

        for frame in 0 ..< 30 {
            try sink.append(
                makeVideoSampleBuffer(pts: CMTime(value: CMTimeValue(frame), timescale: 30)),
                of: .video
            )
            try sink.append(
                makeAudioSampleBuffer(pts: CMTime(value: CMTimeValue(frame * 1600), timescale: 48000)),
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

    func testWritesMicrophoneAudioTrackWhenEnabled() async throws {
        let sink = AssetWriterSink(
            outputURL: outputURL,
            configuration: makeConfiguration(capturesMicrophone: true)
        )
        try await sink.start()

        for frame in 0 ..< 30 {
            try sink.append(
                makeVideoSampleBuffer(pts: CMTime(value: CMTimeValue(frame), timescale: 30)),
                of: .video
            )
            try sink.append(
                makeAudioSampleBuffer(pts: CMTime(value: CMTimeValue(frame * 1600), timescale: 48000)),
                of: .microphone
            )
            try await Task.sleep(nanoseconds: 33_000_000)
        }

        let url = try await sink.finish()
        let audioTracks = try await AVAsset(url: url).loadTracks(withMediaType: .audio)
        XCTAssertEqual(audioTracks.count, 1)
        let duration = try await audioTracks[0].load(.timeRange).duration
        XCTAssertEqual(duration.seconds, 1.0, accuracy: 0.2)
    }

    func testWritesSystemAndMicrophoneAsSingleAudioTrack() async throws {
        let sink = AssetWriterSink(
            outputURL: outputURL,
            configuration: makeConfiguration(capturesSystemAudio: true, capturesMicrophone: true)
        )
        try await sink.start()

        for frame in 0 ..< 30 {
            let videoPTS = CMTime(value: CMTimeValue(frame), timescale: 30)
            let audioPTS = CMTime(value: CMTimeValue(frame * 1600), timescale: 48000)
            try sink.append(makeVideoSampleBuffer(pts: videoPTS), of: .video)
            try sink.append(makeAudioSampleBuffer(pts: audioPTS), of: .microphone)
            try sink.append(makeAudioSampleBuffer(pts: audioPTS), of: .systemAudio)
            try await Task.sleep(nanoseconds: 33_000_000)
        }

        let url = try await sink.finish()
        let audioTracks = try await AVAsset(url: url).loadTracks(withMediaType: .audio)
        XCTAssertEqual(audioTracks.count, 1)
        let duration = try await audioTracks[0].load(.timeRange).duration
        XCTAssertEqual(duration.seconds, 1.0, accuracy: 0.2)
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
        XCTAssertEqual(String(decoding: header.dropFirst(8), as: UTF8.self), "qt  ")

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
        let cases: [(MediaKind, Bool, Bool, String)] = [
            (.systemAudio, true, false, "System Audio"),
            (.microphone, false, true, "Microphone")
        ]

        for (kind, capturesSystemAudio, capturesMicrophone, expectedTitle) in cases {
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
                    of: kind
                )
                try await Task.sleep(nanoseconds: 33_000_000)
            }

            let outputURL = try await sink.finish()
            let tracks = try await AVAsset(url: outputURL).loadTracks(withMediaType: .audio)
            XCTAssertEqual(tracks.count, 1)
            let title = try await audioTrackTitle(XCTUnwrap(tracks.first))
            XCTAssertEqual(title, expectedTitle)
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
            XCTFail("start must fail when the output already exists")
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
        }
    }

    func testPauseProducesGaplessOutput() async throws {
        let sink = AssetWriterSink(outputURL: outputURL, configuration: makeConfiguration())
        try await sink.start()

        try await appendPaced(sink, frames: 0 ..< 15)
        sink.markPaused()
        sink.markResumed()
        // Source clock jumped 10 seconds while paused.
        try await appendPaced(sink, frames: 0 ..< 15, ptsOffset: 300)

        let url = try await sink.finish()
        let duration = try await AVAsset(url: url).load(.duration)
        XCTAssertLessThan(duration.seconds, 1.5, "10s pause gap must be spliced out")
        XCTAssertGreaterThan(duration.seconds, 0.6)
    }

    func testCancelRemovesPartialFile() async throws {
        let sink = AssetWriterSink(outputURL: outputURL, configuration: makeConfiguration())
        try await sink.start()
        try sink.append(makeVideoSampleBuffer(pts: .zero), of: .video)
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
