import Foundation
import SettingsKit

/// Immutable encode-session configuration, snapshotted at recording start.
public struct EncoderConfiguration: Equatable, Sendable {
    public var codec: VideoCodec
    public var container: ContainerFormat
    public var width: Int
    public var height: Int
    public var frameRate: FrameRate
    public var frameRateMode: FrameRateMode
    /// VBR quality 0...100 → codec quality mapping (see output-settings spec).
    public var quality: Int
    public var audioBitrate: AudioBitrate
    public var capturesSystemAudio: Bool
    public var capturesMicrophone: Bool

    public init(
        codec: VideoCodec,
        container: ContainerFormat,
        width: Int,
        height: Int,
        frameRate: FrameRate,
        frameRateMode: FrameRateMode,
        quality: Int,
        audioBitrate: AudioBitrate,
        capturesSystemAudio: Bool,
        capturesMicrophone: Bool
    ) {
        self.codec = codec
        self.container = container
        let clamped = CaptureLimits.clamped(width: width, height: height)
        self.width = clamped.width
        self.height = clamped.height
        self.frameRate = frameRate
        self.frameRateMode = frameRateMode
        self.quality = min(max(quality, 0), 100)
        self.audioBitrate = audioBitrate
        self.capturesSystemAudio = capturesSystemAudio
        self.capturesMicrophone = capturesMicrophone
    }

    /// Snapshot the user's current preferences for a source of the given size.
    public static func fromSettings(_ settings: SettingsStore, sourceWidth: Int, sourceHeight: Int) -> Self {
        .init(
            codec: settings.videoCodec,
            container: settings.containerFormat,
            width: sourceWidth,
            height: sourceHeight,
            frameRate: settings.frameRate,
            frameRateMode: settings.frameRateMode,
            quality: settings.videoQuality,
            audioBitrate: settings.audioBitrate,
            capturesSystemAudio: settings.captureSystemAudio,
            capturesMicrophone: settings.captureMicrophone
        )
    }
}
