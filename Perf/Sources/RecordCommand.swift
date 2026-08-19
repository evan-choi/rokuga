import AVFoundation
import CaptureKit
import CoreGraphics
import CoreMedia
import EffectsKit
import EncoderKit
import Foundation
import os.signpost
import ScreenCaptureKit
import SettingsKit

enum RecordCommand {
    private static let signpostLog = OSLog(subsystem: "io.rokuga.Rokuga.Perf", category: "Recording")

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
        let resourceSampler = ResourceSampler()
        let resourceTask = Task { await resourceSampler.run() }
        defer { resourceTask.cancel() }

        os_signpost(.begin, log: signpostLog, name: "Capture Start")
        do {
            try await coordinator.start(mode: target.recordingMode, countdown: .off)
            try await waitForFirstFrame(in: captureMetrics)
        } catch {
            os_signpost(.end, log: signpostLog, name: "Capture Start")
            await coordinator.cancel()
            throw error
        }
        os_signpost(.end, log: signpostLog, name: "Capture Start")

        os_signpost(.begin, log: signpostLog, name: "Recording")
        do {
            try await Task.sleep(nanoseconds: UInt64(options.seconds * 1_000_000_000))
        } catch {
            os_signpost(.end, log: signpostLog, name: "Recording")
            await coordinator.cancel()
            throw error
        }
        os_signpost(.end, log: signpostLog, name: "Recording")

        let finishStart = CFAbsoluteTimeGetCurrent()
        os_signpost(.begin, log: signpostLog, name: "Finalize")
        let finalizedURL: URL
        do {
            finalizedURL = try await coordinator.stop()
        } catch {
            os_signpost(.end, log: signpostLog, name: "Finalize")
            throw error
        }
        os_signpost(.end, log: signpostLog, name: "Finalize")
        let finishSeconds = CFAbsoluteTimeGetCurrent() - finishStart
        let wallSeconds = Double(DispatchTime.now().uptimeNanoseconds - requestStart) / 1_000_000_000
        let cpuSeconds = cpuSecondsUsed() - cpuStart
        resourceTask.cancel()
        await resourceTask.value
        let resources = await resourceSampler.result()

        let capture = captureMetrics.currentSnapshot()
        let writer = sink.statisticsSnapshot()
        os_signpost(.begin, log: signpostLog, name: "Inspect Output")
        let output: OutputResult
        do {
            output = try await inspectOutput(finalizedURL, expectedFPS: options.fps)
        } catch {
            os_signpost(.end, log: signpostLog, name: "Inspect Output")
            throw error
        }
        os_signpost(.end, log: signpostLog, name: "Inspect Output")
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
            peakMemoryMB: max(Double(peakMemoryBytes()) / 1_048_576, resources.peakMemoryMB),
            steadyMemoryMB: resources.steadyMemoryMB,
            memoryGrowthMBPerSecond: resources.memoryGrowthMBPerSecond,
            thermalStateStart: resources.thermalStateStart,
            thermalStateEnd: resources.thermalStateEnd,
            thermalStateWorst: resources.thermalStateWorst,
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
        let videoTimeRange = try await videoTrack.load(.timeRange)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
        reader.add(output)
        reader.startReading()

        var frames = 0
        var duplicatePTS = 0
        var gapPTS = 0
        var missingVideoFrames = 0
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
                    missingVideoFrames += max(Int((delta / expectedFrameSeconds).rounded()) - 1, 1)
                    maxPTSGapSeconds = max(maxPTSGapSeconds, delta)
                }
            }
            lastPTS = pts
            frames += 1
        }
        if reader.status == .failed {
            throw reader.error ?? PerfError.captureTargetNotFound
        }

        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
        let audioTimeRange = try await audioTrack?.load(.timeRange)
        let audioVideoSync = try audioTrack.flatMap {
            try inspectAudioVideoSync(
                asset: asset,
                videoTrack: videoTrack,
                audioTrack: $0,
                durationSeconds: duration
            )
        }
        let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        return OutputResult(
            durationSeconds: duration,
            width: Int(abs(size.width)),
            height: Int(abs(size.height)),
            videoFrames: frames,
            duplicatePTS: duplicatePTS,
            gapPTS: gapPTS,
            missingVideoFrames: missingVideoFrames,
            maxPTSGapSeconds: maxPTSGapSeconds,
            audioDurationSeconds: audioTimeRange?.duration.seconds,
            audioVideoEndpointSkewSeconds: audioTimeRange.map {
                abs(CMTimeSubtract(CMTimeRangeGetEnd($0), CMTimeRangeGetEnd(videoTimeRange)).seconds)
            },
            audioVideoSyncMarkers: audioVideoSync?.markerCount,
            audioVideoObservedSeconds: audioVideoSync?.observedSeconds,
            audioVideoStartOffsetSeconds: audioVideoSync?.startOffsetSeconds,
            audioVideoEndOffsetSeconds: audioVideoSync?.endOffsetSeconds,
            audioVideoDriftSeconds: audioVideoSync?.driftSeconds,
            audioVideoDriftSecondsPerHour: audioVideoSync?.driftSecondsPerHour,
            fileSizeBytes: fileSize
        )
    }

    private static func inspectAudioVideoSync(
        asset: AVAsset,
        videoTrack: AVAssetTrack,
        audioTrack: AVAssetTrack,
        durationSeconds: Double
    ) throws -> AudioVideoSyncResult? {
        let ranges = syncInspectionRanges(durationSeconds: durationSeconds)
        let videoMarkers = try videoSyncMarkers(asset: asset, track: videoTrack, ranges: ranges)
        let audioMarkers = try audioSyncMarkers(asset: asset, track: audioTrack, ranges: ranges)
        var matches: [(video: Double, audio: Double)] = []
        var audioIndex = 0

        for video in videoMarkers {
            while audioIndex + 1 < audioMarkers.count,
                  abs(audioMarkers[audioIndex + 1] - video) < abs(audioMarkers[audioIndex] - video) {
                audioIndex += 1
            }
            guard audioIndex < audioMarkers.count else { break }
            if abs(audioMarkers[audioIndex] - video) < AVSyncMarker.periodSeconds * 0.45 {
                matches.append((video, audioMarkers[audioIndex]))
                audioIndex += 1
            }
        }

        guard matches.count >= 2,
              let first = matches.first,
              let last = matches.last,
              last.video > first.video
        else { return nil }

        let meanVideo = matches.reduce(0) { $0 + $1.video } / Double(matches.count)
        let meanOffset = matches.reduce(0) { $0 + $1.audio - $1.video } / Double(matches.count)
        let denominator = matches.reduce(0) { $0 + pow($1.video - meanVideo, 2) }
        guard denominator > 0 else { return nil }
        let slope = matches.reduce(0) {
            $0 + ($1.video - meanVideo) * (($1.audio - $1.video) - meanOffset)
        } / denominator
        let observedSeconds = last.video - first.video
        let startOffsetSeconds = meanOffset + slope * (first.video - meanVideo)
        let endOffsetSeconds = meanOffset + slope * (last.video - meanVideo)
        return AudioVideoSyncResult(
            markerCount: matches.count,
            observedSeconds: observedSeconds,
            startOffsetSeconds: startOffsetSeconds,
            endOffsetSeconds: endOffsetSeconds,
            driftSeconds: abs(endOffsetSeconds - startOffsetSeconds),
            driftSecondsPerHour: durationSeconds >= 600 ? abs(slope) * 3600 : nil
        )
    }

    private static func syncInspectionRanges(durationSeconds: Double) -> [CMTimeRange] {
        let timescale: CMTimeScale = 600
        let duration = CMTime(seconds: durationSeconds, preferredTimescale: timescale)
        guard durationSeconds > 120 else {
            return [CMTimeRange(start: .zero, duration: duration)]
        }
        let window = CMTime(seconds: 30, preferredTimescale: timescale)
        return [
            CMTimeRange(start: .zero, duration: window),
            CMTimeRange(start: CMTimeSubtract(duration, window), duration: window)
        ]
    }

    private static func videoSyncMarkers(
        asset: AVAsset,
        track: AVAssetTrack,
        ranges: [CMTimeRange]
    ) throws -> [Double] {
        var markers: [Double] = []
        for range in ranges {
            let reader = try AVAssetReader(asset: asset)
            reader.timeRange = range
            let output = AVAssetReaderTrackOutput(
                track: track,
                outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            )
            output.alwaysCopiesSampleData = false
            reader.add(output)
            guard reader.startReading() else {
                throw reader.error ?? PerfError.outputInspection("cannot decode video sync markers")
            }

            var markerWasOn = false
            while let sample = output.copyNextSampleBuffer() {
                guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
                CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
                let markerIsOn = centerPixelIsWhite(pixelBuffer)
                CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
                let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                if markerIsOn,
                   !markerWasOn,
                   time > range.start.seconds + AVSyncMarker.periodSeconds * 0.5 {
                    markers.append(time)
                }
                markerWasOn = markerIsOn
            }
            if reader.status == .failed {
                throw reader.error ?? PerfError.outputInspection("video sync marker decoding failed")
            }
        }
        return markers
    }

    private static func centerPixelIsWhite(_ pixelBuffer: CVPixelBuffer) -> Bool {
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return false }
        let x = CVPixelBufferGetWidth(pixelBuffer) / 2
        let y = CVPixelBufferGetHeight(pixelBuffer) / 2
        let pixel = baseAddress
            .advanced(by: y * CVPixelBufferGetBytesPerRow(pixelBuffer) + x * 4)
            .assumingMemoryBound(to: UInt8.self)
        return Int(pixel[0]) + Int(pixel[1]) + Int(pixel[2]) > 690
    }

    private static func audioSyncMarkers(
        asset: AVAsset,
        track: AVAssetTrack,
        ranges: [CMTimeRange]
    ) throws -> [Double] {
        var markers: [Double] = []
        for range in ranges {
            let reader = try AVAssetReader(asset: asset)
            reader.timeRange = range
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsNonInterleaved: false
            ])
            output.alwaysCopiesSampleData = false
            reader.add(output)
            guard reader.startReading() else {
                throw reader.error ?? PerfError.outputInspection("cannot decode audio sync markers")
            }

            while let sample = output.copyNextSampleBuffer() {
                guard let format = CMSampleBufferGetFormatDescription(sample),
                      let stream = CMAudioFormatDescriptionGetStreamBasicDescription(format),
                      let data = CMSampleBufferGetDataBuffer(sample)
                else { continue }
                let frameCount = CMSampleBufferGetNumSamples(sample)
                let channelCount = Int(stream.pointee.mChannelsPerFrame)
                let sampleRate = stream.pointee.mSampleRate
                guard frameCount > 0, channelCount > 0, sampleRate > 0 else { continue }

                var lengthAtOffset = 0
                var totalLength = 0
                var pointer: UnsafeMutablePointer<Int8>?
                let status = CMBlockBufferGetDataPointer(
                    data,
                    atOffset: 0,
                    lengthAtOffsetOut: &lengthAtOffset,
                    totalLengthOut: &totalLength,
                    dataPointerOut: &pointer
                )
                guard status == kCMBlockBufferNoErr,
                      lengthAtOffset == totalLength,
                      let pointer,
                      totalLength >= frameCount * channelCount * MemoryLayout<Float>.size
                else {
                    throw PerfError.outputInspection("audio sync marker buffer is not contiguous float PCM")
                }

                let samples = UnsafeRawPointer(pointer).assumingMemoryBound(to: Float.self)
                let start = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                for frame in 0 ..< frameCount {
                    var peak: Float = 0
                    for channel in 0 ..< channelCount {
                        peak = max(peak, abs(samples[frame * channelCount + channel]))
                    }
                    let time = start + Double(frame) / sampleRate
                    if peak > 0.1,
                       time > range.start.seconds + AVSyncMarker.periodSeconds * 0.5,
                       markers.last.map({ time - $0 > AVSyncMarker.periodSeconds * 0.5 }) ?? true {
                        markers.append(time)
                    }
                }
            }
            if reader.status == .failed {
                throw reader.error ?? PerfError.outputInspection("audio sync marker decoding failed")
            }
        }
        return markers
    }
}

private struct AudioVideoSyncResult {
    let markerCount: Int
    let observedSeconds: Double
    let startOffsetSeconds: Double
    let endOffsetSeconds: Double
    let driftSeconds: Double
    let driftSecondsPerHour: Double?
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
                guard let parsed = Int(value), (1 ... 240).contains(parsed) else {
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
    let steadyMemoryMB: Double
    let memoryGrowthMBPerSecond: Double
    let thermalStateStart: String
    let thermalStateEnd: String
    let thermalStateWorst: String
    let recordToFirstFrameSeconds: Double?
    let stopToPlayableSeconds: Double
    let capture: CaptureResult
    let writer: WriterResult
    let output: OutputResult
}

private actor ResourceSampler {
    private struct Sample {
        let uptimeNanoseconds: UInt64
        let residentMemoryMB: Double
        let thermalState: ProcessInfo.ThermalState
    }

    private var samples: [Sample] = []

    func run() async {
        repeat {
            samples.append(Sample(
                uptimeNanoseconds: DispatchTime.now().uptimeNanoseconds,
                residentMemoryMB: Double(residentMemoryBytes()) / 1_048_576,
                thermalState: ProcessInfo.processInfo.thermalState
            ))
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
            } catch {
                break
            }
        } while !Task.isCancelled
    }

    func result() -> ResourceResult {
        guard let first = samples.first, let last = samples.last else {
            let state = thermalStateName(ProcessInfo.processInfo.thermalState)
            return ResourceResult(
                peakMemoryMB: 0,
                steadyMemoryMB: 0,
                memoryGrowthMBPerSecond: 0,
                thermalStateStart: state,
                thermalStateEnd: state,
                thermalStateWorst: state
            )
        }

        let steady = Array(samples.dropFirst(samples.count / 2).map(\.residentMemoryMB)).sorted()
        let steadyMedian: Double = if steady.count.isMultiple(of: 2) {
            (steady[steady.count / 2 - 1] + steady[steady.count / 2]) / 2
        } else {
            steady[steady.count / 2]
        }

        let origin = Double(first.uptimeNanoseconds) / 1_000_000_000
        let points = samples.map {
            (x: Double($0.uptimeNanoseconds) / 1_000_000_000 - origin, y: $0.residentMemoryMB)
        }
        let meanX = points.map(\.x).reduce(0, +) / Double(points.count)
        let meanY = points.map(\.y).reduce(0, +) / Double(points.count)
        let denominator = points.reduce(0) { $0 + ($1.x - meanX) * ($1.x - meanX) }
        let slope = denominator > 0
            ? points.reduce(0) { $0 + ($1.x - meanX) * ($1.y - meanY) } / denominator
            : 0
        let worst = samples.map(\.thermalState).max(by: { thermalSeverity($0) < thermalSeverity($1) }) ?? last.thermalState

        return ResourceResult(
            peakMemoryMB: samples.map(\.residentMemoryMB).max() ?? 0,
            steadyMemoryMB: steadyMedian,
            memoryGrowthMBPerSecond: slope,
            thermalStateStart: thermalStateName(first.thermalState),
            thermalStateEnd: thermalStateName(last.thermalState),
            thermalStateWorst: thermalStateName(worst)
        )
    }
}

private struct ResourceResult {
    let peakMemoryMB: Double
    let steadyMemoryMB: Double
    let memoryGrowthMBPerSecond: Double
    let thermalStateStart: String
    let thermalStateEnd: String
    let thermalStateWorst: String
}

private func residentMemoryBytes() -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? info.resident_size : 0
}

private func thermalSeverity(_ state: ProcessInfo.ThermalState) -> Int {
    switch state {
    case .nominal: 0
    case .fair: 1
    case .serious: 2
    case .critical: 3
    @unknown default: 4
    }
}

private func thermalStateName(_ state: ProcessInfo.ThermalState) -> String {
    switch state {
    case .nominal: "nominal"
    case .fair: "fair"
    case .serious: "serious"
    case .critical: "critical"
    @unknown default: "unknown"
    }
}

struct CaptureResult: Codable {
    let videoCallbacks: Int
    let completeVideoFrames: Int
    let incompleteVideoFrames: Int
    let invalidSamples: Int
    let audioCallbacks: Int
    let duplicatePTS: Int
    let gapPTS: Int
    let missingVideoFrames: Int
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
        missingVideoFrames = snapshot.missingVideoFrames
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
    let missingVideoFrames: Int
    let maxPTSGapSeconds: Double
    let audioDurationSeconds: Double?
    let audioVideoEndpointSkewSeconds: Double?
    let audioVideoSyncMarkers: Int?
    let audioVideoObservedSeconds: Double?
    let audioVideoStartOffsetSeconds: Double?
    let audioVideoEndOffsetSeconds: Double?
    let audioVideoDriftSeconds: Double?
    let audioVideoDriftSecondsPerHour: Double?
    let fileSizeBytes: Int
}
