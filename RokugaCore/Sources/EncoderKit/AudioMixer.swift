import AVFoundation
import Foundation

/// Sums the microphone into the system-audio stream, producing the single AAC-bound track required by the audio-capture spec (task 3.3).
///
/// The continuous SCStream system-audio clock drives output timing.
/// Mic buffers queue in a bounded FIFO and are consumed sample-for-sample as system buffers arrive, which absorbs the two sources' independent buffer cadences without timestamp gymnastics.
public final class AudioMixer: @unchecked Sendable {
    public static let canonicalFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 48_000,
        channels: 2,
        interleaved: false
    )!

    /// Bound the FIFO to 2 seconds so a stalled system stream cannot grow memory unbounded.
    private static let maxQueuedFrames = 96_000

    private let lock = NSLock()
    private var micFIFO: [[Float]] = [[], []]
    private var converters: [String: AVAudioConverter] = [:]

    public init() {}

    public func enqueueMicrophone(_ buffer: AVAudioPCMBuffer) {
        guard let canonical = convertToCanonical(buffer) else { return }
        let frames = Int(canonical.frameLength)
        guard frames > 0, let channelData = canonical.floatChannelData else { return }

        lock.withLock {
            for channel in 0..<2 {
                let source = channelData[min(channel, Int(canonical.format.channelCount) - 1)]
                micFIFO[channel].append(contentsOf: UnsafeBufferPointer(start: source, count: frames))
                if micFIFO[channel].count > Self.maxQueuedFrames {
                    micFIFO[channel].removeFirst(micFIFO[channel].count - Self.maxQueuedFrames)
                }
            }
        }
    }

    /// Returns the system buffer with queued mic samples summed in (canonical format).
    public func mix(system buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let canonical = convertToCanonical(buffer), let channelData = canonical.floatChannelData else {
            return nil
        }
        let frames = Int(canonical.frameLength)

        lock.withLock {
            for channel in 0..<2 {
                let available = min(frames, micFIFO[channel].count)
                guard available > 0 else { continue }
                let mic = micFIFO[channel].prefix(available)
                let out = channelData[channel]
                for (index, sample) in mic.enumerated() {
                    out[index] = max(-1.0, min(1.0, out[index] + sample))
                }
                micFIFO[channel].removeFirst(available)
            }
        }
        return canonical
    }

    private func convertToCanonical(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let format = buffer.format
        if format == Self.canonicalFormat { return buffer }

        let key = "\(format.sampleRate)-\(format.channelCount)-\(format.commonFormat.rawValue)-\(format.isInterleaved)"
        let converter: AVAudioConverter
        if let cached = lock.withLock({ converters[key] }) {
            converter = cached
        } else {
            guard let created = AVAudioConverter(from: format, to: Self.canonicalFormat) else { return nil }
            lock.withLock { converters[key] = created }
            converter = created
        }

        let ratio = Self.canonicalFormat.sampleRate / format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: Self.canonicalFormat, frameCapacity: capacity) else {
            return nil
        }

        var consumed = false
        var conversionError: NSError?
        converter.convert(to: output, error: &conversionError) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        return conversionError == nil ? output : nil
    }
}
