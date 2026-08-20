import Foundation

/// UserDefaults-backed preferences store. Thread-safe, immediate-apply.
///
/// UI layers observe via KVO/`@AppStorage` on the same suite.
/// Core modules read snapshot values at recording start (settings are locked while recording — see app-preferences spec).
public final class SettingsStore: @unchecked Sendable {
    public static let shared = SettingsStore()

    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: Keys

    public enum Key: String, CaseIterable {
        case recordingMode = "recording.mode"
        case videoCodec = "output.codec"
        case containerFormat = "output.container"
        case frameRate = "output.fps"
        case frameRateMode = "output.frameRateMode"
        case videoQuality = "output.quality" // 0...100 VBR quality
        case audioBitrate = "output.audioBitrate"
        case captureSystemAudio = "audio.system"
        case captureMicrophone = "audio.microphone"
        case audioTrackLayout = "audio.trackLayout"
        case showCursor = "mouse.showCursor"
        case animateClicks = "mouse.clicks"
        case countdown = "recording.countdown"
        case excludeDesktopIcons = "capture.excludeDesktopIcons"
        case showFloatingThumbnail = "post.showThumbnail"
        case outputFolderBookmark = "output.folderBookmark"
        case selectedRegions = "region.perDisplay"
        case appLanguage = "app.language"
        case launchAtLogin = "app.launchAtLogin"
        case onboardingCompleted = "app.onboardingCompleted"
        case lastRecordingPath = "post.lastRecordingPath"
    }

    public var lastRecordingPath: String? {
        get { lock.withLock { defaults.string(forKey: Key.lastRecordingPath.rawValue) } }
        set { lock.withLock { defaults.set(newValue, forKey: Key.lastRecordingPath.rawValue) } }
    }

    // MARK: Typed accessors

    public var appLanguage: AppLanguage {
        get { rawRepresentable(.appLanguage) ?? .system }
        set {
            lock.withLock {
                defaults.set(newValue.rawValue, forKey: Key.appLanguage.rawValue)
                if let languageCode = newValue.languageCode {
                    defaults.set([languageCode], forKey: "AppleLanguages")
                } else {
                    defaults.removeObject(forKey: "AppleLanguages")
                }
            }
        }
    }

    public var recordingMode: RecordingMode {
        get { rawRepresentable(.recordingMode) ?? .selectedArea }
        set { setRawRepresentable(newValue, for: .recordingMode) }
    }

    public var videoCodec: VideoCodec {
        get { rawRepresentable(.videoCodec) ?? .hevc }
        set { setRawRepresentable(newValue, for: .videoCodec) }
    }

    public var containerFormat: ContainerFormat {
        get { rawRepresentable(.containerFormat) ?? .mov }
        set { setRawRepresentable(newValue, for: .containerFormat) }
    }

    public var frameRate: FrameRate {
        get { rawRepresentable(.frameRate) ?? .fps60 }
        set { setRawRepresentable(newValue, for: .frameRate) }
    }

    public var frameRateMode: FrameRateMode {
        get { rawRepresentable(.frameRateMode) ?? .variable }
        set { setRawRepresentable(newValue, for: .frameRateMode) }
    }

    /// VBR quality 0...100 (see output-settings spec §rate-control).
    public var videoQuality: Int {
        get { clampedInt(.videoQuality, default: 80, range: 0 ... 100) }
        set { set(min(max(newValue, 0), 100), for: .videoQuality) }
    }

    public var audioBitrate: AudioBitrate {
        get { rawRepresentable(.audioBitrate) ?? .kbps192 }
        set { setRawRepresentable(newValue, for: .audioBitrate) }
    }

    public var captureSystemAudio: Bool {
        get { bool(.captureSystemAudio, default: true) }
        set { set(newValue, for: .captureSystemAudio) }
    }

    public var captureMicrophone: Bool {
        get { bool(.captureMicrophone, default: false) }
        set { set(newValue, for: .captureMicrophone) }
    }

    public var audioTrackLayout: AudioTrackLayout {
        get { rawRepresentable(.audioTrackLayout) ?? .mixed }
        set { setRawRepresentable(newValue, for: .audioTrackLayout) }
    }

    public var showCursor: Bool {
        get { bool(.showCursor, default: true) }
        set { set(newValue, for: .showCursor) }
    }

    public var animateClicks: Bool {
        get { bool(.animateClicks, default: true) }
        set { set(newValue, for: .animateClicks) }
    }

    public var countdown: CountdownDuration {
        get { rawRepresentable(.countdown) ?? .three }
        set { setRawRepresentable(newValue, for: .countdown) }
    }

    public var excludeDesktopIcons: Bool {
        get { bool(.excludeDesktopIcons, default: false) }
        set { set(newValue, for: .excludeDesktopIcons) }
    }

    public var showFloatingThumbnail: Bool {
        get { bool(.showFloatingThumbnail, default: true) }
        set { set(newValue, for: .showFloatingThumbnail) }
    }

    public var launchAtLogin: Bool {
        get { bool(.launchAtLogin, default: false) }
        set { set(newValue, for: .launchAtLogin) }
    }

    public var onboardingCompleted: Bool {
        get { bool(.onboardingCompleted, default: false) }
        set { set(newValue, for: .onboardingCompleted) }
    }

    /// Security-scoped bookmark for the user-chosen output folder.
    public var outputFolderBookmark: Data? {
        get { lock.withLock { defaults.data(forKey: Key.outputFolderBookmark.rawValue) } }
        set { lock.withLock { defaults.set(newValue, forKey: Key.outputFolderBookmark.rawValue) } }
    }

    /// Last-used selection rectangle per display (task 4.5), keyed by display ID.
    public var selectedRegions: [String: CGRect] {
        get {
            lock.withLock {
                guard let data = defaults.data(forKey: Key.selectedRegions.rawValue) else { return [:] }
                return (try? JSONDecoder().decode([String: CGRect].self, from: data)) ?? [:]
            }
        }
        set {
            lock.withLock {
                defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.selectedRegions.rawValue)
            }
        }
    }

    // MARK: Reset

    /// Reset all preferences to defaults. Never touches recordings on disk.
    public func resetAll() {
        lock.withLock {
            for key in Key.allCases {
                defaults.removeObject(forKey: key.rawValue)
            }
            defaults.removeObject(forKey: "AppleLanguages")
        }
    }

    // MARK: Private plumbing

    private func bool(_ key: Key, default defaultValue: Bool) -> Bool {
        lock.withLock {
            defaults.object(forKey: key.rawValue) as? Bool ?? defaultValue
        }
    }

    private func clampedInt(_ key: Key, default defaultValue: Int, range: ClosedRange<Int>) -> Int {
        lock.withLock {
            guard let value = defaults.object(forKey: key.rawValue) as? Int else { return defaultValue }
            return min(max(value, range.lowerBound), range.upperBound)
        }
    }

    private func rawRepresentable<T: RawRepresentable>(_ key: Key) -> T? where T.RawValue == String {
        lock.withLock {
            defaults.string(forKey: key.rawValue).flatMap(T.init(rawValue:))
        }
    }

    private func rawRepresentable<T: RawRepresentable>(_ key: Key) -> T? where T.RawValue == Int {
        lock.withLock {
            guard defaults.object(forKey: key.rawValue) != nil else { return nil }
            return T(rawValue: defaults.integer(forKey: key.rawValue))
        }
    }

    private func setRawRepresentable(_ value: some RawRepresentable, for key: Key) {
        lock.withLock {
            defaults.set(value.rawValue, forKey: key.rawValue)
        }
    }

    private func set(_ value: Any?, for key: Key) {
        lock.withLock {
            defaults.set(value, forKey: key.rawValue)
        }
    }
}
