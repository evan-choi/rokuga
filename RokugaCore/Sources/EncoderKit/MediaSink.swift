import CoreMedia
import Foundation

public enum MediaKind: Sendable {
    case video
    case systemAudio
    case microphone
}

/// Destination for captured media buffers (AVAssetWriter in production, fakes in tests).
public protocol MediaSink: Sendable {
    func start() async throws
    func append(_ sampleBuffer: CMSampleBuffer, of kind: MediaKind)
    func markPaused()
    func markResumed()
    func finish() async throws -> URL
    func cancel() async
}
