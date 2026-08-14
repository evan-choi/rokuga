import AVFoundation
import Foundation

public enum TrimExportKind: Sendable {
    case passthrough
    case frameExact
    case audioOnlyM4A
}

public enum TrimExportError: Error, Equatable, Sendable {
    case exportSessionUnavailable
    case noAudioTrack
    case cancelled
    case failed(String)
}

/// Trim export engine (tasks 8.2/8.4): keyframe-aligned passthrough by default,
/// frame-exact re-encode fallback, and audio-only M4A extraction of the kept range.
public final class TrimExporter: @unchecked Sendable {
    private let asset: AVAsset
    private let lock = NSLock()
    private var session: AVAssetExportSession?

    public init(sourceURL: URL) {
        asset = AVURLAsset(url: sourceURL)
    }

    public func export(
        kind: TrimExportKind,
        range: TrimRange,
        to destination: URL,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        let preset: String
        let fileType: AVFileType
        switch kind {
        case .passthrough:
            preset = AVAssetExportPresetPassthrough
            fileType = destination.pathExtension.lowercased() == "mov" ? .mov : .mp4
        case .frameExact:
            preset = AVAssetExportPresetHighestQuality
            fileType = destination.pathExtension.lowercased() == "mov" ? .mov : .mp4
        case .audioOnlyM4A:
            guard try await hasAudioTrack() else { throw TrimExportError.noAudioTrack }
            preset = AVAssetExportPresetAppleM4A
            fileType = .m4a
        }

        let duration = try await asset.load(.duration)
        let clamped = range.clamped(toAssetDuration: duration)

        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw TrimExportError.exportSessionUnavailable
        }
        session.outputURL = destination
        session.outputFileType = fileType
        session.timeRange = clamped.timeRange
        lock.withLock { self.session = session }

        try? FileManager.default.removeItem(at: destination)

        let poller = progress.map { report in
            Task {
                while !Task.isCancelled {
                    report(Double(session.progress))
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
            }
        }
        defer { poller?.cancel() }

        await session.export()

        switch session.status {
        case .completed:
            progress?(1)
        case .cancelled:
            throw TrimExportError.cancelled
        default:
            throw TrimExportError.failed(session.error?.localizedDescription ?? "unknown")
        }
    }

    public func cancel() {
        lock.withLock { session?.cancelExport() }
    }

    public func hasAudioTrack() async throws -> Bool {
        try await !asset.loadTracks(withMediaType: .audio).isEmpty
    }
}
