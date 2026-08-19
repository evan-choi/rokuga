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

/// Backing scale of the display a rect actually sits on — a 1x-display window captured at an assumed 2x produces a quarter-size image in a black frame.
public enum DisplayScale {
    static func displayID(forCGRect rect: CGRect) -> CGDirectDisplayID? {
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetDisplaysWithRect(rect, 16, &displays, &count)
        guard count > 0 else { return nil }

        var bestArea: CGFloat = -1
        var bestDisplayID: CGDirectDisplayID?
        for index in 0..<Int(count) {
            let bounds = CGDisplayBounds(displays[index])
            let intersection = bounds.intersection(rect)
            let area = intersection.width * intersection.height
            guard area > bestArea else { continue }
            bestArea = area
            bestDisplayID = displays[index]
        }
        return bestDisplayID
    }

    public static func scale(forCGRect rect: CGRect) -> CGFloat {
        guard let displayID = displayID(forCGRect: rect) else { return 2 }
        let bounds = CGDisplayBounds(displayID)
        guard bounds.width > 0 else { return 2 }
        let pixelWidth = CGDisplayCopyDisplayMode(displayID)?.pixelWidth ?? Int(bounds.width)
        return CGFloat(pixelWidth) / bounds.width
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

    private var displayID: CGDirectDisplayID? {
        switch self {
        case let .display(display, _):
            return display.displayID
        case let .window(window):
            return DisplayScale.displayID(forCGRect: window.frame)
        }
    }

    public var displayRefreshRate: Double? {
        guard let displayID,
              let refreshRate = CGDisplayCopyDisplayMode(displayID)?.refreshRate,
              refreshRate > 0
        else { return nil }
        return refreshRate
    }

    /// Output pixel dimensions before the 5K clamp.
    public var sourcePixelSize: (width: Int, height: Int) {
        switch self {
        case let .display(display, crop):
            guard let crop else { return (display.pixelWidth, display.pixelHeight) }
            let scale = display.pointToPixelScale
            return (Int(crop.width * scale), Int(crop.height * scale))
        case let .window(window):
            let scale = DisplayScale.scale(forCGRect: window.frame)
            return (Int(window.frame.width * scale), Int(window.frame.height * scale))
        }
    }
}
