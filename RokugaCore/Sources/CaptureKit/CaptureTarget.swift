import CoreGraphics
import Foundation

public struct DisplayTarget: Equatable, Sendable {
    public let displayID: CGDirectDisplayID
    /// Display bounds in global points.
    public let frame: CGRect
    public let pixelWidth: Int
    public let pixelHeight: Int

    public init(displayID: CGDirectDisplayID, frame: CGRect, pixelWidth: Int, pixelHeight: Int) {
        self.displayID = displayID
        self.frame = frame
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    public var pointToPixelScale: CGFloat {
        frame.width > 0 ? CGFloat(pixelWidth) / frame.width : 1
    }
}

/// Window picker metadata (task 2.3).
public struct WindowTarget: Equatable, Sendable {
    public let windowID: CGWindowID
    public let title: String?
    public let appName: String?
    public let appBundleID: String?
    public let appPID: pid_t
    /// Window frame in global points.
    public let frame: CGRect

    public init(
        windowID: CGWindowID,
        title: String?,
        appName: String?,
        appBundleID: String?,
        appPID: pid_t,
        frame: CGRect
    ) {
        self.windowID = windowID
        self.title = title
        self.appName = appName
        self.appBundleID = appBundleID
        self.appPID = appPID
        self.frame = frame
    }
}

public enum CaptureTarget: Equatable, Sendable {
    /// Full display, or a cropped region of it when `crop` is non-nil (display-local points).
    case display(DisplayTarget, crop: CGRect?)
    case window(WindowTarget)

    /// Captured area in global CG (top-left) coordinates, before any crop.
    public var globalFrame: CGRect {
        switch self {
        case let .display(display, _):
            return display.frame
        case let .window(window):
            return window.frame
        }
    }

    /// Output pixel dimensions before the 5K clamp.
    public var sourcePixelSize: (width: Int, height: Int) {
        switch self {
        case let .display(display, crop):
            guard let crop else { return (display.pixelWidth, display.pixelHeight) }
            let scale = display.pointToPixelScale
            return (Int(crop.width * scale), Int(crop.height * scale))
        case let .window(window):
            // Windows capture at 2x backing scale on Retina; SCStream sizes the surface.
            return (Int(window.frame.width * 2), Int(window.frame.height * 2))
        }
    }
}
