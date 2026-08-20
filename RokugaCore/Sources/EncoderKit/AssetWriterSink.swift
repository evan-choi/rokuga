import AVFoundation
import CoreMedia
import Foundation
import SettingsKit
import VideoToolbox

/// AVAssetWriter-backed `MediaSink` (task 3.1).
///
/// Video: SCStream's IOSurface-backed BGRA buffers are appended untouched — VideoToolbox reads them zero-copy, no CPU pixel path.
/// Audio: one AAC track; the mic is summed into system audio by `AudioMixer` when both are enabled.
public final class AssetWriterSink: MediaSink, @unchecked Sendable {
    private let outputURL: URL
    private let configuration: EncoderConfiguration

    private let queue = DispatchQueue(label: "io.rokuga.encoder.writer", qos: .userInteractive)
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var spliceClock = SpliceClock()
    private var mixer: AudioMixer?
    private var sessionStarted = false
    private var terminalError: Error?
    private var statistics = Statistics()
    private var constantFrameTimer: DispatchSourceTimer?
    private var latestConstantFrame: CMSampleBuffer?
    private var nextConstantFramePTS: CMTime?
    private var lastVideoPTS: CMTime?
    private var lastVideoUptimeNanoseconds: UInt64?
    private var pauseUptimeNanoseconds: UInt64?
    private let collectsDetailedStatistics: Bool

    /// Drop accounting feeds the perf gates (task 10.2: 4K60 drop-rate < 0.1%).
    public struct Statistics: Equatable, Sendable {
        public var videoFramesReceived = 0
        public var videoFramesAppended = 0
        public var videoFramesDropped = 0
        public var audioSamplesReceived = 0
        public var writerQueueSamples = 0
        public var writerQueueWaitSeconds = 0.0
        public var maxWriterQueueWaitSeconds = 0.0
    }

    public func statisticsSnapshot() -> Statistics {
        queue.sync { statistics }
    }

    public init(
        outputURL: URL,
        configuration: EncoderConfiguration,
        collectsDetailedStatistics: Bool = false
    ) {
        self.outputURL = outputURL
        self.configuration = configuration
        self.collectsDetailedStatistics = collectsDetailedStatistics
    }

    // MARK: MediaSink

    public func start() async throws {
        try DiskSpaceMonitor.preflight(outputFolder: outputURL.deletingLastPathComponent())

        let fileType: AVFileType = configuration.container == .mov ? .mov : .mp4
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: fileType)
        if configuration.container == .mov {
            // Fragmented QuickTime keeps partials playable after a crash or power loss (task 3.6); AVAssetWriter only supports this for .mov.
            writer.movieFragmentInterval = CMTime(value: 2, timescale: 1)
        }

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoOutputSettings())
        videoInput.expectsMediaDataInRealTime = true
        writer.add(videoInput)

        if configuration.capturesSystemAudio || configuration.capturesMicrophone {
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioOutputSettings())
            audioInput.expectsMediaDataInRealTime = true
            writer.add(audioInput)
            self.audioInput = audioInput
        }

        if configuration.capturesSystemAudio, configuration.capturesMicrophone {
            mixer = AudioMixer()
        }

        guard writer.startWriting() else {
            throw RecordingSinkError.writerFailed(writer.error?.localizedDescription ?? "startWriting")
        }
        self.writer = writer
        self.videoInput = videoInput
    }

    public func append(_ sampleBuffer: CMSampleBuffer, of kind: MediaKind) {
        let enqueuedAt = collectsDetailedStatistics ? DispatchTime.now().uptimeNanoseconds : nil
        queue.async { [self] in
            if let enqueuedAt {
                let wait = Double(DispatchTime.now().uptimeNanoseconds - enqueuedAt) / 1_000_000_000
                statistics.writerQueueSamples += 1
                statistics.writerQueueWaitSeconds += wait
                statistics.maxWriterQueueWaitSeconds = max(statistics.maxWriterQueueWaitSeconds, wait)
            }
            switch kind {
            case .video:
                if collectsDetailedStatistics { statistics.videoFramesReceived += 1 }
                appendVideo(sampleBuffer)
            case .systemAudio:
                if collectsDetailedStatistics { statistics.audioSamplesReceived += 1 }
                appendSystemAudio(sampleBuffer)
            case .microphone:
                if collectsDetailedStatistics { statistics.audioSamplesReceived += 1 }
                appendMicrophone(sampleBuffer)
            }
        }
    }

    public func markPaused() {
        queue.async { [self] in
            stopConstantFrameOutput(clearFrame: false)
            pauseUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
            spliceClock.markPaused()
        }
    }

    public func markResumed() {
        queue.async { [self] in
            if let pauseUptimeNanoseconds, let lastVideoUptimeNanoseconds {
                self.lastVideoUptimeNanoseconds = lastVideoUptimeNanoseconds
                    + DispatchTime.now().uptimeNanoseconds - pauseUptimeNanoseconds
            }
            pauseUptimeNanoseconds = nil
        }
    }

    public func finish() async throws -> URL {
        let writer: AVAssetWriter? = await withCheckedContinuation { continuation in
            queue.async { [self] in
                stopConstantFrameOutput(clearFrame: true)
                if let lastVideoPTS, let lastVideoUptimeNanoseconds {
                    let endUptimeNanoseconds = pauseUptimeNanoseconds ?? DispatchTime.now().uptimeNanoseconds
                    let elapsed = endUptimeNanoseconds > lastVideoUptimeNanoseconds
                        ? endUptimeNanoseconds - lastVideoUptimeNanoseconds
                        : 0
                    self.writer?.endSession(atSourceTime: CMTimeAdd(
                        lastVideoPTS,
                        CMTime(value: CMTimeValue(elapsed), timescale: 1_000_000_000)
                    ))
                }
                videoInput?.markAsFinished()
                audioInput?.markAsFinished()
                continuation.resume(returning: self.writer)
            }
        }
        guard let writer else { throw RecordingSinkError.notStarted }
        if let terminalError { throw terminalError }

        guard writer.status == .writing else {
            throw RecordingSinkError.writerFailed(writer.error?.localizedDescription ?? "status \(writer.status.rawValue)")
        }
        await writer.finishWriting()
        if writer.status == .failed {
            throw RecordingSinkError.writerFailed(writer.error?.localizedDescription ?? "finishWriting")
        }
        return outputURL
    }

    public func cancel() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                stopConstantFrameOutput(clearFrame: true)
                writer?.cancelWriting()
                try? FileManager.default.removeItem(at: outputURL)
                continuation.resume()
            }
        }
    }

    // MARK: Video path

    private func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        guard let writer, terminalError == nil else { return }

        let sourcePTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let adjustedPTS = spliceClock.adjusted(sourcePTS)
        spliceClock.observe(pts: sourcePTS, duration: CMSampleBufferGetDuration(sampleBuffer))
        lastVideoPTS = adjustedPTS
        lastVideoUptimeNanoseconds = pauseUptimeNanoseconds ?? DispatchTime.now().uptimeNanoseconds

        if !sessionStarted {
            writer.startSession(atSourceTime: adjustedPTS)
            sessionStarted = true
        }

        if configuration.frameRateMode == .constant {
            updateConstantFrame(sampleBuffer, adjustedPTS: adjustedPTS)
        } else {
            appendVideoSample(sampleBuffer, at: adjustedPTS)
        }
    }

    private func appendVideoSample(_ sampleBuffer: CMSampleBuffer, at pts: CMTime, duration: CMTime? = nil) {
        guard let writer, let videoInput, terminalError == nil else { return }
        guard videoInput.isReadyForMoreMediaData,
              let retimed = retime(sampleBuffer, to: pts, duration: duration)
        else {
            statistics.videoFramesDropped += 1
            return
        }
        if videoInput.append(retimed) {
            statistics.videoFramesAppended += 1
        } else {
            terminalError = RecordingSinkError.writerFailed(writer.error?.localizedDescription ?? "video append")
        }
    }

    /// CFR keeps a single latest-frame reference and emits it on the encoder queue's
    /// fixed cadence. Static screen content therefore remains constant-rate even when
    /// ScreenCaptureKit does not deliver a new complete frame.
    private func updateConstantFrame(_ sampleBuffer: CMSampleBuffer, adjustedPTS: CMTime) {
        latestConstantFrame = sampleBuffer
        guard constantFrameTimer == nil else { return }

        let duration = constantFrameDuration
        let outputPTS = nextConstantFramePTS ?? adjustedPTS
        appendVideoSample(sampleBuffer, at: outputPTS, duration: duration)
        nextConstantFramePTS = CMTimeAdd(outputPTS, duration)
        startConstantFrameTimer()
    }

    private func startConstantFrameTimer() {
        let nanoseconds = max(1, 1_000_000_000 / configuration.frameRate)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + .nanoseconds(nanoseconds),
            repeating: .nanoseconds(nanoseconds),
            leeway: .milliseconds(1)
        )
        timer.setEventHandler { [weak self] in
            self?.emitConstantFrame()
        }
        constantFrameTimer = timer
        timer.resume()
    }

    private func emitConstantFrame() {
        guard let sampleBuffer = latestConstantFrame,
              let pts = nextConstantFramePTS
        else { return }
        appendVideoSample(sampleBuffer, at: pts, duration: constantFrameDuration)
        nextConstantFramePTS = CMTimeAdd(pts, constantFrameDuration)
    }

    private func stopConstantFrameOutput(clearFrame: Bool) {
        constantFrameTimer?.cancel()
        constantFrameTimer = nil
        if clearFrame {
            latestConstantFrame = nil
            nextConstantFramePTS = nil
        }
    }

    private var constantFrameDuration: CMTime {
        CMTime(value: 1, timescale: CMTimeScale(configuration.frameRate))
    }

    // MARK: Audio path

    private func appendSystemAudio(_ sampleBuffer: CMSampleBuffer) {
        guard sessionStarted, let audioInput, terminalError == nil else { return }
        let sourcePTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let adjustedPTS = spliceClock.adjusted(sourcePTS)
        spliceClock.observe(pts: sourcePTS, duration: CMSampleBufferGetDuration(sampleBuffer))

        guard audioInput.isReadyForMoreMediaData else { return }

        if let mixer {
            guard let pcm = AudioSampleBufferFactory.pcmBuffer(from: sampleBuffer),
                  let mixed = mixer.mix(system: pcm),
                  let retimed = AudioSampleBufferFactory.sampleBuffer(from: mixed, presentationTime: adjustedPTS)
            else { return }
            appendAudio(retimed)
        } else if let retimed = retime(sampleBuffer, to: adjustedPTS) {
            appendAudio(retimed)
        }
    }

    private func appendMicrophone(_ sampleBuffer: CMSampleBuffer) {
        guard terminalError == nil else { return }

        if let mixer {
            guard let pcm = AudioSampleBufferFactory.pcmBuffer(from: sampleBuffer) else { return }
            mixer.enqueueMicrophone(pcm)
            return
        }

        // Mic-only mode: the mic stream drives the audio track directly.
        guard sessionStarted, let audioInput, audioInput.isReadyForMoreMediaData else { return }
        let sourcePTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let adjustedPTS = spliceClock.adjusted(sourcePTS)
        spliceClock.observe(pts: sourcePTS, duration: CMSampleBufferGetDuration(sampleBuffer))
        if let retimed = retime(sampleBuffer, to: adjustedPTS) {
            appendAudio(retimed)
        }
    }

    private func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        guard let writer, let audioInput else { return }
        if !audioInput.append(sampleBuffer) {
            terminalError = RecordingSinkError.writerFailed(writer.error?.localizedDescription ?? "audio append")
        }
    }

    // MARK: Helpers

    private func retime(
        _ sampleBuffer: CMSampleBuffer,
        to pts: CMTime,
        duration: CMTime? = nil
    ) -> CMSampleBuffer? {
        let originalPTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let originalDuration = CMSampleBufferGetDuration(sampleBuffer)
        if CMTimeCompare(originalPTS, pts) == 0 {
            if let duration {
                if CMTimeCompare(originalDuration, duration) == 0 { return sampleBuffer }
            } else {
                return sampleBuffer
            }
        }

        var timing = CMSampleTimingInfo(
            duration: duration ?? originalDuration,
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid
        )
        var retimed: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &retimed
        )
        return status == noErr ? retimed : nil
    }

    private func videoOutputSettings() -> [String: Any] {
        let fps = configuration.frameRate
        let averageBitrate = RateControl.averageVideoBitrate(
            width: configuration.width,
            height: configuration.height,
            fps: fps,
            quality: configuration.quality,
            codec: configuration.codec
        )
        // AVAssetWriter passes VideoToolbox compression keys through to the encoder.
        var compression: [String: Any] = [
            AVVideoMaxKeyFrameIntervalKey: fps * 2,
            AVVideoAllowFrameReorderingKey: false,
            AVVideoExpectedSourceFrameRateKey: fps,
            kVTCompressionPropertyKey_Quality as String: Float(configuration.quality) / 100.0,
            kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality as String: true,
            AVVideoAverageBitRateKey: averageBitrate,
            kVTCompressionPropertyKey_DataRateLimits as String:
                RateControl.dataRateLimits(averageBitrate: averageBitrate)
        ]
        if configuration.codec == .h264 {
            compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
        } else {
            compression[AVVideoProfileLevelKey] = kVTProfileLevel_HEVC_Main_AutoLevel as String
        }

        let encodedWidth = (configuration.width + 1) & ~1
        let encodedHeight = (configuration.height + 1) & ~1
        var settings: [String: Any] = [
            AVVideoCodecKey: configuration.codec == .hevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: encodedWidth,
            AVVideoHeightKey: encodedHeight,
            AVVideoColorPropertiesKey: Self.sRGBColorProperties,
            AVVideoCompressionPropertiesKey: compression
        ]
        if encodedWidth != configuration.width || encodedHeight != configuration.height {
            settings[AVVideoCleanApertureKey] = [
                AVVideoCleanApertureWidthKey: configuration.width,
                AVVideoCleanApertureHeightKey: configuration.height,
                AVVideoCleanApertureHorizontalOffsetKey: 0,
                AVVideoCleanApertureVerticalOffsetKey: 0
            ]
        }
        return settings
    }

    /// Matches the sRGB capture buffers SCStream delivers (`colorSpaceName = sRGB`
    /// tags them 709 primaries / sRGB transfer / 709 matrix), so AVAssetWriter tags
    /// the output truthfully without a value-altering color conversion. The transfer
    /// string equals `AVVideoTransferFunction_IEC_sRGB`; the CoreVideo constant keeps
    /// the value shared with the capture buffer attachment.
    static let sRGBColorProperties: [String: String] = [
        AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
        AVVideoTransferFunctionKey: kCVImageBufferTransferFunction_sRGB as String,
        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
    ]

    private func audioOutputSettings() -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: configuration.audioBitrate.rawValue * 1_000
        ]
    }
}
