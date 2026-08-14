import Foundation
import SettingsKit

/// Quality-slider → encoder rate mapping (task 3.4, output-settings spec).
public enum RateControl {
    /// Bits-per-pixel-per-frame curve: 0.02 at quality 0 → ~0.24 at quality 100, exponential so the slider feels linear perceptually.
    static func bitsPerPixelPerFrame(quality: Int) -> Double {
        let q = Double(min(max(quality, 0), 100)) / 100.0
        return 0.02 * pow(12.0, q)
    }

    public static func averageVideoBitrate(
        width: Int,
        height: Int,
        fps: Int,
        quality: Int,
        codec: VideoCodec
    ) -> Int {
        let pixelRate = Double(width * height * fps)
        // HEVC reaches equivalent quality at ~65% of the H.264 rate.
        let codecFactor = codec == .hevc ? 0.65 : 1.0
        return Int(pixelRate * bitsPerPixelPerFrame(quality: quality) * codecFactor)
    }

    /// Capped-VBR "CBR" limits: 1.1× the average rate over a 1-second window (`AVVideoDataRateLimitsKey` expects [bytes, seconds]).
    public static func dataRateLimits(averageBitrate: Int) -> [NSNumber] {
        [NSNumber(value: Int(Double(averageBitrate) * 1.1 / 8.0)), NSNumber(value: 1.0)]
    }
}
