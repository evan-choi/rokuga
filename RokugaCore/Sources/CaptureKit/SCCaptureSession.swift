import CoreMedia
import EffectsKit
import EncoderKit
import Foundation
import ScreenCaptureKit
import SettingsKit

public struct CaptureConfiguration: Equatable, Sendable {
    public var frameRate: Int
    public var captureSystemAudio: Bool
    public var exclusion: ExclusionOptions
    public var cursorEffects: CursorEffectOptions

    /// ScreenCaptureKit owns the system pointer for the entire stream. Custom dot
    /// pointers remain owned by EffectsKit for the entire stream.
    public var showsCursor: Bool {
        cursorEffects.usesNativeSystemCursor
    }

    public init(
        frameRate: Int,
        captureSystemAudio: Bool,
        exclusion: ExclusionOptions,
        cursorEffects: CursorEffectOptions = CursorEffectOptions(
            showCursor: true, pointerStyle: .system, highlight: false, animateClicks: false
        )
    ) {
        self.frameRate = max(frameRate, 1)
        self.captureSystemAudio = captureSystemAudio
        self.exclusion = exclusion
        self.cursorEffects = cursorEffects
    }

    public static func fromSettings(_ settings: SettingsStore, frameRate: Int? = nil) -> Self {
        .init(
            frameRate: frameRate ?? settings.frameRate.resolved(displayRefreshRate: nil),
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

        await prepareCursorEffects(configuration: streamConfiguration)

        do {
            try await sink.start()
            try await stream.startCapture()
            stateLock.withLock { self.stream = stream }
        } catch {
            try? await stream.stopCapture()
            await stopCursorSampling()
            await sink.cancel()
            throw error
        }
    }

    private func prepareCursorEffects(configuration streamConfiguration: SCStreamConfiguration) async {
        guard configuration.cursorEffects.needsCompositor else { return }

        let sampler = CursorStateSampler(
            framesPerSecond: configuration.frameRate
        )
        await sampler.start()
        let compositor = CursorCompositor(
            options: configuration.cursorEffects,
            geometry: frameGeometry(configuration: streamConfiguration),
            sampler: sampler
        ) { [weak self] in
            self?.finishCursorEffectDegradation()
        }
        stateLock.withLock {
            cursorSampler = sampler
            self.compositor = compositor
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

    private func finishCursorEffectDegradation() {
        // A custom dot still needs the compositor at the cursor-only level. Native
        // system pointers are already present in every SCStream frame, so all custom
        // effects can be detached without a cursor-ownership handoff.
        guard !configuration.cursorEffects.compositesPointer else { return }

        let sampler = stateLock.withLock { () -> CursorStateSampler? in
            compositor = nil
            defer { cursorSampler = nil }
            return cursorSampler
        }
        if let sampler {
            Task { await sampler.stop() }
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
        guard sampleBuffer.isValid else { return }
        let paused = stateLock.withLock { isPaused || isStopping }
        guard !paused else { return }

        switch type {
        case .screen:
            guard isCompleteVideoFrame(sampleBuffer) else { return }
            let compositor = stateLock.withLock { self.compositor }
            let geometry = Self.frameGeometry(from: sampleBuffer)
            sink.append(compositor?.composite(sampleBuffer, geometry: geometry) ?? sampleBuffer, of: .video)
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

    private static func frameGeometry(from sampleBuffer: CMSampleBuffer) -> FrameGeometry? {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
              as? [[SCStreamFrameInfo: Any]],
              let frameInfo = attachments.first
        else { return nil }

        return frameGeometry(
            frameInfo: frameInfo,
            pixelSize: CGSize(
                width: CVPixelBufferGetWidth(imageBuffer),
                height: CVPixelBufferGetHeight(imageBuffer)
            )
        )
    }

    static func frameGeometry(
        frameInfo: [SCStreamFrameInfo: Any],
        pixelSize: CGSize
    ) -> FrameGeometry? {
        guard let screenRect = frameInfo[.screenRect] as? CGRect,
              let surfaceRect = frameInfo[.contentRect] as? CGRect,
              let scaleFactor = frameInfo[.scaleFactor] as? CGFloat,
              screenRect.width > 0,
              screenRect.height > 0,
              scaleFactor > 0
        else { return nil }

        let pixelContentRect = CGRect(
            x: surfaceRect.minX * scaleFactor,
            y: surfaceRect.minY * scaleFactor,
            width: surfaceRect.width * scaleFactor,
            height: surfaceRect.height * scaleFactor
        ).intersection(CGRect(origin: .zero, size: pixelSize))
        guard !pixelContentRect.isNull, !pixelContentRect.isEmpty else { return nil }

        return FrameGeometry(
            contentRect: screenRect,
            pixelSize: pixelSize,
            pixelContentRect: pixelContentRect
        )
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
