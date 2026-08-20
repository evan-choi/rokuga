import AVFoundation
import CoreVideo
import EncoderKit
import Foundation
import SettingsKit
import TrimKit

// Performance benchmark harness (tasks 10.2/10.3/10.4).
//
// `rokuga-bench throughput [--width W] [--height H] [--fps N] [--seconds S] [--codec hevc|h264]`
//   Paces synthesized BGRA frames through the real encode sink at wall-clock rate and
//   reports drop rate, PTS drift, CPU usage, and peak memory as JSON.
// `rokuga-bench latency`
//   Measures record→first-frame, stop→playable, and passthrough-trim durations.

struct BenchArgs {
    var width = 3840
    var height = 2160
    var fps = 60
    var seconds = 10.0
    var codec = VideoCodec.hevc

    init(_ arguments: [String]) {
        var iterator = arguments.makeIterator()
        while let flag = iterator.next() {
            switch flag {
            case "--width": width = Int(iterator.next() ?? "") ?? width
            case "--height": height = Int(iterator.next() ?? "") ?? height
            case "--fps": fps = Int(iterator.next() ?? "") ?? fps
            case "--seconds": seconds = Double(iterator.next() ?? "") ?? seconds
            case "--codec": codec = VideoCodec(rawValue: iterator.next() ?? "") ?? codec
            default: break
            }
        }
    }
}

func makeConfiguration(_ args: BenchArgs) -> EncoderConfiguration {
    EncoderConfiguration(
        codec: args.codec,
        container: .mp4,
        width: args.width,
        height: args.height,
        frameRate: args.fps,
        frameRateMode: .variable,
        quality: 60,
        audioBitrate: .kbps192,
        capturesSystemAudio: false,
        capturesMicrophone: false
    )
}

final class FramePump {
    private let pool: CVPixelBufferPool
    private let formatCache = NSMutableDictionary()
    let width: Int
    let height: Int

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(nil, nil, [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ] as CFDictionary, &pool)
        self.pool = pool!
    }

    func frame(index: Int, fps: Int) -> CMSampleBuffer? {
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        guard let pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
            memset(base, Int32(index % 251), min(CVPixelBufferGetDataSize(pixelBuffer), 1 << 20))
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        var formatDescription: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: nil, imageBuffer: pixelBuffer, formatDescriptionOut: &formatDescription
        )
        guard let formatDescription else { return nil }
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(fps)),
            presentationTimeStamp: CMTime(value: CMTimeValue(index), timescale: CMTimeScale(fps)),
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateForImageBuffer(
            allocator: nil, imageBuffer: pixelBuffer, dataReady: true,
            makeDataReadyCallback: nil, refcon: nil,
            formatDescription: formatDescription, sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        return sampleBuffer
    }
}

func cpuSecondsUsed() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1e6
    let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1e6
    return user + system
}

func peakMemoryBytes() -> Int64 {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return Int64(usage.ru_maxrss)
}

func runThroughput(_ args: BenchArgs) async throws -> [String: Any] {
    let output = FileManager.default.temporaryDirectory
        .appendingPathComponent("bench-\(UUID().uuidString).mp4")
    defer { try? FileManager.default.removeItem(at: output) }

    let sink = AssetWriterSink(outputURL: output, configuration: makeConfiguration(args))
    try await sink.start()

    let pump = FramePump(width: args.width, height: args.height)
    let totalFrames = Int(args.seconds * Double(args.fps))
    let interval = 1.0 / Double(args.fps)

    let wallStart = CFAbsoluteTimeGetCurrent()
    let cpuStart = cpuSecondsUsed()
    var generated = 0

    for index in 0 ..< totalFrames {
        let deadline = wallStart + Double(index) * interval
        let now = CFAbsoluteTimeGetCurrent()
        if deadline > now {
            try await Task.sleep(nanoseconds: UInt64((deadline - now) * 1e9))
        }
        if let frame = pump.frame(index: index, fps: args.fps) {
            generated += 1
            sink.append(frame, of: .video)
        }
    }

    let stopStart = CFAbsoluteTimeGetCurrent()
    _ = try await sink.finish()
    let stopSeconds = CFAbsoluteTimeGetCurrent() - stopStart

    let wallSeconds = CFAbsoluteTimeGetCurrent() - wallStart
    let cpuSeconds = cpuSecondsUsed() - cpuStart
    let statistics = sink.statisticsSnapshot()

    let asset = AVURLAsset(url: output)
    let duration = try await asset.load(.duration).seconds
    let expectedDuration = Double(totalFrames) / Double(args.fps)

    let dropRate = generated > 0
        ? Double(generated - statistics.videoFramesAppended) / Double(generated)
        : 1
    return [
        "benchmark": "throughput",
        "width": args.width,
        "height": args.height,
        "fps": args.fps,
        "seconds": args.seconds,
        "codec": args.codec.rawValue,
        "framesGenerated": generated,
        "framesAppended": statistics.videoFramesAppended,
        "dropRate": dropRate,
        "ptsDriftSeconds": abs(duration - expectedDuration),
        "cpuPercentOfOneCore": cpuSeconds / wallSeconds * 100,
        "peakMemoryMB": Double(peakMemoryBytes()) / 1_048_576,
        "stopToPlayableSeconds": stopSeconds
    ]
}

func runLatency() async throws -> [String: Any] {
    let args = BenchArgs(["--width", "1920", "--height", "1080", "--fps", "60"])
    let output = FileManager.default.temporaryDirectory
        .appendingPathComponent("bench-lat-\(UUID().uuidString).mp4")
    defer { try? FileManager.default.removeItem(at: output) }

    let sink = AssetWriterSink(outputURL: output, configuration: makeConfiguration(args))
    let pump = FramePump(width: args.width, height: args.height)

    let startBegin = CFAbsoluteTimeGetCurrent()
    try await sink.start()
    let firstFrame = pump.frame(index: 0, fps: args.fps)!
    sink.append(firstFrame, of: .video)
    let recordToFirstFrame = CFAbsoluteTimeGetCurrent() - startBegin

    for index in 1 ..< 180 {
        if let frame = pump.frame(index: index, fps: args.fps) {
            sink.append(frame, of: .video)
        }
    }
    let stopBegin = CFAbsoluteTimeGetCurrent()
    let url = try await sink.finish()
    let stopToPlayable = CFAbsoluteTimeGetCurrent() - stopBegin

    let trimBegin = CFAbsoluteTimeGetCurrent()
    let trimOut = FileManager.default.temporaryDirectory
        .appendingPathComponent("bench-trim-\(UUID().uuidString).mp4")
    defer { try? FileManager.default.removeItem(at: trimOut) }
    try await TrimExporter(sourceURL: url).export(
        kind: .passthrough,
        range: TrimRange(
            start: CMTime(seconds: 0.5, preferredTimescale: 600),
            end: CMTime(seconds: 2.5, preferredTimescale: 600)
        ),
        to: trimOut
    )
    let trimSeconds = CFAbsoluteTimeGetCurrent() - trimBegin

    return [
        "benchmark": "latency",
        "recordToFirstFrameSeconds": recordToFirstFrame,
        "stopToPlayableSeconds": stopToPlayable,
        "passthroughTrimSeconds": trimSeconds
    ]
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
    FileHandle.standardError.write(Data("usage: rokuga-bench <throughput|latency> [flags]\n".utf8))
    exit(2)
}

let result: [String: Any]
switch command {
case "throughput":
    result = try await runThroughput(BenchArgs(Array(arguments.dropFirst())))
case "latency":
    result = try await runLatency()
default:
    FileHandle.standardError.write(Data("unknown benchmark: \(command)\n".utf8))
    exit(2)
}

let json = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
print(String(data: json, encoding: .utf8)!)
