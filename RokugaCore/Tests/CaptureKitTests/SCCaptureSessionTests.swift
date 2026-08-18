import CoreGraphics
import Foundation
import ScreenCaptureKit
import SettingsKit
import XCTest
@testable import CaptureKit

final class SCCaptureSessionTests: XCTestCase {
    func testSystemPointerRemainsNativeWhenEffectsAreEnabled() {
        withSettings { settings in
            settings.showCursor = true
            settings.pointerStyle = .system
            settings.highlightCursor = true
            settings.animateClicks = true

            let configuration = CaptureConfiguration.fromSettings(settings)

            XCTAssertTrue(configuration.showsCursor)
            XCTAssertTrue(configuration.cursorEffects.needsCompositor)
        }
    }

    func testDotPointerDisablesNativeCursorAndKeepsCompositor() {
        withSettings { settings in
            settings.showCursor = true
            settings.pointerStyle = .dot
            settings.highlightCursor = false
            settings.animateClicks = false

            let configuration = CaptureConfiguration.fromSettings(settings)

            XCTAssertFalse(configuration.showsCursor)
            XCTAssertTrue(configuration.cursorEffects.compositesPointer)
            XCTAssertTrue(configuration.cursorEffects.needsCompositor)
        }
    }

    func testHiddenPointerDisablesBothCursorOwners() {
        withSettings { settings in
            settings.showCursor = false
            settings.pointerStyle = .system
            settings.highlightCursor = false
            settings.animateClicks = false

            let configuration = CaptureConfiguration.fromSettings(settings)

            XCTAssertFalse(configuration.showsCursor)
            XCTAssertFalse(configuration.cursorEffects.needsCompositor)
        }
    }

    func testFrameMetadataTracksMovingWindowAndSurfacePlacement() throws {
        let frameInfo: [SCStreamFrameInfo: Any] = [
            .screenRect: CGRect(x: 120, y: 80, width: 640, height: 480),
            .contentRect: CGRect(x: 10, y: 20, width: 320, height: 240),
            .scaleFactor: CGFloat(2)
        ]

        let geometry = try XCTUnwrap(SCCaptureSession.frameGeometry(
            frameInfo: frameInfo,
            pixelSize: CGSize(width: 800, height: 600)
        ))

        XCTAssertEqual(geometry.contentRect, CGRect(x: 120, y: 80, width: 640, height: 480))
        XCTAssertEqual(geometry.pixelContentRect, CGRect(x: 20, y: 40, width: 640, height: 480))
        XCTAssertEqual(
            geometry.pixelPosition(of: CGPoint(x: 440, y: 320)),
            CGPoint(x: 340, y: 280)
        )
    }

    private func withSettings(_ body: (SettingsStore) -> Void) {
        let suiteName = "SCCaptureSessionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        body(SettingsStore(defaults: defaults))
    }
}
