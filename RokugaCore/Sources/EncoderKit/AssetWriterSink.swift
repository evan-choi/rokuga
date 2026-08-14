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

    /// Drop accounting feeds the perf gates (task 10.2: 4K60 drop-rate < 0.1%).
    public struct Statistics: Equatable, Sendable {
        public var videoFramesAppended = 0
        public var videoFramesDropped = 0
    }

    public func statisticsSnapshot() -> Statistics {
        queue.sync { statistics }
    }

    public init(outputURL: URL, configuration: EncoderConfiguration) {
        self.outputURL = outputURL
        self.configuration = configuration
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
        queue.async { [self] in
            switch kind {
            case .video:
                appendVideo(sampleBuffer)
            case .systemAudio:
                appendSystemAudio(sampleBuffer)
            case .microphone:
                appendMicrophone(sampleBuffer)
            }
        }
    }

    public func markPaused() {
        queue.async { [self] in
            spliceClock.markPaused()
        }
    }

    public func markResumed() {}

    public func finish() async throws -> URL {
        let writer: AVAssetWriter? = await withCheckedContinuation { continuation in
            queue.async { [self] in
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
                writer?.cancelWriting()
                try? FileManager.default.removeItem(at: outputURL)
                continuation.resume()
            }
        }
    }

    // MARK: Video path

    private func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        guard let writer, let videoInput, terminalError == nil else { return }

        let sourcePTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let adjustedPTS = spliceClock.adjusted(sourcePTS)
        spliceClock.observe(pts: sourcePTS, duration: CMSampleBufferGetDuration(sampleBuffer))

        if !sessionStarted {
            writer.startSession(atSourceTime: adjustedPTS)
            sessionStarted = true
        }

        guard videoInput.isReadyForMoreMediaData, let retimed = retime(sampleBuffer, to: adjustedPTS) else {
            statistics.videoFramesDropped += 1
            return
        }
        if videoInput.append(retimed) {
            statistics.videoFramesAppended += 1
        } else {
            terminalError = RecordingSinkError.writerFailed(writer.error?.localizedDescription ?? "video append")
        }
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

    private func retime(_ sampleBuffer: CMSampleBuffer, to pts: CMTime) -> CMSampleBuffer? {
        let originalPTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if CMTimeCompare(originalPTS, pts) == 0 { return sampleBuffer }

        var timing = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(sampleBuffer),
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
        let fps = configuration.frameRate.rawValue
        let averageBitrate = RateControl.averageVideoBitrate(
            width: configuration.width,
            height: configuration.height,
            fps: fps,
            quality: configuration.quality,
            codec: configuration.codec
        )

        // AVFoundation has no public data-rate-limits constant; AVAssetWriter documents passthrough of VideoToolbox compression keys.
        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: averageBitrate,
            kVTCompressionPropertyKey_DataRateLimits as String: RateControl.dataRateLimits(averageBitrate: averageBitrate),
            AVVideoMaxKeyFrameIntervalKey: fps * 2,
            AVVideoAllowFrameReorderingKey: false,
            AVVideoExpectedSourceFrameRateKey: fps,
        ]
        if configuration.codec == .h264 {
            compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
        }

        return [
            AVVideoCodecKey: configuration.codec == .hevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: configuration.width,
            AVVideoHeightKey: configuration.height,
            AVVideoCompressionPropertiesKey: compression,
        ]
    }

    private func audioOutputSettings() -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: configuration.audioBitrate.rawValue * 1_000,
        ]
    }
}
