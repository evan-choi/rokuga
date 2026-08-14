import AVFoundation
import Foundation

/// Sync-sample (keyframe) timestamps for snap display in the trim editor (task 8.1).
/// Passthrough export cuts land on these boundaries, so the UI surfaces them.
public struct KeyframeIndex: Sendable {
    public let seconds: [Double]

    public init(seconds: [Double]) {
        self.seconds = seconds
    }

    public static func load(from url: URL) async throws -> KeyframeIndex {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first,
              try await track.load(.canProvideSampleCursors),
              let cursor = track.makeSampleCursorAtFirstSampleInDecodeOrder()
        else {
            return KeyframeIndex(seconds: [])
        }

        var times: [Double] = [cursor.presentationTimeStamp.seconds]
        while cursor.stepInDecodeOrder(byCount: 1) == 1 {
            if cursor.currentSampleSyncInfo.sampleIsFullSync.boolValue {
                times.append(cursor.presentationTimeStamp.seconds)
            }
        }
        return KeyframeIndex(seconds: times.sorted())
    }

    public func nearest(to time: Double) -> Double? {
        guard !seconds.isEmpty else { return nil }
        return seconds.min { abs($0 - time) < abs($1 - time) }
    }
}
