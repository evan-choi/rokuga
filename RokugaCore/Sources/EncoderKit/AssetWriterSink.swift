import AVFoundation
import CoreMedia
import Foundation
import SettingsKit
import VideoToolbox

/// AVAssetWriter-backed `MediaSink` (task 3.1).
///
/// Video: SCStream's IOSurface-backed BGRA buffers are appended untouched — VideoToolbox reads them zero-copy, no CPU pixel path.
/// Audio: one mixed AAC track by default, or independent system/microphone tracks in MOV.
public final class AssetWriterSink: MediaSink, @unchecked Sendable {
    private let outputURL: URL
    private let configuration: EncoderConfiguration

    private let queue = DispatchQueue(label: "io.rokuga.encoder.writer", qos: .userInteractive)
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var systemAudioInput: AVAssetWriterInput?
    private var microphoneInput: AVAssetWriterInput?
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

        let outputExisted = FileManager.default.fileExists(atPath: outputURL.path)
        var preparedWriter: AVAssetWriter?
        do {
            let fileType: AVFileType = configuration.container == .mov ? .mov : .mp4
            let writer = try AVAssetWriter(outputURL: outputURL, fileType: fileType)
            preparedWriter = writer
            if configuration.container == .mov {
                // Fragmented QuickTime keeps partials playable after a crash or power loss (task 3.6); AVAssetWriter only supports this for .mov.
                writer.movieFragmentInterval = CMTime(value: 2, timescale: 1)
            }

            let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoOutputSettings())
            videoInput.expectsMediaDataInRealTime = true
            try add(videoInput, named: "video", to: writer)

            if configuration.audioTrackLayout == .separate {
                if configuration.capturesSystemAudio {
                    let input = makeAudioInput(title: "System Audio")
                    try add(input, named: "system audio", to: writer)
                    systemAudioInput = input
                }
                if configuration.capturesMicrophone {
                    let input = makeAudioInput(title: "Microphone")
                    try add(input, named: "microphone", to: writer)
                    microphoneInput = input
                }
            } else if configuration.capturesSystemAudio || configuration.capturesMicrophone {
                let input = makeAudioInput()
                try add(input, named: "audio", to: writer)
                audioInput = input
                if configuration.capturesSystemAudio, configuration.capturesMicrophone {
                    mixer = AudioMixer()
                }
            }

            guard writer.startWriting() else {
                throw RecordingSinkError.writerFailed(writer.error?.localizedDescription ?? "startWriting")
            }
            self.writer = writer
            self.videoInput = videoInput
        } catch {
            preparedWriter?.cancelWriting()
            audioInput = nil
            systemAudioInput = nil
            microphoneInput = nil
            mixer = nil
            if !outputExisted {
                try? FileManager.default.removeItem(at: outputURL)
            }
            throw error
        }
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
                if collectsDetailedStatistics {
                    statistics.videoFramesReceived += 1
                }
                appendVideo(sampleBuffer)
            case .systemAudio:
                if collectsDetailedStatistics {
                    statistics.audioSamplesReceived += 1
                }
                appendSystemAudio(sampleBuffer)
            case .microphone:
                if collectsDetailedStatistics {
                    statistics.audioSamplesReceived += 1
                }
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
        let requestedAt = DispatchTime.now().uptimeNanoseconds
        let writer: AVAssetWriter? = await withCheckedContinuation { continuation in
            queue.async { [self] in
                stopConstantFrameOutput(clearFrame: false)
                let endPTS: CMTime?
                if let lastVideoPTS, let lastVideoUptimeNanoseconds {
                    let endUptimeNanoseconds = pauseUptimeNanoseconds ?? requestedAt
                    let elapsed = endUptimeNanoseconds > lastVideoUptimeNanoseconds
                        ? endUptimeNanoseconds - lastVideoUptimeNanoseconds
                        : 0
                    endPTS = CMTimeAdd(
                        lastVideoPTS,
                        CMTime(value: CMTimeValue(elapsed), timescale: 1_000_000_000)
                    )
                } else {
                    endPTS = nil
                }
                finishConstantFrameOutput(until: endPTS) { [self] in
                    if let endPTS {
                        self.writer?.endSession(atSourceTime: endPTS)
                    }
                    stopConstantFrameOutput(clearFrame: true)
                    videoInput?.markAsFinished()
                    audioInput?.markAsFinished()
                    systemAudioInput?.markAsFinished()
                    microphoneInput?.markAsFinished()
                    continuation.resume(returning: self.writer)
                }
            }
        }
        guard let writer else { throw RecordingSinkError.notStarted }
        if let terminalError {
            throw terminalError
        }

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

    @discardableResult
    private func appendVideoSample(_ sampleBuffer: CMSampleBuffer, at pts: CMTime, duration: CMTime? = nil) -> Bool {
        guard let writer, let videoInput, terminalError == nil else { return false }
        guard videoInput.isReadyForMoreMediaData,
              let retimed = retime(sampleBuffer, to: pts, duration: duration)
        else {
            statistics.videoFramesDropped += 1
            return false
        }
        if videoInput.append(retimed) {
            statistics.videoFramesAppended += 1
            return true
        } else {
            terminalError = RecordingSinkError.writerFailed(writer.error?.localizedDescription ?? "video append")
            return false
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
        if videoInput?.isReadyForMoreMediaData == true,
           appendVideoSample(sampleBuffer, at: outputPTS, duration: duration) {
            nextConstantFramePTS = CMTimeAdd(outputPTS, duration)
        } else {
            nextConstantFramePTS = outputPTS
        }
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
              let pts = nextConstantFramePTS,
              videoInput?.isReadyForMoreMediaData == true
        else { return }
        if appendVideoSample(sampleBuffer, at: pts, duration: constantFrameDuration) {
            nextConstantFramePTS = CMTimeAdd(pts, constantFrameDuration)
        }
    }

    private func finishConstantFrameOutput(until endPTS: CMTime?, completion: @escaping @Sendable () -> Void) {
        guard configuration.frameRateMode == .constant,
              let endPTS,
              let sampleBuffer = latestConstantFrame,
              var pts = nextConstantFramePTS
        else {
            completion()
            return
        }

        while CMTimeCompare(pts, endPTS) < 0,
              videoInput?.isReadyForMoreMediaData == true,
              appendVideoSample(sampleBuffer, at: pts, duration: constantFrameDuration) {
            pts = CMTimeAdd(pts, constantFrameDuration)
        }
        nextConstantFramePTS = pts

        guard CMTimeCompare(pts, endPTS) < 0,
              terminalError == nil,
              writer?.status == .writing
        else {
            completion()
            return
        }
        queue.asyncAfter(deadline: .now() + .milliseconds(1)) { [self] in
            finishConstantFrameOutput(until: endPTS, completion: completion)
        }
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
}

extension AssetWriterSink {
    // MARK: Audio path

    private func appendSystemAudio(_ sampleBuffer: CMSampleBuffer) {
        let targetInput = configuration.audioTrackLayout == .separate ? systemAudioInput : audioInput
        guard sessionStarted, let targetInput, terminalError == nil else { return }
        let sourcePTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let adjustedPTS = spliceClock.adjusted(sourcePTS)
        spliceClock.observe(pts: sourcePTS, duration: CMSampleBufferGetDuration(sampleBuffer))

        guard targetInput.isReadyForMoreMediaData else { return }

        if let mixer {
            guard let pcm = AudioSampleBufferFactory.pcmBuffer(from: sampleBuffer),
                  let mixed = mixer.mix(system: pcm),
                  let retimed = AudioSampleBufferFactory.sampleBuffer(from: mixed, presentationTime: adjustedPTS)
            else { return }
            appendAudio(retimed, to: targetInput)
        } else if let retimed = retime(sampleBuffer, to: adjustedPTS) {
            appendAudio(retimed, to: targetInput)
        }
    }

    private func appendMicrophone(_ sampleBuffer: CMSampleBuffer) {
        guard terminalError == nil else { return }

        if let mixer {
            guard let pcm = AudioSampleBufferFactory.pcmBuffer(from: sampleBuffer) else { return }
            mixer.enqueueMicrophone(pcm)
            return
        }

        let targetInput = configuration.audioTrackLayout == .separate ? microphoneInput : audioInput
        guard sessionStarted, let targetInput, targetInput.isReadyForMoreMediaData else { return }
        let sourcePTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let adjustedPTS = spliceClock.adjusted(sourcePTS)
        spliceClock.observe(pts: sourcePTS, duration: CMSampleBufferGetDuration(sampleBuffer))
        if let retimed = retime(sampleBuffer, to: adjustedPTS) {
            appendAudio(retimed, to: targetInput)
        }
    }

    private func appendAudio(_ sampleBuffer: CMSampleBuffer, to input: AVAssetWriterInput) {
        guard let writer else { return }
        if !input.append(sampleBuffer) {
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
                if CMTimeCompare(originalDuration, duration) == 0 {
                    return sampleBuffer
                }
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

    private func add(_ input: AVAssetWriterInput, named name: String, to writer: AVAssetWriter) throws {
        guard writer.canAdd(input) else {
            throw RecordingSinkError.writerFailed("cannot add \(name) input")
        }
        writer.add(input)
    }

    private func makeAudioInput(title: String? = nil) -> AVAssetWriterInput {
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioOutputSettings())
        input.expectsMediaDataInRealTime = true
        if let title {
            let metadata = AVMutableMetadataItem()
            metadata.identifier = .quickTimeMetadataTitle
            metadata.value = title as NSString
            metadata.extendedLanguageTag = "und"
            input.metadata = [metadata]
        }
        return input
    }

    func audioOutputSettings() -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: configuration.audioBitrate.rawValue * 1000
        ]
    }
}
