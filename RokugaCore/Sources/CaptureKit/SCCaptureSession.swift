import CoreMedia
import EncoderKit
import Foundation
import ScreenCaptureKit
import SettingsKit

public struct CaptureConfiguration: Equatable, Sendable {
    public var frameRate: Int
    public var captureSystemAudio: Bool
    public var exclusion: ExclusionOptions
    public var showsCursor: Bool
    public var showMouseClicks: Bool

    public init(
        frameRate: Int,
        captureSystemAudio: Bool,
        exclusion: ExclusionOptions,
        showsCursor: Bool = true,
        showMouseClicks: Bool = false
    ) {
        self.frameRate = max(frameRate, 1)
        self.captureSystemAudio = captureSystemAudio
        self.exclusion = exclusion
        self.showsCursor = showsCursor
        self.showMouseClicks = showMouseClicks
    }

    public static func fromSettings(_ settings: SettingsStore, frameRate: Int? = nil) -> Self {
        .init(
            frameRate: frameRate ?? settings.frameRate.resolved(displayRefreshRate: nil),
            captureSystemAudio: settings.captureSystemAudio,
            exclusion: ExclusionOptions(
                excludeDesktopIcons: settings.excludeDesktopIcons
            ),
            showsCursor: settings.showCursor,
            showMouseClicks: settings.animateClicks
        )
    }
}

public final class CaptureMetrics: @unchecked Sendable {
    public struct Snapshot: Equatable, Sendable {
        public var videoCallbacks = 0
        public var completeVideoFrames = 0
        public var incompleteVideoFrames = 0
        public var invalidSamples = 0
        public var audioCallbacks = 0
        public var duplicatePTS = 0
        public var gapPTS = 0
        public var missingVideoFrames = 0
        public var maxPTSGapSeconds = 0.0
        public var firstCompleteFrameUptimeNanoseconds: UInt64?
    }

    private let expectedFrameSeconds: Double
    private let lock = NSLock()
    private var snapshot = Snapshot()
    private var lastVideoPTS: CMTime?

    public init(frameRate: Int) {
        expectedFrameSeconds = 1.0 / Double(max(frameRate, 1))
    }

    public func currentSnapshot() -> Snapshot {
        lock.withLock { snapshot }
    }

    func recordInvalidSample() {
        lock.withLock { snapshot.invalidSamples += 1 }
    }

    func recordVideoCallback() {
        lock.withLock { snapshot.videoCallbacks += 1 }
    }

    func recordIncompleteVideoFrame() {
        lock.withLock { snapshot.incompleteVideoFrames += 1 }
    }

    func recordCompleteVideoFrame(pts: CMTime) {
        lock.withLock {
            snapshot.completeVideoFrames += 1
            if snapshot.firstCompleteFrameUptimeNanoseconds == nil {
                snapshot.firstCompleteFrameUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
            }
            if let lastVideoPTS {
                let delta = CMTimeSubtract(pts, lastVideoPTS).seconds
                if delta <= 0 {
                    snapshot.duplicatePTS += 1
                } else if delta > expectedFrameSeconds * 1.5 {
                    snapshot.gapPTS += 1
                    snapshot.missingVideoFrames += max(Int((delta / expectedFrameSeconds).rounded()) - 1, 1)
                    snapshot.maxPTSGapSeconds = max(snapshot.maxPTSGapSeconds, delta)
                }
            }
            lastVideoPTS = pts
        }
    }

    func recordAudioCallback() {
        lock.withLock { snapshot.audioCallbacks += 1 }
    }
}

/// SCStream-backed implementation of `CaptureSession` (tasks 2.2/2.3/2.5).
public final class SCCaptureSession: NSObject, CaptureSession, @unchecked Sendable {
    private let target: CaptureTarget
    private let configuration: CaptureConfiguration
    private let sink: MediaSink
    private let microphoneCapture: MicrophoneCapture?
    private let metrics: CaptureMetrics?
    private let onInterruption: @Sendable (Error?) -> Void

    private let sampleQueue = DispatchQueue(label: "io.rokuga.capture.samples", qos: .userInteractive)
    private let stateLock = NSLock()
    private var stream: SCStream?
    private var isPaused = false
    private var isStopping = false

    public init(
        target: CaptureTarget,
        configuration: CaptureConfiguration,
        sink: MediaSink,
        microphoneCapture: MicrophoneCapture? = nil,
        metrics: CaptureMetrics? = nil,
        onInterruption: @escaping @Sendable (Error?) -> Void
    ) {
        self.target = target
        self.configuration = configuration
        self.sink = sink
        self.microphoneCapture = microphoneCapture
        self.metrics = metrics
        self.onInterruption = onInterruption
    }

    // MARK: CaptureSession

    public func start() async throws {
        var stream: SCStream?
        do {
            async let sinkStart: Void = sink.start()
            let content = try await ShareableContentService.currentContent()
            guard let filter = ContentFilterBuilder.filter(
                for: target,
                content: content,
                exclusion: configuration.exclusion
            ) else {
                throw RecordingError.captureSourceLost
            }

            let preparedStream = SCStream(filter: filter, configuration: makeStreamConfiguration(), delegate: self)
            stream = preparedStream
            try preparedStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
            if configuration.captureSystemAudio {
                try preparedStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
            }

            try await sinkStart
            try await preparedStream.startCapture()
            try microphoneCapture?.start(sink: sink)
            stateLock.withLock { self.stream = preparedStream }
        } catch {
            microphoneCapture?.stop()
            if let stream {
                try? await stream.stopCapture()
            }
            await sink.cancel()
            throw error
        }
    }

    public func pause() async throws {
        stateLock.withLock { isPaused = true }
        microphoneCapture?.pause()
        sink.markPaused()
    }

    public func resume() async throws {
        sink.markResumed()
        microphoneCapture?.resume()
        stateLock.withLock { isPaused = false }
    }

    public func finish() async throws -> URL {
        let stream = stateLock.withLock { () -> SCStream? in
            isStopping = true
            defer { self.stream = nil }
            return self.stream
        }
        microphoneCapture?.stop()
        if let stream {
            // stopCapture throws if the stream already died (e.g. display unplug) — the sink still holds valid data, so finalize regardless.
            try? await stream.stopCapture()
        }
        return try await sink.finish()
    }

    public func cancel() async {
        let stream = stateLock.withLock { () -> SCStream? in
            isStopping = true
            defer { self.stream = nil }
            return self.stream
        }
        microphoneCapture?.stop()
        if let stream {
            try? await stream.stopCapture()
        }
        await sink.cancel()
    }

    // MARK: Stream configuration

    func makeStreamConfiguration() -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        let source = target.sourcePixelSize
        let clamped = CaptureLimits.clamped(width: source.width, height: source.height)
        config.width = clamped.width
        config.height = clamped.height
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(configuration.frameRate))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        // Without an explicit color space, SCStream delivers buffers in the display's
        // ICC color space, which no standard video color tag can describe — the file
        // then carries no color metadata and players guess. sRGB makes ScreenCaptureKit
        // color-match at the source and tag buffers 709 primaries / sRGB transfer /
        // 709 matrix, which AssetWriterSink records verbatim (color-fidelity fix).
        config.colorSpaceName = CGColorSpace.sRGB
        config.showsCursor = configuration.showsCursor
        if #available(macOS 15.0, *) {
            config.showMouseClicks = configuration.showMouseClicks
        }
        config.queueDepth = 8

        if case let .display(_, crop) = target, let crop {
            config.sourceRect = crop
        }
        if case .window = target {
            // Mid-recording window resizes shrink-to-fit instead of cropping (recording-modes spec).
            config.scalesToFit = true
        }

        if configuration.captureSystemAudio {
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
            config.sampleRate = 48000
            config.channelCount = 2
        }
        return config
    }
}

// MARK: - SCStreamOutput

extension SCCaptureSession: SCStreamOutput {
    public func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard sampleBuffer.isValid else {
            metrics?.recordInvalidSample()
            return
        }
        let paused = stateLock.withLock { isPaused || isStopping }
        guard !paused else { return }

        switch type {
        case .screen:
            metrics?.recordVideoCallback()
            guard isCompleteVideoFrame(sampleBuffer) else {
                metrics?.recordIncompleteVideoFrame()
                return
            }
            metrics?.recordCompleteVideoFrame(
                pts: CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            )
            sink.append(sampleBuffer, of: .video)
        case .audio:
            metrics?.recordAudioCallback()
            sink.append(sampleBuffer, of: .systemAudio)
        default:
            break
        }
    }

    private func isCompleteVideoFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
            as? [[SCStreamFrameInfo: Any]],
            let statusRaw = attachments.first?[.status] as? Int,
            let status = SCFrameStatus(rawValue: statusRaw)
        else { return false }
        return status == .complete
    }
}

// MARK: - SCStreamDelegate (task 2.5 — source disconnect)

extension SCCaptureSession: SCStreamDelegate {
    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        let alreadyStopping = stateLock.withLock { () -> Bool in
            defer { self.stream = nil }
            return isStopping
        }
        guard !alreadyStopping else { return }
        onInterruption(error)
    }
}
