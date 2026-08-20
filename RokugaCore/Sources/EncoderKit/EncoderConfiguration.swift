import Foundation
import SettingsKit

/// Immutable encode-session configuration, snapshotted at recording start.
public struct EncoderConfiguration: Equatable, Sendable {
    public var codec: VideoCodec
    public var container: ContainerFormat
    public var width: Int
    public var height: Int
    public var frameRate: Int
    public var frameRateMode: FrameRateMode
    /// VBR quality 0...100 → codec quality mapping (see output-settings spec).
    public var quality: Int
    public var audioBitrate: AudioBitrate
    public var capturesSystemAudio: Bool
    public var capturesMicrophone: Bool
    public var audioTrackLayout: AudioTrackLayout

    public init(
        codec: VideoCodec,
        container: ContainerFormat,
        width: Int,
        height: Int,
        frameRate: Int,
        frameRateMode: FrameRateMode,
        quality: Int,
        audioBitrate: AudioBitrate,
        capturesSystemAudio: Bool,
        capturesMicrophone: Bool,
        audioTrackLayout: AudioTrackLayout = .mixed
    ) {
        self.codec = codec
        self.container = container
        let clamped = CaptureLimits.clamped(width: width, height: height)
        self.width = clamped.width
        self.height = clamped.height
        self.frameRate = max(frameRate, 1)
        self.frameRateMode = frameRateMode
        self.quality = min(max(quality, 0), 100)
        self.audioBitrate = audioBitrate
        self.capturesSystemAudio = capturesSystemAudio
        self.capturesMicrophone = capturesMicrophone
        self.audioTrackLayout = container == .mov ? audioTrackLayout : .mixed
    }

    /// Snapshot the user's current preferences for a source of the given size.
    public static func fromSettings(
        _ settings: SettingsStore,
        sourceWidth: Int,
        sourceHeight: Int,
        frameRate: Int? = nil
    ) -> Self {
        .init(
            codec: settings.videoCodec,
            container: settings.containerFormat,
            width: sourceWidth,
            height: sourceHeight,
            frameRate: frameRate ?? settings.frameRate.resolved(displayRefreshRate: nil),
            frameRateMode: settings.frameRateMode,
            quality: settings.videoQuality,
            audioBitrate: settings.audioBitrate,
            capturesSystemAudio: settings.captureSystemAudio,
            capturesMicrophone: settings.captureMicrophone,
            audioTrackLayout: settings.audioTrackLayout
        )
    }
}
