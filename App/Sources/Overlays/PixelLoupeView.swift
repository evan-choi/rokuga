import AppKit

/// Live-display sampling for the pixel loupe drawn by `AreaSelectionView` (task 4.5).
enum LoupeSampler {
    static func capture(around point: CGPoint, displayID: CGDirectDisplayID) -> CGImage? {
        let side = PixelLoupeSampleRect.side
        let rect = CGRect(
            x: point.x - side / 2,
            y: point.y - side / 2,
            width: side,
            height: side
        )
        return CGDisplayCreateImage(displayID, rect: rect)
    }
}

enum PixelLoupeSampleRect {
    static let side: CGFloat = 21
}
