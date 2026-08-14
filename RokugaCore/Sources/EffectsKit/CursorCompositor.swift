import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import Metal

/// Maps global CG (top-left) screen points into captured-frame pixel coordinates.
public struct FrameGeometry: Equatable, Sendable {
    /// Captured area in global CG top-left coordinates (display frame ∩ crop).
    public var contentRect: CGRect
    /// Output frame size in pixels.
    public var pixelSize: CGSize

    public init(contentRect: CGRect, pixelSize: CGSize) {
        self.contentRect = contentRect
        self.pixelSize = pixelSize
    }

    public var scale: CGFloat {
        guard contentRect.width > 0 else { return 1 }
        return pixelSize.width / contentRect.width
    }

    /// Frame pixel position (top-left origin) for a global point; nil when outside the frame.
    public func pixelPosition(of globalPoint: CGPoint) -> CGPoint? {
        guard contentRect.insetBy(dx: -64, dy: -64).contains(globalPoint) else { return nil }
        return CGPoint(
            x: (globalPoint.x - contentRect.minX) * scale,
            y: (globalPoint.y - contentRect.minY) * scale
        )
    }
}

/// Metal-backed cursor compositor (task 6.1). Renders cursor/halo/click layers into
/// recorded frames only — the live screen is never touched. The full-resolution frame
/// stays on the GPU (CoreImage over IOSurface); only the tiny cursor overlay (~256 px)
/// is rasterized on the CPU each frame.
public final class CursorCompositor: @unchecked Sendable {
    private let options: CursorEffectOptions
    private let geometry: FrameGeometry
    private let sampler: CursorStateSampling
    private let budget: FrameBudgetMonitor
    private let onDegradeToNativeCursor: @Sendable () -> Void

    private let context: CIContext
    private var pool: CVPixelBufferPool?
    private var notifiedNativeFallback = false

    public init(
        options: CursorEffectOptions,
        geometry: FrameGeometry,
        sampler: CursorStateSampling,
        budget: FrameBudgetMonitor = FrameBudgetMonitor(),
        onDegradeToNativeCursor: @escaping @Sendable () -> Void = {}
    ) {
        self.options = options
        self.geometry = geometry
        self.sampler = sampler
        self.budget = budget
        self.onDegradeToNativeCursor = onDegradeToNativeCursor
        if let device = MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        } else {
            context = CIContext(options: [.cacheIntermediates: false])
        }
    }

    /// Composite cursor layers over the frame; returns the original buffer untouched
    /// on the passthrough path or after full degradation.
    public func composite(_ sampleBuffer: CMSampleBuffer) -> CMSampleBuffer {
        guard !options.isPassthrough else { return sampleBuffer }

        let level = budget.currentLevel
        if level == .nativeCursor {
            if !notifiedNativeFallback {
                notifiedNativeFallback = true
                onDegradeToNativeCursor()
            }
            return sampleBuffer
        }

        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return sampleBuffer }

        let started = CFAbsoluteTimeGetCurrent()
        defer { budget.record(frameSeconds: CFAbsoluteTimeGetCurrent() - started) }

        let snapshot = sampler.snapshot()
        guard let overlay = CursorOverlayRenderer.render(
            snapshot: snapshot,
            options: options,
            geometry: geometry,
            level: level,
            now: ProcessInfo.processInfo.systemUptime
        ) else {
            return sampleBuffer
        }

        guard let output = makeOutputBuffer(like: imageBuffer) else { return sampleBuffer }

        let base = CIImage(cvPixelBuffer: imageBuffer)
        let frameHeight = CGFloat(CVPixelBufferGetHeight(imageBuffer))
        // CoreImage is bottom-left origin; overlay rect comes in top-left pixel coordinates.
        let overlayImage = CIImage(cgImage: overlay.image)
            .transformed(by: CGAffineTransform(
                translationX: overlay.rect.minX,
                y: frameHeight - overlay.rect.maxY
            ))
        let composited = overlayImage.composited(over: base)
        context.render(composited, to: output)

        return retimedSampleBuffer(from: sampleBuffer, imageBuffer: output) ?? sampleBuffer
    }

    private func makeOutputBuffer(like source: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        if pool == nil {
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: CVPixelBufferGetPixelFormatType(source),
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
                kCVPixelBufferMetalCompatibilityKey as String: true,
            ]
            CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
        }
        guard let pool else { return nil }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        return buffer
    }

    private func retimedSampleBuffer(from source: CMSampleBuffer, imageBuffer: CVPixelBuffer) -> CMSampleBuffer? {
        var formatDescription: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: nil,
            imageBuffer: imageBuffer,
            formatDescriptionOut: &formatDescription
        )
        guard let formatDescription else { return nil }

        var timing = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(source),
            presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(source),
            decodeTimeStamp: CMSampleBufferGetDecodeTimeStamp(source)
        )
        var output: CMSampleBuffer?
        CMSampleBufferCreateForImageBuffer(
            allocator: nil,
            imageBuffer: imageBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &output
        )
        return output
    }
}

/// CPU rasterizer for the small cursor overlay tile.
enum CursorOverlayRenderer {
    struct Overlay {
        let image: CGImage
        /// Placement in frame pixel coordinates (top-left origin).
        let rect: CGRect
    }

    static func render(
        snapshot: CursorSnapshot,
        options: CursorEffectOptions,
        geometry: FrameGeometry,
        level: FrameBudgetMonitor.Level,
        now: TimeInterval
    ) -> Overlay? {
        guard let center = geometry.pixelPosition(of: snapshot.location) else { return nil }

        let scale = geometry.scale
        let tileSide: CGFloat = 256 * max(scale, 1)
        let tileOrigin = CGPoint(x: center.x - tileSide / 2, y: center.y - tileSide / 2)

        guard let ctx = CGContext(
            data: nil,
            width: Int(tileSide),
            height: Int(tileSide),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        // CGContext is bottom-left origin; flip so drawing math is top-left like the frame.
        ctx.translateBy(x: 0, y: tileSide)
        ctx.scaleBy(x: 1, y: -1)

        let local = CGPoint(x: tileSide / 2, y: tileSide / 2)

        if options.animateClicks, level < .noClickAnimations {
            for ripple in ClickRipple.progresses(clicks: snapshot.clicks, now: now) {
                guard let ripplePixel = geometry.pixelPosition(of: ripple.location) else { continue }
                let rippleLocal = CGPoint(
                    x: ripplePixel.x - tileOrigin.x,
                    y: ripplePixel.y - tileOrigin.y
                )
                let radius = (10 + 34 * ripple.progress) * scale
                ctx.setStrokeColor(CGColor(red: 1, green: 0.85, blue: 0.2, alpha: 0.85 * (1 - ripple.progress)))
                ctx.setLineWidth(2.5 * scale)
                ctx.strokeEllipse(in: CGRect(
                    x: rippleLocal.x - radius,
                    y: rippleLocal.y - radius,
                    width: radius * 2,
                    height: radius * 2
                ))
            }
        }

        if options.highlight, level < .noHighlight {
            let radius = 22 * scale
            ctx.setFillColor(CGColor(red: 1, green: 0.9, blue: 0.25, alpha: 0.3))
            ctx.fillEllipse(in: CGRect(
                x: local.x - radius,
                y: local.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
        }

        if options.showCursor {
            switch options.pointerStyle {
            case .dot:
                let radius = 7 * scale
                ctx.setFillColor(CGColor(red: 1, green: 0.23, blue: 0.19, alpha: 0.95))
                ctx.fillEllipse(in: CGRect(
                    x: local.x - radius,
                    y: local.y - radius,
                    width: radius * 2,
                    height: radius * 2
                ))
            case .system:
                if let image = snapshot.image {
                    let size = CGSize(
                        width: snapshot.imagePointSize.width * scale,
                        height: snapshot.imagePointSize.height * scale
                    )
                    let origin = CGPoint(
                        x: local.x - snapshot.imageHotSpot.x * scale,
                        y: local.y - snapshot.imageHotSpot.y * scale
                    )
                    ctx.saveGState()
                    ctx.translateBy(x: origin.x, y: origin.y + size.height)
                    ctx.scaleBy(x: 1, y: -1)
                    ctx.draw(image, in: CGRect(origin: .zero, size: size))
                    ctx.restoreGState()
                }
            }
        }

        guard let image = ctx.makeImage() else { return nil }
        return Overlay(image: image, rect: CGRect(origin: tileOrigin, size: CGSize(width: tileSide, height: tileSide)))
    }
}
