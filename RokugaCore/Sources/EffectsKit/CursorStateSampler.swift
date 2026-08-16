import AppKit
import Foundation

/// A point-in-time snapshot of cursor state, in global CG (top-left origin) coordinates.
public struct CursorSnapshot: Sendable {
    public var location: CGPoint
    public var image: CGImage?
    public var imageHotSpot: CGPoint
    public var imagePointSize: CGSize
    /// Click timestamps (host clock) with locations, newest last.
    public var clicks: [(time: TimeInterval, location: CGPoint)]

    public init(
        location: CGPoint,
        image: CGImage?,
        imageHotSpot: CGPoint = .zero,
        imagePointSize: CGSize = .zero,
        clicks: [(time: TimeInterval, location: CGPoint)] = []
    ) {
        self.location = location
        self.image = image
        self.imageHotSpot = imageHotSpot
        self.imagePointSize = imagePointSize
        self.clicks = clicks
    }
}

public protocol CursorStateSampling: Sendable {
    func snapshot() -> CursorSnapshot
}

/// Samples cursor position/image on the main thread at 30 Hz and records global clicks,
/// so the frame path (task 6.1) never hops to the main thread.
public final class CursorStateSampler: CursorStateSampling, @unchecked Sendable {
    private let lock = NSLock()
    private var latest = CursorSnapshot(location: .zero, image: nil)
    private var clicks: [(time: TimeInterval, location: CGPoint)] = []
    private var timer: Timer?
    private var clickMonitor: Any?

    public init() {}

    @MainActor
    public func start() {
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.sampleOnMain()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        sampleOnMain()

        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self else { return }
            let location = CGEvent(source: nil)?.location ?? .zero
            lock.withLock {
                self.clicks = [(time: ProcessInfo.processInfo.systemUptime, location: location)]
            }
        }
    }

    @MainActor
    public func stop() {
        timer?.invalidate()
        timer = nil
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
    }

    private func sampleOnMain() {
        let location = CGEvent(source: nil)?.location ?? .zero
        let cursor = NSCursor.currentSystem ?? NSCursor.arrow
        let image = cursor.image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        let hotSpot = cursor.hotSpot
        let size = cursor.image.size
        lock.withLock {
            latest = CursorSnapshot(
                location: location,
                image: image,
                imageHotSpot: hotSpot,
                imagePointSize: size,
                clicks: latest.clicks
            )
        }
    }

    public func snapshot() -> CursorSnapshot {
        lock.withLock {
            var snap = latest
            let cutoff = ProcessInfo.processInfo.systemUptime - ClickRipple.lifetime
            clicks.removeAll { $0.time < cutoff }
            snap.clicks = clicks
            return snap
        }
    }
}

/// Native-style click indicator timeline (pure math, unit tested).
public enum ClickRipple {
    public static let lifetime: TimeInterval = 0.5
    static let radius: CGFloat = 40
    static let fadeStartProgress = 0.4

    /// Progress values in 0...1 for clicks still animating at `now`.
    public static func progresses(
        clicks: [(time: TimeInterval, location: CGPoint)],
        now: TimeInterval
    ) -> [(progress: Double, location: CGPoint)] {
        clicks.compactMap { click in
            let age = now - click.time
            guard age >= 0, age < lifetime else { return nil }
            return (progress: age / lifetime, location: click.location)
        }
    }

    static func opacity(at progress: Double) -> CGFloat {
        let clamped = min(max(progress, 0), 1)
        guard clamped > fadeStartProgress else { return 1 }
        let fadeProgress = (clamped - fadeStartProgress) / (1 - fadeStartProgress)
        let eased = fadeProgress * fadeProgress * (3 - 2 * fadeProgress)
        return CGFloat(1 - eased)
    }
}
