import Foundation
import CoreGraphics

// MARK: - Recording mode

/// The four capture modes exposed by the toolbar (webcam intentionally excluded).
public enum RecordingMode: String, CaseIterable, Codable, Sendable {
    case selectedArea
    case fullScreen
    case window
}

// MARK: - Video

public enum VideoCodec: String, CaseIterable, Codable, Sendable {
    case h264
    case hevc
}

public enum ContainerFormat: String, CaseIterable, Codable, Sendable {
    case mp4
    case mov

    public var fileExtension: String { rawValue }
}

/// Frame-rate cap. Sources faster than this are downsampled; never upsampled.
public enum FrameRate: Int, CaseIterable, Codable, Sendable {
    case fps30 = 30
    case fps60 = 60
}

// MARK: - Audio

public enum AudioBitrate: Int, CaseIterable, Codable, Sendable {
    case kbps128 = 128
    case kbps192 = 192
    case kbps256 = 256
    case kbps320 = 320
}

// MARK: - Mouse effects

public enum PointerStyle: String, CaseIterable, Codable, Sendable {
    case system
    case dot
}

// MARK: - Appearance

public enum Theme: String, CaseIterable, Codable, Sendable {
    case auto
    case light
    case dark
}

// MARK: - Countdown

public enum CountdownDuration: Int, CaseIterable, Codable, Sendable {
    case off = 0
    case three = 3
    case five = 5
    case ten = 10
}

// MARK: - Limits (spec: output-settings, performance)

public enum CaptureLimits {
    /// Resolution cap — sources above 5K are downscaled preserving aspect ratio.
    public static let maxPixelsWide = 5120
    public static let maxPixelsHigh = 2880
    /// Hard FPS ceiling.
    public static let maxFrameRate = 60
    /// Disk-full guard: refuse to start below this threshold.
    public static let minFreeBytesToStart: Int64 = 1_000_000_000 // 1 GB
    /// Auto-stop when free space drops below this while recording.
    public static let autoStopFreeBytes: Int64 = 500_000_000 // 500 MB

    /// Clamp an arbitrary source size to the 5K envelope, preserving aspect ratio and rounding to even pixel dimensions (encoder requirement).
    public static func clamped(width: Int, height: Int) -> (width: Int, height: Int) {
        let scale = min(1.0, Double(maxPixelsWide) / Double(width), Double(maxPixelsHigh) / Double(height))
        let w = Int(Double(width) * scale) & ~1
        let h = Int(Double(height) * scale) & ~1
        return (max(w, 2), max(h, 2))
    }
}
