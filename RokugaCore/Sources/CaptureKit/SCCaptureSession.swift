import CoreMedia
import EffectsKit
import EncoderKit
import Foundation
import ScreenCaptureKit
import SettingsKit

public struct CaptureConfiguration: Equatable, Sendable {
    public var frameRate: FrameRate
    public var showsCursor: Bool
    public var captureSystemAudio: Bool
    public var exclusion: ExclusionOptions
    public var cursorEffects: CursorEffectOptions

    public init(
        frameRate: FrameRate,
        showsCursor: Bool,
        captureSystemAudio: Bool,
        exclusion: ExclusionOptions,
        cursorEffects: CursorEffectOptions = CursorEffectOptions(
            showCursor: true, pointerStyle: .system, highlight: false, animateClicks: false
        )
    ) {
        self.frameRate = frameRate
        self.showsCursor = showsCursor
        self.captureSystemAudio = captureSystemAudio
        self.exclusion = exclusion
        self.cursorEffects = cursorEffects
    }

    public static func fromSettings(_ settings: SettingsStore) -> Self {
        .init(
            frameRate: settings.frameRate,
            // The system cursor stays visible in the capture only on the zero-cost passthrough path; EffectsKit composites it otherwise (task 6.1).
            showsCursor: settings.showCursor && settings.pointerStyle == .system
                && !settings.highlightCursor && !settings.animateClicks,
            captureSystemAudio: settings.captureSystemAudio,
            exclusion: ExclusionOptions(
                excludeDesktopIcons: settings.excludeDesktopIcons
            ),
            cursorEffects: CursorEffectOptions.fromSettings(settings)
        )
    }
}

/// SCStream-backed implementation of `CaptureSession` (tasks 2.2/2.3/2.5).
public final class SCCaptureSession: NSObject, CaptureSession, @unchecked Sendable {
    private let target: CaptureTarget
    private let configuration: CaptureConfiguration
    private let sink: MediaSink
    private let onInterruption: @Sendable (Error?) -> Void

    private let sampleQueue = DispatchQueue(label: "io.rokuga.capture.samples", qos: .userInteractive)
    private let stateLock = NSLock()
    private var stream: SCStream?
    private var isPaused = false
    private var isStopping = false
    private var compositor: CursorCompositor?
    private var cursorSampler: CursorStateSampler?

    public init(
        target: CaptureTarget,
        configuration: CaptureConfiguration,
        sink: MediaSink,
        onInterruption: @escaping @Sendable (Error?) -> Void
    ) {
        self.target = target
        self.configuration = configuration
        self.sink = sink
        self.onInterruption = onInterruption
    }

    // MARK: CaptureSession

    public func start() async throws {
        let content = try await ShareableContentService.currentContent()
        guard let filter = ContentFilterBuilder.filter(
            for: target,
            content: content,
            exclusion: configuration.exclusion
        ) else {
            throw RecordingError.captureSourceLost
        }

        let streamConfiguration = makeStreamConfiguration()
        let stream = SCStream(filter: filter, configuration: streamConfiguration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        if configuration.captureSystemAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        }

        try await sink.start()
        try await stream.startCapture()
        stateLock.withLock { self.stream = stream }

        if !configuration.cursorEffects.isPassthrough {
            let sampler = CursorStateSampler()
            await sampler.start()
            let compositor = CursorCompositor(
                options: configuration.cursorEffects,
                geometry: frameGeometry(configuration: streamConfiguration),
                sampler: sampler
            ) { [weak self] in
                // GPU budget exhausted (task 6.2): fall back to the native cursor mid-stream.
                self?.fallBackToNativeCursor()
            }
            stateLock.withLock {
                self.cursorSampler = sampler
                self.compositor = compositor
            }
        }
    }

    /// Global-CG-coordinate rect of the captured content, used to map cursor positions into frame pixels.
    private func frameGeometry(configuration: SCStreamConfiguration) -> FrameGeometry {
        var contentRect = target.globalFrame
        if case let .display(display, crop) = target, let crop {
            contentRect = CGRect(
                x: display.frame.minX + crop.minX,
                y: display.frame.minY + crop.minY,
                width: crop.width,
                height: crop.height
            )
        }
        return FrameGeometry(
            contentRect: contentRect,
            pixelSize: CGSize(width: Int(configuration.width), height: Int(configuration.height))
        )
    }

    private func fallBackToNativeCursor() {
        guard let stream = stateLock.withLock({ self.stream }) else { return }
        let config = makeStreamConfiguration()
        config.showsCursor = true
        Task {
            try? await stream.updateConfiguration(config)
            let sampler = self.stateLock.withLock { () -> CursorStateSampler? in
                self.compositor = nil
                defer { self.cursorSampler = nil }
                return self.cursorSampler
            }
            if let sampler {
                await sampler.stop()
            }
        }
    }

    public func pause() async throws {
        stateLock.withLock { isPaused = true }
        sink.markPaused()
    }

    public func resume() async throws {
        sink.markResumed()
        stateLock.withLock { isPaused = false }
    }

    public func finish() async throws -> URL {
        let stream = stateLock.withLock { () -> SCStream? in
            isStopping = true
            defer { self.stream = nil }
            return self.stream
        }
        if let stream {
            // stopCapture throws if the stream already died (e.g. display unplug) — the sink still holds valid data, so finalize regardless.
            try? await stream.stopCapture()
        }
        await stopCursorSampling()
        return try await sink.finish()
    }

    public func cancel() async {
        let stream = stateLock.withLock { () -> SCStream? in
            isStopping = true
            defer { self.stream = nil }
            return self.stream
        }
        if let stream {
            try? await stream.stopCapture()
        }
        await stopCursorSampling()
        await sink.cancel()
    }

    private func stopCursorSampling() async {
        let sampler = stateLock.withLock { () -> CursorStateSampler? in
            compositor = nil
            defer { cursorSampler = nil }
            return cursorSampler
        }
        if let sampler {
            await sampler.stop()
        }
    }

    /// Re-resolves the content filter so newly created windows (e.g. the floating thumbnail) honor the exclusion rules mid-recording (task 2.4).
    public func refreshContentFilter() async {
        guard let stream = stateLock.withLock({ self.stream }) else { return }
        guard let content = try? await ShareableContentService.currentContent(),
              let filter = ContentFilterBuilder.filter(
                  for: target,
                  content: content,
                  exclusion: configuration.exclusion
              )
        else { return }
        try? await stream.updateContentFilter(filter)
    }

    // MARK: Stream configuration

    private func makeStreamConfiguration() -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        let source = target.sourcePixelSize
        let clamped = CaptureLimits.clamped(width: source.width, height: source.height)
        config.width = clamped.width
        config.height = clamped.height
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(configuration.frameRate.rawValue))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = configuration.showsCursor
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
            config.sampleRate = 48_000
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
        guard sampleBuffer.isValid else { return }
        let paused = stateLock.withLock { isPaused || isStopping }
        guard !paused else { return }

        switch type {
        case .screen:
            guard isCompleteVideoFrame(sampleBuffer) else { return }
            let compositor = stateLock.withLock { self.compositor }
            sink.append(compositor?.composite(sampleBuffer) ?? sampleBuffer, of: .video)
        case .audio:
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
