import AVFoundation
import CaptureKit
import CoreGraphics
import CoreMedia
import EncoderKit
import EffectsKit
import Foundation
import ScreenCaptureKit
import SettingsKit

enum RecordCommand {
    static func run(arguments: [String]) async throws -> RecordResult {
        let options = try RecordOptions(arguments)
        let target = try await captureTarget(windowPID: options.windowPID)
        let sourceSize = target.sourcePixelSize
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rokuga-perf-\(UUID().uuidString).mov")
        let encoderConfiguration = EncoderConfiguration(
            codec: options.codec,
            container: .mov,
            width: sourceSize.width,
            height: sourceSize.height,
            frameRate: options.fps,
            frameRateMode: options.frameRateMode,
            quality: 80,
            audioBitrate: .kbps192,
            capturesSystemAudio: options.systemAudio,
            capturesMicrophone: false
        )
        let captureConfiguration = CaptureConfiguration(
            frameRate: options.fps,
            captureSystemAudio: options.systemAudio,
            exclusion: ExclusionOptions(excludeDesktopIcons: false),
            cursorEffects: options.cursorEffects
        )
        let sink = AssetWriterSink(
            outputURL: outputURL,
            configuration: encoderConfiguration,
            collectsDetailedStatistics: true
        )
        let captureMetrics = CaptureMetrics(frameRate: options.fps)
        let coordinator = RecordingCoordinator { _ in
            SCCaptureSession(
                target: target,
                configuration: captureConfiguration,
                sink: sink,
                metrics: captureMetrics,
                onInterruption: { _ in }
            )
        }

        let requestStart = DispatchTime.now().uptimeNanoseconds
        let cpuStart = cpuSecondsUsed()
        try await coordinator.start(mode: target.recordingMode, countdown: .off)
        do {
            try await waitForFirstFrame(in: captureMetrics)
            try await Task.sleep(nanoseconds: UInt64(options.seconds * 1_000_000_000))
        } catch {
            await coordinator.cancel()
            throw error
        }
        let finishStart = CFAbsoluteTimeGetCurrent()
        let finalizedURL = try await coordinator.stop()
        let finishSeconds = CFAbsoluteTimeGetCurrent() - finishStart
        let wallSeconds = Double(DispatchTime.now().uptimeNanoseconds - requestStart) / 1_000_000_000
        let cpuSeconds = cpuSecondsUsed() - cpuStart

        let capture = captureMetrics.currentSnapshot()
        let writer = sink.statisticsSnapshot()
        let output = try await inspectOutput(finalizedURL, expectedFPS: options.fps)
        let firstFrameSeconds = capture.firstCompleteFrameUptimeNanoseconds.map {
            Double($0 - requestStart) / 1_000_000_000
        }

        return RecordResult(
            command: "record",
            outputPath: finalizedURL.path,
            target: options.windowPID == nil ? "display" : "window",
            width: sourceSize.width,
            height: sourceSize.height,
            fps: options.fps,
            seconds: options.seconds,
            codec: options.codec.rawValue,
            frameRateMode: options.frameRateMode.rawValue,
            systemAudio: options.systemAudio,
            effects: options.effects,
            wallSeconds: wallSeconds,
            cpuPercentOfOneCore: cpuSeconds / wallSeconds * 100,
            peakMemoryMB: Double(peakMemoryBytes()) / 1_048_576,
            recordToFirstFrameSeconds: firstFrameSeconds,
            stopToPlayableSeconds: finishSeconds,
            capture: CaptureResult(capture),
            writer: WriterResult(writer),
            output: output
        )
    }

    private static func captureTarget(windowPID: pid_t?) async throws -> CaptureTarget {
        let content = try await ShareableContentService.currentContent()
        if let windowPID {
            guard let window = content.windows.first(where: {
                $0.owningApplication?.processID == windowPID && $0.frame.width > 0 && $0.frame.height > 0
            }), let app = window.owningApplication else {
                throw PerfError.captureTargetNotFound
            }
            return .window(WindowTarget(
                windowID: window.windowID,
                title: window.title,
                appName: app.applicationName,
                appBundleID: app.bundleIdentifier,
                appPID: app.processID,
                frame: window.frame
            ))
        }

        let mainDisplayID = CGMainDisplayID()
        guard let display = content.displays.first(where: { $0.displayID == mainDisplayID }) else {
            throw PerfError.captureTargetNotFound
        }
        return .display(DisplayTarget(
            displayID: display.displayID,
            frame: CGDisplayBounds(display.displayID),
            pixelWidth: display.width,
            pixelHeight: display.height
        ), crop: nil)
    }

    private static func waitForFirstFrame(in metrics: CaptureMetrics) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + 5_000_000_000
        while metrics.currentSnapshot().firstCompleteFrameUptimeNanoseconds == nil {
            guard DispatchTime.now().uptimeNanoseconds < deadline else {
                throw PerfError.firstFrameTimeout
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    private static func inspectOutput(_ url: URL, expectedFPS: Int) async throws -> OutputResult {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else { throw PerfError.captureTargetNotFound }
        let size = try await videoTrack.load(.naturalSize)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
        reader.add(output)
        reader.startReading()

        var frames = 0
        var duplicatePTS = 0
        var gapPTS = 0
        var maxPTSGapSeconds = 0.0
        var lastPTS: CMTime?
        let expectedFrameSeconds = 1.0 / Double(max(expectedFPS, 1))
        while let sample = output.copyNextSampleBuffer() {
            let pts = CMSampleBufferGetPresentationTimeStamp(sample)
            if let lastPTS {
                let delta = CMTimeSubtract(pts, lastPTS).seconds
                if delta <= 0 {
                    duplicatePTS += 1
                } else if delta > expectedFrameSeconds * 1.5 {
                    gapPTS += 1
                    maxPTSGapSeconds = max(maxPTSGapSeconds, delta)
                }
            }
            lastPTS = pts
            frames += 1
        }
        if reader.status == .failed { throw reader.error ?? PerfError.captureTargetNotFound }

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let audioDuration = try await audioTracks.first?.load(.timeRange).duration.seconds
        let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        return OutputResult(
            durationSeconds: duration,
            width: Int(abs(size.width)),
            height: Int(abs(size.height)),
            videoFrames: frames,
            duplicatePTS: duplicatePTS,
            gapPTS: gapPTS,
            maxPTSGapSeconds: maxPTSGapSeconds,
            audioDurationSeconds: audioDuration,
            audioVideoDriftSeconds: audioDuration.map { abs($0 - duration) },
            fileSizeBytes: fileSize
        )
    }
}

private struct RecordOptions {
    var seconds = 10.0
    var fps = 60
    var codec = VideoCodec.hevc
    var frameRateMode = FrameRateMode.variable
    var systemAudio = false
    var effects = false
    var windowPID: pid_t?

    var cursorEffects: CursorEffectOptions {
        if effects {
            return CursorEffectOptions(showCursor: true, pointerStyle: .dot, highlight: true, animateClicks: true)
        }
        return CursorEffectOptions(showCursor: true, pointerStyle: .system, highlight: false, animateClicks: false)
    }

    init(_ arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            let flag = arguments[index]
            guard index + 1 < arguments.count else { throw PerfError.invalidArgument("missing value for \(flag)") }
            let value = arguments[index + 1]
            switch flag {
            case "--seconds":
                guard let parsed = Double(value), parsed.isFinite, parsed > 0 else {
                    throw PerfError.invalidArgument("invalid seconds: \(value)")
                }
                seconds = parsed
            case "--fps":
                guard let parsed = Int(value), (1...240).contains(parsed) else {
                    throw PerfError.invalidArgument("invalid fps: \(value)")
                }
                fps = parsed
            case "--codec":
                guard let parsed = VideoCodec(rawValue: value) else {
                    throw PerfError.invalidArgument("invalid codec: \(value)")
                }
                codec = parsed
            case "--frame-rate-mode":
                guard let parsed = FrameRateMode(rawValue: value) else {
                    throw PerfError.invalidArgument("invalid frame-rate-mode: \(value)")
                }
                frameRateMode = parsed
            case "--system-audio":
                systemAudio = try Self.boolean(value, name: flag)
            case "--effects":
                effects = try Self.boolean(value, name: flag)
            case "--window-pid":
                guard let parsed = pid_t(value), parsed > 0 else {
                    throw PerfError.invalidArgument("invalid window pid: \(value)")
                }
                windowPID = parsed
            default:
                throw PerfError.invalidArgument("unknown option: \(flag)")
            }
            index += 2
        }
    }

    private static func boolean(_ value: String, name: String) throws -> Bool {
        switch value {
        case "on": true
        case "off": false
        default: throw PerfError.invalidArgument("invalid \(name): \(value)")
        }
    }
}

private extension CaptureTarget {
    var recordingMode: RecordingMode {
        switch self {
        case .display: .fullScreen
        case .window: .window
        }
    }
}

private func cpuSecondsUsed() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
    let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
    return user + system
}

private func peakMemoryBytes() -> Int64 {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return Int64(usage.ru_maxrss)
}

struct RecordResult: Codable {
    let command: String
    let outputPath: String
    let target: String
    let width: Int
    let height: Int
    let fps: Int
    let seconds: Double
    let codec: String
    let frameRateMode: String
    let systemAudio: Bool
    let effects: Bool
    let wallSeconds: Double
    let cpuPercentOfOneCore: Double
    let peakMemoryMB: Double
    let recordToFirstFrameSeconds: Double?
    let stopToPlayableSeconds: Double
    let capture: CaptureResult
    let writer: WriterResult
    let output: OutputResult
}

struct CaptureResult: Codable {
    let videoCallbacks: Int
    let completeVideoFrames: Int
    let incompleteVideoFrames: Int
    let invalidSamples: Int
    let audioCallbacks: Int
    let duplicatePTS: Int
    let gapPTS: Int
    let maxPTSGapSeconds: Double
    let compositeCalls: Int
    let averageCompositeSeconds: Double
    let maxCompositeSeconds: Double
    let effectDegradations: Int

    init(_ snapshot: CaptureMetrics.Snapshot) {
        videoCallbacks = snapshot.videoCallbacks
        completeVideoFrames = snapshot.completeVideoFrames
        incompleteVideoFrames = snapshot.incompleteVideoFrames
        invalidSamples = snapshot.invalidSamples
        audioCallbacks = snapshot.audioCallbacks
        duplicatePTS = snapshot.duplicatePTS
        gapPTS = snapshot.gapPTS
        maxPTSGapSeconds = snapshot.maxPTSGapSeconds
        compositeCalls = snapshot.compositeCalls
        averageCompositeSeconds = snapshot.compositeCalls > 0
            ? snapshot.compositeSeconds / Double(snapshot.compositeCalls)
            : 0
        maxCompositeSeconds = snapshot.maxCompositeSeconds
        effectDegradations = snapshot.effectDegradations
    }
}

struct WriterResult: Codable {
    let videoFramesReceived: Int
    let videoFramesAppended: Int
    let videoFramesDropped: Int
    let audioSamplesReceived: Int
    let averageQueueWaitSeconds: Double
    let maxQueueWaitSeconds: Double

    init(_ statistics: AssetWriterSink.Statistics) {
        videoFramesReceived = statistics.videoFramesReceived
        videoFramesAppended = statistics.videoFramesAppended
        videoFramesDropped = statistics.videoFramesDropped
        audioSamplesReceived = statistics.audioSamplesReceived
        averageQueueWaitSeconds = statistics.writerQueueSamples > 0
            ? statistics.writerQueueWaitSeconds / Double(statistics.writerQueueSamples)
            : 0
        maxQueueWaitSeconds = statistics.maxWriterQueueWaitSeconds
    }
}

struct OutputResult: Codable {
    let durationSeconds: Double
    let width: Int
    let height: Int
    let videoFrames: Int
    let duplicatePTS: Int
    let gapPTS: Int
    let maxPTSGapSeconds: Double
    let audioDurationSeconds: Double?
    let audioVideoDriftSeconds: Double?
    let fileSizeBytes: Int
}
