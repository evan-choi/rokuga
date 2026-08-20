import AVFoundation
import CoreGraphics
import Foundation

/// Lazy thumbnail tile provider for the timeline strip (task 8.5).
/// Tiles are cached per zoom band so re-zooming reuses previously generated images.
public actor ThumbnailStrip {
    public struct TileKey: Hashable, Sendable {
        public let band: Int
        public let index: Int

        public init(band: Int, index: Int) {
            self.band = band
            self.index = index
        }
    }

    private let generator: AVAssetImageGenerator
    private var cache: [TileKey: CGImage] = [:]
    private var inFlight: Set<TileKey> = []

    public init(url: URL, tileHeight: CGFloat = 48) {
        generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: tileHeight * 4, height: tileHeight * 2)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
    }

    /// Zoom bands quantize points-per-second to powers of two, bounding regeneration work while zooming.
    public static func band(forPointsPerSecond pps: Double) -> Int {
        Int(log2(max(pps, 1)).rounded())
    }

    public static func secondsPerTile(band: Int, tileWidth: Double = 80) -> Double {
        tileWidth / pow(2, Double(band))
    }

    public func tile(for key: TileKey) async -> CGImage? {
        if let cached = cache[key] {
            return cached
        }
        guard !inFlight.contains(key) else { return nil }
        inFlight.insert(key)
        defer { inFlight.remove(key) }

        let seconds = Double(key.index) * Self.secondsPerTile(band: key.band)
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        guard let image = try? generator.copyCGImage(at: time, actualTime: nil) else { return nil }
        cache[key] = image
        return image
    }
}
