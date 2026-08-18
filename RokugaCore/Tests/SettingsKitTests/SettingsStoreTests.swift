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
        XCTAssertEqual(store.recordingMode, .selectedArea)
        XCTAssertEqual(store.videoCodec, .hevc)
        XCTAssertEqual(store.containerFormat, .mov)
        XCTAssertEqual(store.frameRate, .fps60)
        XCTAssertEqual(store.frameRateMode, .variable)
        XCTAssertEqual(store.videoQuality, 80)
        XCTAssertTrue(store.captureSystemAudio)
        XCTAssertFalse(store.captureMicrophone)
        XCTAssertEqual(store.countdown, .three)
        XCTAssertEqual(store.theme, .dark)
    }

    func testRoundTrip() {
        store.recordingMode = .window
        store.videoCodec = .h264
        store.frameRate = .fps30
        store.frameRateMode = .constant
        store.videoQuality = 55

        let reread = SettingsStore(defaults: defaults)
        XCTAssertEqual(reread.recordingMode, .window)
        XCTAssertEqual(reread.videoCodec, .h264)
        XCTAssertEqual(reread.frameRate, .fps30)
        XCTAssertEqual(reread.frameRateMode, .constant)
        XCTAssertEqual(reread.videoQuality, 55)
    }

    func testQualityClamped() {
        store.videoQuality = 400
        XCTAssertEqual(store.videoQuality, 100)
        store.videoQuality = -5
        XCTAssertEqual(store.videoQuality, 0)
    }

    func testThemeRoundTrip() {
        for theme in [Theme.auto, .light, .dark] {
            store.theme = theme
            XCTAssertEqual(SettingsStore(defaults: defaults).theme, theme)
        }
    }

    func testResetAllRestoresDefaults() {
        store.videoCodec = .h264
        store.frameRateMode = .constant
        store.captureMicrophone = true
        store.theme = .light
        store.resetAll()
        XCTAssertEqual(store.videoCodec, .hevc)
        XCTAssertEqual(store.frameRateMode, .variable)
        XCTAssertFalse(store.captureMicrophone)
        XCTAssertEqual(store.theme, .dark)
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
    }
}
