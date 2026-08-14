import AppKit
import SwiftUI

/// Pixel loupe shown while drag-creating or resizing a region (task 4.5).
/// Samples the live display around the cursor for pixel-precise edge placement.
struct PixelLoupeView: View {
    let point: CGPoint
    let displayID: CGDirectDisplayID
    let displaySize: CGSize

    private static let sampleSide: CGFloat = 21
    private static let loupeSide: CGFloat = 126

    var body: some View {
        VStack(spacing: 4) {
            loupe
            Text(verbatim: "\(Int(point.x)), \(Int(point.y))")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.black.opacity(0.75)))
                .foregroundStyle(.white)
        }
        .position(loupePosition)
        .allowsHitTesting(false)
    }

    private var loupe: some View {
        ZStack {
            if let sample = LoupeSampler.capture(around: point, displayID: displayID) {
                Image(decorative: sample, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: Self.loupeSide, height: Self.loupeSide)
            } else {
                Color.black
            }
            // Center pixel crosshair
            Rectangle()
                .stroke(Color.red, lineWidth: 1)
                .frame(
                    width: Self.loupeSide / Self.sampleSide,
                    height: Self.loupeSide / Self.sampleSide
                )
        }
        .frame(width: Self.loupeSide, height: Self.loupeSide)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 2))
        .shadow(radius: 8)
    }

    /// Offset the loupe away from the cursor, flipping quadrant near display edges.
    private var loupePosition: CGPoint {
        let offset: CGFloat = 90
        let x = point.x + (point.x > displaySize.width - 170 ? -offset : offset)
        let y = point.y + (point.y < 170 ? offset : -offset)
        return CGPoint(x: x, y: y)
    }
}

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
