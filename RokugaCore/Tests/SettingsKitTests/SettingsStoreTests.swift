import XCTest
@testable import SettingsKit

final class SettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: SettingsStore!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "io.rokuga.tests")
        defaults.removePersistentDomain(forName: "io.rokuga.tests")
        store = SettingsStore(defaults: defaults)
    }

    func testDefaults() {
        XCTAssertEqual(store.appLanguage, .system)
        XCTAssertEqual(store.recordingMode, .selectedArea)
        XCTAssertEqual(store.videoCodec, .hevc)
        XCTAssertEqual(store.containerFormat, .mov)
        XCTAssertEqual(store.frameRate, .fps60)
        XCTAssertEqual(store.frameRateMode, .variable)
        XCTAssertEqual(store.videoQuality, 80)
        XCTAssertTrue(store.captureSystemAudio)
        XCTAssertFalse(store.captureMicrophone)
        XCTAssertEqual(store.audioTrackLayout, .mixed)
        XCTAssertEqual(store.countdown, .three)
    }

    func testRoundTrip() {
        store.appLanguage = .japanese
        store.recordingMode = .window
        store.videoCodec = .h264
        store.frameRate = .matchDisplay
        store.frameRateMode = .constant
        store.videoQuality = 55
        store.audioTrackLayout = .separate

        let reread = SettingsStore(defaults: defaults)
        XCTAssertEqual(reread.appLanguage, .japanese)
        XCTAssertEqual(defaults.array(forKey: "AppleLanguages") as? [String], ["ja"])
        XCTAssertEqual(reread.recordingMode, .window)
        XCTAssertEqual(reread.videoCodec, .h264)
        XCTAssertEqual(reread.frameRate, .matchDisplay)
        XCTAssertEqual(reread.frameRateMode, .constant)
        XCTAssertEqual(reread.videoQuality, 55)
        XCTAssertEqual(reread.audioTrackLayout, .separate)
    }

    func testMatchDisplayFrameRateResolution() {
        XCTAssertEqual(FrameRate.matchDisplay.resolved(displayRefreshRate: 179.8), 180)
        XCTAssertEqual(FrameRate.matchDisplay.resolved(displayRefreshRate: nil), 60)
        XCTAssertEqual(FrameRate.fps30.resolved(displayRefreshRate: 180), 30)
    }

    func testQualityClamped() {
        store.videoQuality = 400
        XCTAssertEqual(store.videoQuality, 100)
        store.videoQuality = -5
        XCTAssertEqual(store.videoQuality, 0)
    }

    func testResetAllRestoresDefaults() {
        store.appLanguage = .korean
        store.videoCodec = .h264
        store.frameRateMode = .constant
        store.captureMicrophone = true
        store.audioTrackLayout = .separate
        store.resetAll()
        XCTAssertEqual(store.appLanguage, .system)
        XCTAssertNil(defaults.persistentDomain(forName: "io.rokuga.tests")?["AppleLanguages"])
        XCTAssertEqual(store.videoCodec, .hevc)
        XCTAssertEqual(store.frameRateMode, .variable)
        XCTAssertFalse(store.captureMicrophone)
        XCTAssertEqual(store.audioTrackLayout, .mixed)
    }

    func testSystemLanguageRemovesOverride() {
        store.appLanguage = .simplifiedChinese
        store.appLanguage = .system

        XCTAssertNil(defaults.persistentDomain(forName: "io.rokuga.tests")?["AppleLanguages"])
    }

    func testUnknownAudioTrackLayoutFallsBackToMixed() {
        defaults.set("future-layout", forKey: SettingsStore.Key.audioTrackLayout.rawValue)
        XCTAssertEqual(store.audioTrackLayout, .mixed)
    }

    func testContainerChangePreservesAudioTrackLayout() {
        store.audioTrackLayout = .separate
        store.containerFormat = .mp4
        XCTAssertEqual(store.audioTrackLayout, .separate)
    }

    func testCaptureLimitsClamp5K() {
        // 8K source → clamped inside 5120×2880, aspect preserved, even dims.
        let clamped = CaptureLimits.clamped(width: 7680, height: 4320)
        XCTAssertLessThanOrEqual(clamped.width, 5120)
        XCTAssertLessThanOrEqual(clamped.height, 2880)
        XCTAssertEqual(clamped.width % 2, 0)
        XCTAssertEqual(clamped.height % 2, 0)
        let aspect = Double(clamped.width) / Double(clamped.height)
        XCTAssertEqual(aspect, 16.0 / 9.0, accuracy: 0.01)

        // Small sources are untouched.
        let small = CaptureLimits.clamped(width: 1280, height: 720)
        XCTAssertEqual(small.width, 1280)
        XCTAssertEqual(small.height, 720)

        // Native odd dimensions stay untouched so ScreenCaptureKit does not
        // fractionally rescale the entire captured image by one pixel.
        let odd = CaptureLimits.clamped(width: 1201, height: 863)
        XCTAssertEqual(odd.width, 1201)
        XCTAssertEqual(odd.height, 863)
    }
}
